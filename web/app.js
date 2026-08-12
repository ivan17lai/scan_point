"use strict";

const elements = {
  codePreview: document.querySelector("#code-preview"),
  copyCode: document.querySelector("#copy-code"),
  downloadCode: document.querySelector("#download-code"),
  codeStatus: document.querySelector("#code-status"),
  spreadsheetSource: document.querySelector("#spreadsheet-source"),
  spreadsheetId: document.querySelector("#spreadsheet-id"),
  copySpreadsheetId: document.querySelector("#copy-spreadsheet-id"),
  uploadKey: document.querySelector("#upload-key"),
  copyUploadKey: document.querySelector("#copy-upload-key"),
  generateKey: document.querySelector("#generate-key"),
  readKey: document.querySelector("#read-key"),
  copyReadKey: document.querySelector("#copy-read-key"),
  generateReadKey: document.querySelector("#generate-read-key"),
  keyModeButtons: document.querySelectorAll("[data-key-mode]"),
  keyModeHelp: document.querySelector("#key-mode-help"),
  keyModeSummary: document.querySelector("#key-mode-summary"),
  codeKeyModeNote: document.querySelector("#code-key-mode-note"),
  scriptPropertiesPanel: document.querySelector("#script-properties-panel"),
  propertyStepExtra: document.querySelector("#property-step-extra"),
  propertySpreadsheetId: document.querySelector("#property-spreadsheet-id"),
  propertyUploadKey: document.querySelector("#property-upload-key"),
  propertyReadKey: document.querySelector("#property-read-key"),
  propertyCopyButtons: document.querySelectorAll("[data-copy-literal], [data-copy-config]"),
  downloadKeyBackup: document.querySelector("#download-key-backup"),
  keyBackupStatus: document.querySelector("#key-backup-status"),
  stationForm: document.querySelector("#station-form"),
  downloadCompletePackage: document.querySelector("#download-complete-package"),
  formStatus: document.querySelector("#form-status"),
  pageProgressLinks: document.querySelectorAll("[data-progress-section]"),
  pageProgressNav: document.querySelector(".page-progress__nav"),
  pageProgressBar: document.querySelector("#page-progress-bar"),
  pageProgressLabel: document.querySelector("#page-progress-label"),
};

let rawCodeGs = "";
let preparedCodeGs = "";
let keyMode = "auto";
const keyValues = {upload: "", read: ""};
let progressFrame = 0;
let lastProgressIndex = -1;
const latestWindowsPackageUrl = "downloads/scan_point-windows-x64.zip";
const progressSections = Array.from(
  elements.pageProgressLinks,
  (link) => document.querySelector("#" + link.dataset.progressSection),
);

function setStatus(element, message, tone = "") {
  element.textContent = message;
  if (tone) {
    element.dataset.tone = tone;
  } else {
    delete element.dataset.tone;
  }
}

async function copyText(text) {
  if (!text) return false;
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (_) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.append(textarea);
    textarea.select();
    const copied = document.execCommand("copy");
    textarea.remove();
    return copied;
  }
}

function generateUploadKey() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
}

function applyUploadKey(key) {
  keyValues.upload = key;
  elements.uploadKey.value = key;
  elements.copyUploadKey.disabled = !key;
  updatePropertyValues();
  updatePreparedCode();
}

function applyReadKey(key) {
  keyValues.read = key;
  elements.readKey.value = key;
  elements.copyReadKey.disabled = !key;
  updatePropertyValues();
  updatePreparedCode();
}

function isValidKey(value) {
  return value.length >= 16 && !/\s/.test(value);
}

function currentConfigValues() {
  return {
    spreadsheetId: parseSpreadsheetId(elements.spreadsheetSource.value),
    uploadKey: keyValues.upload,
    readKey: keyValues.read,
  };
}

function updatePropertyValues() {
  const values = currentConfigValues();
  elements.propertySpreadsheetId.value = values.spreadsheetId || "尚未貼上連結";
  elements.propertyUploadKey.value = values.uploadKey;
  elements.propertyReadKey.value = values.readKey;
}

