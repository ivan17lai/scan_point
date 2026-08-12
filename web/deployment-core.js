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

  function customizeStationArchive(zip, stationValues, cloudValues) {
    for (const name of Object.keys(zip.files)) {
      if (/(^|\/)(station\.json|cloud\.config|upload\.key|開始使用\.txt)$/i.test(name)) {
        zip.remove(name);
      }
    }
    zip.file(
      "station.json",
      `${JSON.stringify(buildStationConfig(stationValues), null, 2)}\n`,
    );
    zip.file("cloud.config", buildCloudConfig(cloudValues));
    zip.file("開始使用.txt", buildGettingStartedText());
    return zip;
  }

  return {
    appsScriptEndpointPattern,
    buildCloudConfig,
    buildGettingStartedText,
    buildKeyBundle,
    buildStationConfig,
    customizeStationArchive,
    isValidAppsScriptUrl,
    isValidKey,
    normalizeCloudConfig,
    parseSpreadsheetId,
  };
});
