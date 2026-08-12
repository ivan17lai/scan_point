"use strict";

const deploymentCore = window.ScanPointDeploymentCore;

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
  stationForm: document.querySelector("#station-form"),
  downloadCompletePackage: document.querySelector("#download-complete-package"),
  downloadKeyBundle: document.querySelector("#download-key-bundle"),
  idMappingFile: document.querySelector("#id-mapping-file"),
  clearIdMapping: document.querySelector("#clear-id-mapping"),
  idMappingStatus: document.querySelector("#id-mapping-status"),
  formStatus: document.querySelector("#form-status"),
  deploymentModeButtons: document.querySelectorAll("[data-deployment-mode]"),
  deploymentModeHelp: document.querySelector("#deployment-mode-help"),
  cloudOnlyElements: document.querySelectorAll("[data-cloud-only]"),
  offlineOnlyElements: document.querySelectorAll("[data-offline-only]"),
  downloadStepNumbers: document.querySelectorAll("[data-download-step-number]"),
  finishStepNumbers: document.querySelectorAll("[data-finish-step-number]"),
  downloadNavLabel: document.querySelector("[data-download-nav-label]"),
  downloadKicker: document.querySelector("[data-download-kicker]"),
  downloadTitle: document.querySelector("[data-download-title]"),
  downloadButtonLabel: document.querySelector("[data-download-button-label]"),
  pageProgressLinks: document.querySelectorAll("[data-progress-section]"),
  pageProgressNav: document.querySelector(".page-progress__nav"),
  pageProgressBar: document.querySelector("#page-progress-bar"),
  pageProgressLabel: document.querySelector("#page-progress-label"),
};

let rawCodeGs = "";
let preparedCodeGs = "";
let keyMode = "auto";
let deploymentMode = "cloud";
const keyValues = {upload: "", read: ""};
let progressFrame = 0;
let lastProgressIndex = -1;
const latestWindowsPackageUrl = "downloads/scan_point-windows-x64.zip";
let preparedIdMapping = null;

function setStatus(element, message, tone = "") {
  element.textContent = message;
  if (tone) {
    element.dataset.tone = tone;
  } else {
    delete element.dataset.tone;
  }
}

function idMappingErrorMessage(error) {
  const code = error instanceof Error ? error.message : "";
  return {
    ID_MAPPING_TOO_LARGE: "對照表不可超過 2 MB。",
    ID_MAPPING_EMPTY: "對照表沒有任何資料。",
    ID_MAPPING_QUOTES_INVALID: "CSV 引號沒有正確關閉。",
    ID_MAPPING_JSON_INVALID: "JSON 格式不正確。",
    ID_MAPPING_HEADER_INVALID: "第一列標題必須包含 id 與 text。",
    ID_MAPPING_ENTRY_INVALID: "每一列都必須有 ID 與自訂文字。",
    ID_MAPPING_ENTRY_TOO_LONG: "對照表內有過長的 ID 或自訂文字。",
    ID_MAPPING_DUPLICATE: "對照表含有重複 ID。",
    ID_MAPPING_TOO_MANY: "對照表最多可包含 10000 筆。",
  }[code] || "無法讀取對照表，請確認檔案格式。";
}

function clearPreparedIdMapping() {
  preparedIdMapping = null;
  elements.idMappingFile.value = "";
  elements.clearIdMapping.hidden = true;
  setStatus(
    elements.idMappingStatus,
    "尚未選擇檔案；下載的軟體會顯示原始 ID。",
  );
}

