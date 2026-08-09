"use strict";

const elements = {
  codePreview: document.querySelector("#code-preview"),
  copyCode: document.querySelector("#copy-code"),
  codeStatus: document.querySelector("#code-status"),
  spreadsheetSource: document.querySelector("#spreadsheet-source"),
  spreadsheetId: document.querySelector("#spreadsheet-id"),
  copySpreadsheetId: document.querySelector("#copy-spreadsheet-id"),
  uploadKey: document.querySelector("#upload-key"),
  copyUploadKey: document.querySelector("#copy-upload-key"),
  generateKey: document.querySelector("#generate-key"),
  stationUploadKey: document.querySelector("#station-upload-key"),
  stationForm: document.querySelector("#station-form"),
  formStatus: document.querySelector("#form-status"),
  pageProgressLinks: document.querySelectorAll("[data-progress-section]"),
  pageProgressNav: document.querySelector(".page-progress__nav"),
  pageProgressBar: document.querySelector("#page-progress-bar"),
  pageProgressLabel: document.querySelector("#page-progress-label"),
};

let codeGs = "";
let progressFrame = 0;
let lastProgressIndex = -1;
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
  elements.uploadKey.value = key;
  elements.stationUploadKey.value = key;
}

function parseSpreadsheetId(value) {
  const trimmed = value.trim();
  const urlMatch = trimmed.match(/\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
  if (urlMatch) return urlMatch[1];
  return /^[a-zA-Z0-9_-]{20,}$/.test(trimmed) ? trimmed : "";
}

function updateSpreadsheetId() {
  const id = parseSpreadsheetId(elements.spreadsheetSource.value);
  elements.spreadsheetId.value = id || "尚未辨識";
  elements.copySpreadsheetId.disabled = !id;
}

function safeFilenamePart(value) {
  return value.trim().replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/^-+|-+$/g, "");
}

function downloadJson(value) {
  const json = `${JSON.stringify(value, null, 2)}\n`;
  const blob = new Blob([json], {type: "application/json;charset=utf-8"});
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "station.json";
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

async function loadCodeGs() {
  try {
    const response = await fetch("google_apps_script/Code.gs", {cache: "no-store"});
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    codeGs = await response.text();
    elements.codePreview.textContent = codeGs;
    elements.copyCode.disabled = false;
    setStatus(elements.codeStatus, "程式碼已就緒", "success");
  } catch (_) {
    setStatus(
      elements.codeStatus,
      "無法載入程式碼，請使用「下載 Code.gs」或從 GitHub Pages 開啟本頁。",
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
  const copied = await copyText(codeGs);
  setStatus(
    elements.codeStatus,
    copied ? "Code.gs 已複製" : "瀏覽器拒絕存取剪貼簿，請展開預覽後手動複製。",
    copied ? "success" : "error",
  );
});

elements.spreadsheetSource.addEventListener("input", updateSpreadsheetId);

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

elements.stationForm.addEventListener("submit", (event) => {
  event.preventDefault();

  const stationId = document.querySelector("#station-id").value.trim();
  const stationName = document.querySelector("#station-name").value.trim();
  const pin = document.querySelector("#station-pin").value.replace(/\D/g, "");
  const uploadUrl = document.querySelector("#upload-url").value.trim();
  const extraDir = document.querySelector("#extra-dir").value.trim();

  if (!stationId || !stationName) {
    setStatus(elements.formStatus, "請填寫站點編號與站點名稱。", "error");
    return;
  }
  if (pin.length < 4) {
    setStatus(elements.formStatus, "管理 PIN 至少需要 4 位數字。", "error");
    return;
  }
  if (uploadUrl && !/^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec$/.test(uploadUrl)) {
    setStatus(elements.formStatus, "部署網址格式不正確，應為 script.google.com 且以 /exec 結尾。", "error");
    return;
  }

  downloadJson({
    station_id: stationId,
    station_name: stationName,
    pin,
    upload_url: uploadUrl,
    upload_token: elements.stationUploadKey.value,
    extra_dir: extraDir,
  });

  const stationLabel = safeFilenamePart(stationId) || "station";
  setStatus(elements.formStatus, `${stationLabel} 的 station.json 已下載。`, "success");
});

applyUploadKey(generateUploadKey());
loadCodeGs();
updatePageProgress();