function updateKeyModeAvailability(hasSpreadsheetId) {
  elements.keyModeButtons.forEach((button) => {
    const selected = button.dataset.keyMode === keyMode;
    button.disabled = !hasSpreadsheetId;
    button.classList.toggle("is-selected", selected);
    button.setAttribute("aria-pressed", String(selected));
  });

  if (!hasSpreadsheetId) {
    elements.scriptPropertiesPanel.hidden = true;
    elements.propertyStepExtra.hidden = true;
    elements.keyModeHelp.textContent =
      "已預設選中推薦方式。請先貼上空白試算表連結，辨識成功後就會自動套用。";
    elements.keyModeSummary.textContent =
      "先貼上空白試算表連結；完成後頁面會依推薦方式準備完整程式碼。";
    elements.codeKeyModeNote.textContent =
      "請先回到第 2 步貼上空白試算表連結。辨識成功後，這裡會提供可直接貼上的完整程式碼。";
    updatePropertyValues();
    updatePreparedCode();
    return;
  }

  setKeyMode(keyMode || "auto");
}
function setKeyMode(mode) {
  if (mode !== "auto" && mode !== "properties") return;
  keyMode = mode;
  const usesProperties = mode === "properties";

  elements.keyModeButtons.forEach((button) => {
    const selected = button.dataset.keyMode === mode;
    button.classList.toggle("is-selected", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
  elements.uploadKey.readOnly = true;
  elements.readKey.readOnly = true;
  elements.scriptPropertiesPanel.hidden = !usesProperties;
  elements.propertyStepExtra.hidden = !usesProperties;

  if (usesProperties) {
    elements.keyModeHelp.textContent =
      "已選擇自行新增。請把下方三組名稱和值，逐項貼到 Apps Script 的「專案設定 → 指令碼屬性」。";
    elements.keyModeSummary.textContent =
      "這種方式會由 Apps Script 的指令碼屬性保存設定。請完整新增 SPREADSHEET_ID、UPLOAD_KEY、READ_KEY 三組名稱和值。";
    elements.codeKeyModeNote.textContent =
      "下方是支援指令碼屬性的完整程式碼。貼上並儲存後，還要回到「專案設定」新增第 2 步列出的三組名稱和值。";
  } else {
    elements.keyModeHelp.textContent =
      "已選擇推薦方式。第 3 步提供的完整程式碼已包含試算表 ID 與兩組金鑰，不必再新增指令碼屬性。";
    elements.keyModeSummary.textContent =
      "頁面會把試算表 ID 與兩組金鑰直接填入完整程式碼。";
    elements.codeKeyModeNote.textContent =
      "下方是已填好試算表 ID 與兩組金鑰的完整程式碼。請整份複製並取代 Apps Script 編輯器中原本的範例程式。";
  }

  updatePropertyValues();
  updatePreparedCode();
}
function parseSpreadsheetId(value) {
  const trimmed = value.trim();
  const urlMatch = trimmed.match(/\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
  if (urlMatch) return urlMatch[1];
  return /^[a-zA-Z0-9_-]{20,}$/.test(trimmed) ? trimmed : "";
}

function updateSpreadsheetId() {
  const source = elements.spreadsheetSource.value.trim();
  const id = parseSpreadsheetId(source);
  elements.spreadsheetId.value = id
    ? id
    : source
      ? "無法辨識，請確認已貼上完整試算表連結"
      : "尚未貼上連結";
  elements.copySpreadsheetId.disabled = !id;
  updateKeyModeAvailability(Boolean(id));
}
function escapeJavaScriptString(value) {
  return String(value).replaceAll("\\", "\\\\").replaceAll("'", "\\'");
}

function updatePreparedCode() {
  const spreadsheetId = parseSpreadsheetId(elements.spreadsheetSource.value);
  const uploadKey = elements.uploadKey.value;
  const readKey = elements.readKey.value;
  if (!rawCodeGs) {
    preparedCodeGs = "";
    elements.codePreview.textContent = "正在載入完整程式碼範本…";
    elements.copyCode.disabled = true;
    elements.downloadCode.disabled = true;
    return;
  }
  if (!spreadsheetId) {
    preparedCodeGs = "";
    elements.codePreview.textContent = "請先回到第 2 步，貼上你建立的空白試算表完整連結。";
    elements.copyCode.disabled = true;
    elements.downloadCode.disabled = true;
    setStatus(elements.codeStatus, "尚未辨識到試算表，請先貼上完整連結。", "error");
    return;
  }
  if (!isValidKey(uploadKey) || !isValidKey(readKey)) {
    preparedCodeGs = "";
    elements.codePreview.textContent =
      "第 2 步的兩組金鑰尚未準備完成，請回到上方重新產生。";
    elements.copyCode.disabled = true;
    elements.downloadCode.disabled = true;
    setStatus(elements.codeStatus, "兩組金鑰尚未準備完成，暫時不能產生完整程式碼。", "error");
    return;
  }
  if (!keyMode) {
    preparedCodeGs = "";
    elements.codePreview.textContent = "試算表已辨識，請回到第 2 步選擇設定方式。";
    elements.copyCode.disabled = true;
    elements.downloadCode.disabled = true;
    setStatus(elements.codeStatus, "請先選擇「自動填入程式」或「自行新增名稱和值」。", "error");
    return;
  }

  preparedCodeGs = keyMode === "properties"
    ? rawCodeGs
    : rawCodeGs
      .replace("__SCANPOINT_SPREADSHEET_ID__", escapeJavaScriptString(spreadsheetId))
      .replace("__SCANPOINT_UPLOAD_KEY__", escapeJavaScriptString(uploadKey))
      .replace("__SCANPOINT_READ_KEY__", escapeJavaScriptString(readKey));
  elements.codePreview.textContent = preparedCodeGs;
  elements.copyCode.disabled = false;
  elements.downloadCode.disabled = false;
  setStatus(
    elements.codeStatus,
    keyMode === "properties"
      ? "完整程式碼已準備好；貼上後還要新增三個指令碼屬性。"
      : "試算表 ID 與兩組金鑰已填入完整程式碼，可以直接複製。",
    "success",
  );
}

function downloadText(value, filename, mimeType) {
  const blob = new Blob([value], {type: mimeType});
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function downloadKeyBackup() {
  const values = currentConfigValues();
  const backup = {
    format: "scanpoint-key-backup",
    schema_version: 1,
    SPREADSHEET_ID: values.spreadsheetId,
    UPLOAD_KEY: values.uploadKey,
    READ_KEY: values.readKey,
  };
  downloadText(
    `${JSON.stringify(backup, null, 2)}\n`,
    "scanpoint-keys.json",
    "application/json;charset=utf-8",
  );
  setStatus(elements.keyBackupStatus, "金鑰檔已下載。請妥善保存；之後部署掃描站或進入成績計算頁都會用到。", "success");
}

async function loadCodeGs() {
  try {
    const response = await fetch("google_apps_script/Code.gs", {cache: "no-store"});
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    rawCodeGs = await response.text();
    updatePreparedCode();
  } catch (_) {
    rawCodeGs = "";
    preparedCodeGs = "";
    elements.copyCode.disabled = true;
    elements.downloadCode.disabled = true;
    elements.codePreview.textContent = "目前無法載入完整程式碼，請重新整理頁面後再試一次。";
    setStatus(
      elements.codeStatus,
      "無法載入完整程式碼。請確認你是從網站或本機伺服器開啟本頁，再重新整理。",
      "error",
    );
  }
}

function updatePageProgress() {
  const markerPosition = window.scrollY + window.innerHeight * 0.38;
  let activeIndex = 0;

  progressSections.forEach((section, index) => {
    const sectionTop = section.getBoundingClientRect().top + window.scrollY;
    if (section && sectionTop <= markerPosition) activeIndex = index;
  });

  const pageBottom = window.scrollY + window.innerHeight;
  if (pageBottom >= document.documentElement.scrollHeight - 4) {
    activeIndex = progressSections.length - 1;
  }

  if (activeIndex === lastProgressIndex) return;
  lastProgressIndex = activeIndex;

  elements.pageProgressLinks.forEach((link, index) => {
    if (index === activeIndex) {
      link.setAttribute("aria-current", "step");
    } else {
      link.removeAttribute("aria-current");
    }
  });

  const completed = ((activeIndex + 1) / progressSections.length) * 100;
  elements.pageProgressBar.style.width = completed + "%";
  elements.pageProgressLabel.value =
    "步驟 " + (activeIndex + 1) + " / " + progressSections.length;

  if (window.matchMedia("(max-width: 1080px)").matches) {
    const activeLink = elements.pageProgressLinks[activeIndex];
    const left =
      activeLink.offsetLeft -
      (elements.pageProgressNav.clientWidth - activeLink.offsetWidth) / 2;
    elements.pageProgressNav.scrollTo({
      left: Math.max(0, left),
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "auto"
        : "smooth",
    });
  }
}

function schedulePageProgressUpdate() {
  if (progressFrame) return;
  progressFrame = window.requestAnimationFrame(() => {
    progressFrame = 0;
    updatePageProgress();
  });
}

window.addEventListener("scroll", schedulePageProgressUpdate, {passive: true});
window.addEventListener("resize", schedulePageProgressUpdate);

elements.copyCode.addEventListener("click", async () => {
  const copied = await copyText(preparedCodeGs);
  setStatus(
    elements.codeStatus,
    copied ? "完整程式碼已複製，可以回到 Apps Script 貼上。" : "瀏覽器無法使用剪貼簿，請展開程式碼預覽後手動複製。",
    copied ? "success" : "error",
  );
});
elements.downloadCode.addEventListener("click", () => {
  if (!preparedCodeGs) return;
  downloadText(preparedCodeGs, "Code.gs", "text/plain;charset=utf-8");
  setStatus(elements.codeStatus, "完整程式碼已下載，請回到 Apps Script 貼上全部內容。", "success");
});

elements.spreadsheetSource.addEventListener("input", updateSpreadsheetId);

elements.keyModeButtons.forEach((button) => {
  button.addEventListener("click", () => setKeyMode(button.dataset.keyMode));
});

elements.propertyCopyButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    const values = currentConfigValues();
    const value = button.dataset.copyLiteral || values[button.dataset.copyConfig] || "";
    const original = button.textContent;
    const copied = await copyText(value);
    button.textContent = copied ? "已複製" : "尚無可複製的值";
    window.setTimeout(() => {
      button.textContent = original;
    }, 1600);
  });
});

elements.downloadKeyBackup.addEventListener("click", downloadKeyBackup);

elements.copySpreadsheetId.addEventListener("click", async () => {
  const id = parseSpreadsheetId(elements.spreadsheetSource.value);
  const copied = await copyText(id);
  elements.copySpreadsheetId.textContent = copied ? "已複製" : "複製失敗";
  window.setTimeout(() => {
    elements.copySpreadsheetId.textContent = "複製";
  }, 1600);
});

elements.copyUploadKey.addEventListener("click", async () => {
  const copied = await copyText(elements.uploadKey.value);
  elements.copyUploadKey.textContent = copied ? "已複製" : "複製失敗";
  window.setTimeout(() => {
    elements.copyUploadKey.textContent = "複製";
  }, 1600);
});

elements.generateKey.addEventListener("click", () => {
  applyUploadKey(generateUploadKey());
  elements.generateKey.textContent = "已重新產生";
  window.setTimeout(() => {
    elements.generateKey.textContent = "重新產生";
  }, 1600);
});

elements.copyReadKey.addEventListener("click", async () => {
  const copied = await copyText(elements.readKey.value);
  elements.copyReadKey.textContent = copied ? "已複製" : "複製失敗";
  window.setTimeout(() => {
    elements.copyReadKey.textContent = "複製";
  }, 1600);
});

elements.generateReadKey.addEventListener("click", () => {
  applyReadKey(generateUploadKey());
  elements.generateReadKey.textContent = "已重新產生";
  window.setTimeout(() => {
    elements.generateReadKey.textContent = "重新產生";
  }, 1600);
});

const defaultStationConfig = {
  stationId: "CP1",
  stationName: "未命名站點",
  pin: "246810",
  extraDir: "",
};

function readCloudConfigValues() {
  const values = {
    spreadsheetId: parseSpreadsheetId(elements.spreadsheetSource.value),
    uploadUrl: document.querySelector("#upload-url").value.trim(),
    uploadKey: elements.uploadKey.value.trim(),
  };
  if (!values.spreadsheetId) {
    setStatus(elements.formStatus, "找不到試算表 ID，請先回到第 2 步貼上空白試算表連結。", "error");
    return null;
  }
  if (!/^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec$/.test(values.uploadUrl)) {
    setStatus(elements.formStatus, "請貼上第 4 步取得、以 /exec 結尾的 Apps Script 正式網址。", "error");
    return null;
  }
  if (!isValidKey(values.uploadKey)) {
    setStatus(elements.formStatus, "上傳金鑰尚未準備完成，請先回到第 2 步。", "error");
    return null;
  }
  return values;
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

function setStationDownloadBusy(busy) {
  elements.downloadCompletePackage.disabled = busy;
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

async function downloadCompleteStationPackage(stationValues, cloudValues) {
  if (!window.JSZip) {
    throw new Error("ZIP 元件未載入，請重新整理頁面後再試一次。");
  }

  setStationDownloadBusy(true);
  setStatus(elements.formStatus, "正在取得最新 Windows 軟體，請稍候…");
  try {
    const response = await fetch(latestWindowsPackageUrl, {cache: "no-store"});
    if (!response.ok) {
      throw new Error(
        response.status === 404
          ? "最新 Windows 軟體仍在建置中，請等 GitHub Actions 完成後再試一次。"
          : `無法下載最新 Windows 軟體（HTTP ${response.status}）。`,
      );
    }

    setStatus(elements.formStatus, "已取得最新版，正在加入這台站點的設定與金鑰…");
    const zip = await window.JSZip.loadAsync(await response.arrayBuffer());
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
    zip.file(
      "開始使用.txt",
      [
        "ScanPoint 掃描站",
        "",
        "站點：首次啟動時設定",
        "1. 將整個資料夾解壓縮。",
        "2. 保持 station.json 與 cloud.config 在 scan_point.exe 同一資料夾。",
        "3. 第一次執行 scan_point.exe 時，依畫面要求設定站點編號與名稱。",
        "",
        "cloud.config 包含試算表 ID 與上傳金鑰，請勿公開分享。",
      ].join("\r\n"),
    );

    const packageBlob = await zip.generateAsync(
      {
        type: "blob",
        compression: "DEFLATE",
        compressionOptions: {level: 6},
      },
      (metadata) => {
        setStatus(
          elements.formStatus,
          `正在產生完整安裝包… ${Math.round(metadata.percent)}%`,
        );
      },
    );
    downloadBlob(packageBlob, "scan_point-windows-x64.zip");
    setStatus(
      elements.formStatus,
      "完整 Windows 軟體已下載；解壓縮後直接執行 scan_point.exe。",
      "success",
    );
  } finally {
    setStationDownloadBusy(false);
  }
}

elements.stationForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const cloudValues = readCloudConfigValues();
  if (!cloudValues) return;
  try {
    await downloadCompleteStationPackage(defaultStationConfig, cloudValues);
  } catch (error) {
    setStatus(
      elements.formStatus,
      error instanceof Error ? error.message : "完整軟體下載失敗，請稍後再試。",
      "error",
    );
  }
});

applyUploadKey(generateUploadKey());
applyReadKey(generateUploadKey());
updateKeyModeAvailability(false);
loadCodeGs();
updatePageProgress();