async function handleIdMappingFile() {
  const [file] = elements.idMappingFile.files;
  if (!file) {
    clearPreparedIdMapping();
    return;
  }
  try {
    preparedIdMapping = deploymentCore.normalizeIdMapping(
      await file.text(),
      file.name,
    );
    elements.clearIdMapping.hidden = false;
    setStatus(
      elements.idMappingStatus,
      `${file.name} · 已載入 ${preparedIdMapping.entries.length} 筆，會一併放入 ZIP。`,
      "success",
    );
  } catch (error) {
    clearPreparedIdMapping();
    setStatus(elements.idMappingStatus, idMappingErrorMessage(error), "error");
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
  return deploymentCore.isValidKey(value);
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
      "請先回到第 1 步貼上空白試算表連結。辨識成功後，這裡會提供可直接貼上的完整程式碼。";
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
      "下方是支援指令碼屬性的完整程式碼。貼上並儲存後，還要回到「專案設定」新增第 1 步列出的三組名稱和值。";
  } else {
    elements.keyModeHelp.textContent =
      "已選擇推薦方式。第 1 步提供的完整程式碼已包含試算表 ID 與兩組金鑰，不必再新增指令碼屬性。";
    elements.keyModeSummary.textContent =
      "頁面會把試算表 ID 與兩組金鑰直接填入完整程式碼。";
    elements.codeKeyModeNote.textContent =
      "下方是已填好試算表 ID 與兩組金鑰的完整程式碼。請整份複製並取代 Apps Script 編輯器中原本的範例程式。";
  }

  updatePropertyValues();
  updatePreparedCode();
}
function parseSpreadsheetId(value) {
  return deploymentCore.parseSpreadsheetId(value);
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
    elements.codePreview.textContent = "請先回到第 1 步，貼上你建立的空白試算表完整連結。";
    elements.copyCode.disabled = true;
    elements.downloadCode.disabled = true;
    setStatus(elements.codeStatus, "尚未辨識到試算表，請先貼上完整連結。", "error");
    return;
  }
  if (!isValidKey(uploadKey) || !isValidKey(readKey)) {
    preparedCodeGs = "";
    elements.codePreview.textContent =
      "第 1 步的兩組金鑰尚未準備完成，請回到上方重新產生。";
    elements.copyCode.disabled = true;
    elements.downloadCode.disabled = true;
    setStatus(elements.codeStatus, "兩組金鑰尚未準備完成，暫時不能產生完整程式碼。", "error");
    return;
  }
  if (!keyMode) {
    preparedCodeGs = "";
    elements.codePreview.textContent = "試算表已辨識，請回到第 1 步選擇設定方式。";
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

function visibleProgressEntries() {
  return Array.from(elements.pageProgressLinks)
    .filter((link) => !link.hidden)
    .map((link) => ({
      link,
      section: document.querySelector("#" + link.dataset.progressSection),
    }))
    .filter((entry) => entry.section && !entry.section.hidden);
}

function updatePageProgress() {
  const entries = visibleProgressEntries();
  if (!entries.length) return;
  const markerPosition = window.scrollY + window.innerHeight * 0.38;
  let activeIndex = 0;

  entries.forEach((entry, index) => {
    const sectionTop = entry.section.getBoundingClientRect().top + window.scrollY;
    if (sectionTop <= markerPosition) activeIndex = index;
  });

  const pageBottom = window.scrollY + window.innerHeight;
  if (pageBottom >= document.documentElement.scrollHeight - 4) {
    activeIndex = entries.length - 1;
  }

  if (activeIndex === lastProgressIndex) return;
  lastProgressIndex = activeIndex;

  elements.pageProgressLinks.forEach((link) => link.removeAttribute("aria-current"));
  entries[activeIndex].link.setAttribute("aria-current", "step");

  const completed = ((activeIndex + 1) / entries.length) * 100;
  elements.pageProgressBar.style.width = completed + "%";
  elements.pageProgressLabel.value =
    "步驟 " + (activeIndex + 1) + " / " + entries.length;

  if (window.matchMedia("(max-width: 1080px)").matches) {
    const activeLink = entries[activeIndex].link;
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


function setDeploymentMode(mode) {
  if (mode !== "cloud" && mode !== "offline") return;
  deploymentMode = mode;
  const offline = mode === "offline";
  elements.deploymentModeButtons.forEach((button) => {
    const selected = button.dataset.deploymentMode === mode;
    button.classList.toggle("is-selected", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
  elements.cloudOnlyElements.forEach((element) => { element.hidden = offline; });
  elements.offlineOnlyElements.forEach((element) => { element.hidden = !offline; });
  elements.downloadStepNumbers.forEach((element) => { element.textContent = offline ? "01" : "04"; });
  elements.finishStepNumbers.forEach((element) => { element.textContent = offline ? "02" : "05"; });
  elements.downloadNavLabel.textContent = offline ? "下載乾淨離線版" : "下載完整掃描站";
  elements.downloadKicker.textContent = offline ? "不加入任何雲端設定" : "產生可直接設定的 Windows 軟體";
  elements.downloadTitle.textContent = offline ? "下載乾淨的離線版軟體" : "下載已含雲端配置的完整最新版";
  elements.downloadButtonLabel.textContent = offline ? "下載乾淨離線版 Windows 軟體" : "下載含雲端配置的 Windows 軟體";
  elements.deploymentModeHelp.textContent = offline
    ? "已選擇離線版。略過 Google 設定，直接到第 1 步下載乾淨軟體。"
    : "已選擇雲端版。請先在 Google Drive 建立一份空白試算表，再依步驟完成設定。";
  setStatus(elements.formStatus, "");
  lastProgressIndex = -1;
  window.requestAnimationFrame(updatePageProgress);
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

elements.deploymentModeButtons.forEach((button) => {
  button.addEventListener("click", () => setDeploymentMode(button.dataset.deploymentMode));
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
  try {
    return deploymentCore.normalizeCloudConfig({
      spreadsheetSource: elements.spreadsheetSource.value,
      uploadUrl: document.querySelector("#upload-url").value,
      uploadKey: elements.uploadKey.value,
      readKey: elements.readKey.value,
    });
  } catch (error) {
    const message = {
      SPREADSHEET_ID_INVALID: "找不到試算表 ID，請先回到第 1 步貼上空白試算表連結。",
      UPLOAD_URL_INVALID: "請貼上第 3 步取得、以 /exec 結尾的 Apps Script 正式網址。",
      UPLOAD_KEY_INVALID: "上傳金鑰尚未準備完成，請先回到第 1 步。",
      READ_KEY_INVALID: "讀取金鑰尚未準備完成，請先回到第 1 步。",
    }[error.message] || "雲端配置無效，請重新檢查前面的步驟。";
    setStatus(elements.formStatus, message, "error");
    return null;
  }
}

function downloadCompleteKeyBundle() {
  const values = readCloudConfigValues();
  if (!values) return;
  const bundle = deploymentCore.buildKeyBundle(values);
  downloadText(
    `${JSON.stringify(bundle, null, 2)}\n`,
    "scanpoint-keys.json",
    "application/json;charset=utf-8",
  );
  setStatus(
    elements.formStatus,
    "完整鑰匙檔已下載。請安全保存；成績計算時只需匯入這一個檔案。",
    "success",
  );
}

function setStationDownloadBusy(busy) {
  elements.downloadCompletePackage.disabled = busy;
  elements.downloadKeyBundle.disabled = busy;
  elements.idMappingFile.disabled = busy;
  elements.clearIdMapping.disabled = busy;
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

async function downloadCompleteStationPackage(stationValues, cloudValues, idMapping) {
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
    deploymentCore.customizeStationArchive(zip, stationValues, cloudValues, idMapping);

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


async function downloadOfflinePackage(idMapping) {
  if (!window.JSZip) {
    throw new Error("ZIP 元件未載入，請重新整理頁面後再試一次。");
  }

  setStationDownloadBusy(true);
  setStatus(elements.formStatus, "正在取得最新的乾淨離線版軟體，請稍候…");
  try {
    const response = await fetch(latestWindowsPackageUrl, {cache: "no-store"});
    if (!response.ok) {
      throw new Error(
        response.status === 404
          ? "最新 Windows 軟體仍在建置中，請等 GitHub Actions 完成後再試一次。"
          : `無法下載最新 Windows 軟體（HTTP ${response.status}）。`,
      );
    }

    const zip = await window.JSZip.loadAsync(await response.arrayBuffer());
    deploymentCore.customizeOfflineArchive(zip, idMapping);
    const packageBlob = await zip.generateAsync(
      {
        type: "blob",
        compression: "DEFLATE",
        compressionOptions: {level: 6},
      },
      (metadata) => {
        setStatus(
          elements.formStatus,
          `正在產生離線安裝包… ${Math.round(metadata.percent)}%`,
        );
      },
    );
    downloadBlob(packageBlob, "scan_point-windows-x64-offline.zip");
    setStatus(
      elements.formStatus,
      idMapping
        ? `乾淨離線版已下載，並包含 ${idMapping.entries.length} 筆 ID 對照。`
        : "乾淨離線版已下載；不含 cloud.config、試算表 ID、金鑰或對照表。",
      "success",
    );
  } finally {
    setStationDownloadBusy(false);
  }
}

elements.downloadKeyBundle.addEventListener("click", downloadCompleteKeyBundle);
elements.idMappingFile.addEventListener("change", handleIdMappingFile);
elements.clearIdMapping.addEventListener("click", clearPreparedIdMapping);

elements.stationForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (deploymentMode === "offline") {
    try {
      await downloadOfflinePackage(preparedIdMapping);
    } catch (error) {
      setStatus(elements.formStatus, error instanceof Error ? error.message : "離線版下載失敗，請稍後再試。", "error");
    }
    return;
  }
  const cloudValues = readCloudConfigValues();
  if (!cloudValues) return;
  try {
    await downloadCompleteStationPackage(defaultStationConfig, cloudValues, preparedIdMapping);
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
setDeploymentMode("cloud");
loadCodeGs();
