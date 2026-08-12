"use strict";

(function attachDeploymentCore(root, factory) {
  const core = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = core;
  }
  root.ScanPointDeploymentCore = core;
})(typeof globalThis !== "undefined" ? globalThis : this, () => {
  const appsScriptEndpointPattern =
    /^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec$/;

  function parseSpreadsheetId(value) {
    const trimmed = String(value || "").trim();
    const urlMatch = trimmed.match(/\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
    if (urlMatch) return urlMatch[1];
    return /^[a-zA-Z0-9_-]{20,}$/.test(trimmed) ? trimmed : "";
  }

  function isValidKey(value) {
    return typeof value === "string" && value.length >= 16 && !/\s/.test(value);
  }

  function isValidAppsScriptUrl(value) {
    return typeof value === "string" && appsScriptEndpointPattern.test(value.trim());
  }

  function normalizeCloudConfig({spreadsheetSource, uploadUrl, uploadKey, readKey}) {
    const values = {
      spreadsheetId: parseSpreadsheetId(spreadsheetSource),
      uploadUrl: String(uploadUrl || "").trim(),
      uploadKey: String(uploadKey || "").trim(),
      readKey: String(readKey || "").trim(),
    };
    if (!values.spreadsheetId) throw new Error("SPREADSHEET_ID_INVALID");
    if (!isValidAppsScriptUrl(values.uploadUrl)) throw new Error("UPLOAD_URL_INVALID");
    if (!isValidKey(values.uploadKey)) throw new Error("UPLOAD_KEY_INVALID");
    if (!isValidKey(values.readKey)) throw new Error("READ_KEY_INVALID");
    return values;
  }

  function buildKeyBundle(values) {
    return {
      format: "scanpoint-key-backup",
      schema_version: 2,
      SPREADSHEET_ID: values.spreadsheetId,
      UPLOAD_URL: values.uploadUrl,
      UPLOAD_KEY: values.uploadKey,
      READ_KEY: values.readKey,
    };
  }

  function buildStationConfig(values) {
    return {
      station_id: values.stationId,
      station_name: values.stationName,
      pin: values.pin,
      extra_dir: values.extraDir,
    };
  }

  function buildCloudConfig(values) {
    return [
      "# ScanPoint remote upload configuration",
      `SPREADSHEET_ID=${values.spreadsheetId}`,
      `UPLOAD_URL=${values.uploadUrl}`,
      `UPLOAD_KEY=${values.uploadKey}`,
      "",
    ].join("\n");
  }

  function buildGettingStartedText() {
    return [
      "ScanPoint 掃描站",
      "",
      "站點：首次啟動時設定",
      "1. 將整個資料夾解壓縮。",
      "2. 保持 station.json 與 cloud.config 在 scan_point.exe 同一資料夾。",
      "3. 第一次執行 scan_point.exe 時，依畫面要求設定站點編號、名稱與管理 PIN。",
      "",
      "cloud.config 包含試算表 ID 與上傳金鑰，請勿公開分享。",
    ].join("\r\n");
  }

  function parseDelimited(text, delimiter) {
    const rows = [];
    let row = [];
    let cell = "";
    let quoted = false;
    const finishCell = () => {
      row.push(cell);
      cell = "";
    };
    const finishRow = () => {
      finishCell();
      rows.push(row);
      row = [];
    };

    for (let index = 0; index < text.length; index += 1) {
      const char = text[index];
      if (char === '"') {
        if (quoted && text[index + 1] === '"') {
          cell += '"';
          index += 1;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && char === delimiter) {
        finishCell();
      } else if (!quoted && (char === "\n" || char === "\r")) {
        if (char === "\r" && text[index + 1] === "\n") index += 1;
        finishRow();
      } else {
        cell += char;
      }
    }
    if (quoted) throw new Error("ID_MAPPING_QUOTES_INVALID");
    if (cell || row.length) finishRow();
    return rows;
  }

  function jsonMappingPair(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("ID_MAPPING_ENTRY_INVALID");
    }
    return [
      value.id ?? value.card_id ?? value.card ?? value.uid,
      value.text ?? value.label ?? value.name ?? value.display_text,
    ];
  }

  function mappingPairsFromJson(text) {
    let decoded;
    try {
      decoded = JSON.parse(text);
    } catch (_) {
      throw new Error("ID_MAPPING_JSON_INVALID");
    }
    if (Array.isArray(decoded)) return decoded.map(jsonMappingPair);
    if (!decoded || typeof decoded !== "object") {
      throw new Error("ID_MAPPING_JSON_INVALID");
    }
    if (Array.isArray(decoded.entries)) return decoded.entries.map(jsonMappingPair);
    return Object.entries(decoded)
      .filter(([key]) => key !== "format" && key !== "schema_version");
  }

  function mappingPairsFromTable(text) {
    const firstLine = text.split(/\r?\n/, 1)[0];
    const rows = parseDelimited(text, firstLine.includes("\t") ? "\t" : ",");
    if (!rows.length) throw new Error("ID_MAPPING_EMPTY");
    const header = rows[0].map((value) => value.trim().toLowerCase());
    const idIndex = header.findIndex((value) =>
      ["id", "card_id", "card", "uid"].includes(value));
    const textIndex = header.findIndex((value) =>
      ["text", "label", "name", "display_text", "顯示文字", "名稱"].includes(value));
    if (idIndex < 0 || textIndex < 0) throw new Error("ID_MAPPING_HEADER_INVALID");
    return rows.slice(1)
      .filter((row) => row.some((cell) => cell.trim()))
      .map((row) => [row[idIndex], row[textIndex]]);
  }

  function normalizeIdMapping(source, fileName = "") {
    if (typeof source !== "string" || source.length > 2 * 1024 * 1024) {
      throw new Error("ID_MAPPING_TOO_LARGE");
    }
    const text = source.replace(/^\uFEFF/, "").trim();
    if (!text) throw new Error("ID_MAPPING_EMPTY");
    const looksLikeJson =
      fileName.toLowerCase().endsWith(".json") ||
      text.startsWith("{") ||
      text.startsWith("[");
    const pairs = looksLikeJson
      ? mappingPairsFromJson(text)
      : mappingPairsFromTable(text);
    if (!pairs.length) throw new Error("ID_MAPPING_EMPTY");
    if (pairs.length > 10000) throw new Error("ID_MAPPING_TOO_MANY");

    const seen = new Set();
    const entries = pairs.map(([rawId, rawText]) => {
      const id = String(rawId ?? "").trim();
      const displayText = String(rawText ?? "").trim();
      if (!id || !displayText) throw new Error("ID_MAPPING_ENTRY_INVALID");
      if (id.length > 256 || displayText.length > 120) {
        throw new Error("ID_MAPPING_ENTRY_TOO_LONG");
      }
      if (seen.has(id)) throw new Error("ID_MAPPING_DUPLICATE");
      seen.add(id);
      return {id, text: displayText};
    });
    return {
      format: "scanpoint-id-mapping",
      schema_version: 1,
      entries,
    };
  }

  function applyIdMappingToArchive(zip, mapping) {
    for (const name of Object.keys(zip.files)) {
      if (/(^|\/)id-mapping\.json$/i.test(name)) zip.remove(name);
    }
    if (mapping) {
      zip.file("id-mapping.json", `${JSON.stringify(mapping, null, 2)}\n`);
    }
    return zip;
  }

  function customizeStationArchive(zip, stationValues, cloudValues, idMapping = null) {
    for (const name of Object.keys(zip.files)) {
      if (/(^|\/)(station\.json|cloud\.config|upload\.key|id-mapping\.json|開始使用\.txt)$/i.test(name)) {
        zip.remove(name);
      }
    }
    zip.file(
      "station.json",
      `${JSON.stringify(buildStationConfig(stationValues), null, 2)}\n`,
    );
    zip.file("cloud.config", buildCloudConfig(cloudValues));
    zip.file("開始使用.txt", buildGettingStartedText());
    applyIdMappingToArchive(zip, idMapping);
    return zip;
  }

  function customizeOfflineArchive(zip, idMapping = null) {
    for (const name of Object.keys(zip.files)) {
      if (/(^|\/)(cloud\.config|upload\.key|id-mapping\.json)$/i.test(name)) {
        zip.remove(name);
      }
    }
    applyIdMappingToArchive(zip, idMapping);
    return zip;
  }


  return {
    appsScriptEndpointPattern,
    buildCloudConfig,
    buildGettingStartedText,
    buildKeyBundle,
    buildStationConfig,
    customizeStationArchive,
    applyIdMappingToArchive,
    customizeOfflineArchive,
    normalizeIdMapping,
    isValidAppsScriptUrl,
    isValidKey,
    normalizeCloudConfig,
    parseSpreadsheetId,
  };
});
