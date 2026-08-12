"use strict";

const engine = window.ScanPointScoreEngine;
const appsScriptEndpointPattern =
  /^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec$/;

const elements = {
  app: document.querySelector("#score-app"),
  panels: document.querySelectorAll("[data-score-panel]"),
  stepButtons: document.querySelectorAll("[data-go-step]"),
  stepProgress: document.querySelector("#score-step-progress"),
  stepLabel: document.querySelector("#score-step-label"),
  cloudUrl: document.querySelector("#score-cloud-url"),
  readKey: document.querySelector("#score-read-key"),
  keyFile: document.querySelector("#score-key-file"),
  keyFileStatus: document.querySelector("#score-key-file-status"),
  loadCloud: document.querySelector("#load-cloud"),
  fileInput: document.querySelector("#score-files"),
  dropzone: document.querySelector("#score-dropzone"),
  dataStatus: document.querySelector("#score-data-status"),
  dataUnlockHint: document.querySelector("#data-unlock-hint"),
  goToRules: document.querySelector("#go-to-rules"),
  recordCount: document.querySelector("#loaded-record-count"),
  stationCount: document.querySelector("#loaded-station-count"),
  sourceLabel: document.querySelector("#loaded-source"),
  stationOrder: document.querySelector("#station-order"),
  stationChips: document.querySelector("#station-chips"),
  calculate: document.querySelector("#calculate-score"),
  ruleStatus: document.querySelector("#score-rule-status"),
  participantMetric: document.querySelector("#metric-participants"),
  completedMetric: document.querySelector("#metric-completed"),
  stationMetric: document.querySelector("#metric-stations"),
  scanMetric: document.querySelector("#metric-scans"),
  resultBody: document.querySelector("#score-result-body"),
  emptyState: document.querySelector("#score-empty-state"),
  resultView: document.querySelector("#score-result-view"),
  resultStatus: document.querySelector("#score-result-status"),
  search: document.querySelector("#score-search"),
  exportButton: document.querySelector("#export-score"),
  backToRules: document.querySelector("#back-to-rules"),
};

let sourceRecords = [];
let scoreResult = null;
let sourceDescription = "尚未載入";
let activeStep = 1;
let dataReady = false;
let resultReady = false;

function setStatus(element, message, tone = "") {
  element.textContent = message;
  if (tone) element.dataset.tone = tone;
  else delete element.dataset.tone;
}

function stepStatus(step) {
  if (step === activeStep) return "進行中";
  if (step === 1) return dataReady ? "已完成" : "尚未完成";
  if (step === 2) {
    if (!dataReady) return "完成第一步後解鎖";
    return resultReady ? "已完成" : "已解鎖";
  }
  return resultReady ? "可查看" : "計算後開啟";
}

function updateStepAccess() {
  elements.app.dataset.dataReady = String(dataReady);
  elements.stepButtons.forEach((button) => {
    const step = Number(button.dataset.goStep);
    button.disabled =
      (step === 2 && !dataReady) || (step === 3 && !resultReady);
    button.querySelector("small").textContent = stepStatus(step);
  });
}

function goToStep(step) {
  if (step === 2 && !dataReady) return;
  if (step === 3 && !resultReady) return;

  activeStep = step;
  elements.app.dataset.activeStep = String(step);
  elements.app.classList.toggle("is-results", step === 3);

  elements.panels.forEach((panel) => {
    const isActive = Number(panel.dataset.scorePanel) === step;
    panel.hidden = !isActive;
    if (isActive) panel.scrollTop = 0;
  });
  elements.stepButtons.forEach((button) => {
    if (Number(button.dataset.goStep) === step) {
      button.setAttribute("aria-current", "step");
    } else {
      button.removeAttribute("aria-current");
    }
  });

  const progress = `${(step / 3) * 100}%`;
  elements.stepProgress.style.setProperty("--score-progress", progress);
  elements.stepLabel.value = `步驟 ${step} / 3`;
  updateStepAccess();
}

function describeLoaded(records, source) {
  const validRecords = engine.normalizeRecords(records);
  const stations = engine.inferStations(records);
  if (!validRecords.length || !stations.length) {
    throw new Error("資料中沒有可辨識的有效掃描紀錄");
  }

  sourceRecords = records;
  sourceDescription = source;
  dataReady = true;
  resultReady = false;
  scoreResult = null;
  elements.recordCount.textContent = String(validRecords.length);
  elements.stationCount.textContent = String(stations.length);
  elements.sourceLabel.textContent = source;
  elements.stationOrder.value = stations.map((station) => station.id).join(", ");
  renderStationChips(stations);
  resetResults();
  updateStepAccess();
  elements.dataUnlockHint.textContent = "第二步已解鎖";
  elements.goToRules.hidden = false;
  setStatus(
    elements.dataStatus,
    `已載入 ${validRecords.length} 筆有效資料，辨識到 ${stations.length} 個站點。`,
    "success",
  );
}

function renderStationChips(stations) {
  elements.stationChips.replaceChildren();
  if (!stations.length) {
    const empty = document.createElement("span");
    empty.className = "station-chip station-chip--empty";
    empty.textContent = "載入資料後顯示站點";
    elements.stationChips.append(empty);
    return;
  }

  stations.forEach((station, index) => {
    const chip = document.createElement("span");
    chip.className = "station-chip";
    const number = document.createElement("b");
    number.textContent = String(index + 1).padStart(2, "0");
    const label = document.createElement("span");
    label.textContent = station.name
      ? `${station.id} · ${station.name}`
      : station.id;
    chip.append(number, label);
    elements.stationChips.append(chip);
  });
}

function resetResults() {
  elements.participantMetric.textContent = "—";
  elements.completedMetric.textContent = "—";
  elements.stationMetric.textContent = "—";
  elements.scanMetric.textContent = "—";
  elements.resultBody.replaceChildren();
  elements.resultView.hidden = true;
  elements.emptyState.hidden = false;
  elements.exportButton.disabled = true;
  elements.resultStatus.textContent = "完成前兩個步驟後顯示成績。";
}

function invalidateResults() {
  if (!resultReady && !scoreResult) return;
  resultReady = false;
  scoreResult = null;
  resetResults();
  updateStepAccess();
  setStatus(elements.ruleStatus, "站點順序已變更，請重新計算成績。");
}

async function loadFiles(files) {
  const selected = Array.from(files);
  if (!selected.length) return;

  elements.fileInput.disabled = true;
  setStatus(elements.dataStatus, "正在讀取檔案…");
  try {
    const merged = [];
    for (const file of selected) {
      const text = await file.text();
      merged.push(...engine.parseDataText(text, file.name));
    }
    if (!merged.length) throw new Error("檔案中沒有可辨識的掃描紀錄");
    describeLoaded(
      merged,
      selected.length === 1 ? selected[0].name : `${selected.length} 個本機檔案`,
    );
  } catch (error) {
    setStatus(elements.dataStatus, `讀取失敗：${error.message}`, "error");
  } finally {
    elements.fileInput.disabled = false;
    elements.fileInput.value = "";
  }
}

async function importKeyBackup(file) {
  if (!file) return;
  try {
    const payload = JSON.parse(await file.text());
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      throw new Error("金鑰檔格式無效");
    }
    const uploadUrl =
      payload.UPLOAD_URL || payload.upload_url || payload.uploadUrl;
    const readKey = payload.READ_KEY || payload.read_key || payload.readKey;
    if (
      typeof uploadUrl !== "string" ||
      !appsScriptEndpointPattern.test(uploadUrl.trim())
    ) {
      throw new Error("UPLOAD_URL 必須是以 /exec 結尾的 Apps Script 正式網址");
    }
    if (typeof readKey !== "string" || !readKey.trim()) {
      throw new Error("檔案中找不到 READ_KEY");
    }
    elements.cloudUrl.value = uploadUrl.trim();
    elements.readKey.value = readKey.trim();
    elements.keyFileStatus.textContent =
      `已從 ${file.name} 帶入 Apps Script 網址與 READ_KEY`;
    elements.keyFileStatus.dataset.tone = "success";
  } catch (error) {
    elements.keyFileStatus.textContent = `金鑰檔讀取失敗：${error.message}`;
    elements.keyFileStatus.dataset.tone = "error";
  } finally {
    elements.keyFile.value = "";
  }
}

function loadCloudJsonp(endpoint) {
  return new Promise((resolve, reject) => {
    const bytes = new Uint8Array(8);
    crypto.getRandomValues(bytes);
    const suffix = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    const callbackName = "scanPointScore" + suffix;
    const script = document.createElement("script");
    const jsonpEndpoint = new URL(endpoint);
    jsonpEndpoint.searchParams.set("callback", callbackName);

    const cleanup = () => {
      window.clearTimeout(timeout);
      script.remove();
      delete window[callbackName];
    };
    const timeout = window.setTimeout(() => {
      cleanup();
      reject(new Error("Google 試算表讀取逾時"));
    }, 20000);

    window[callbackName] = (payload) => {
      cleanup();
      resolve(payload);
    };
    script.onerror = () => {
      cleanup();
      reject(new Error("瀏覽器無法載入 Apps Script 回應"));
    };
    script.src = jsonpEndpoint.toString();
    script.async = true;
    document.head.append(script);
  });
}

async function loadCloud() {
  const endpointText = elements.cloudUrl.value.trim();
  const readKey = elements.readKey.value.trim();

  if (!appsScriptEndpointPattern.test(endpointText)) {
    setStatus(elements.dataStatus, "請輸入以 /exec 結尾的 Apps Script 正式網址。", "error");
    elements.cloudUrl.focus();
    return;
  }
  if (!readKey) {
    setStatus(elements.dataStatus, "請輸入 READ_KEY。", "error");
    elements.readKey.focus();
    return;
  }

  const endpoint = new URL(endpointText);
  endpoint.searchParams.set("action", "scores");
  endpoint.searchParams.set("read_key", readKey);

  elements.loadCloud.disabled = true;
  setStatus(elements.dataStatus, "正在從 Google 試算表讀取…");
  try {
    let payload;
    try {
      const response = await fetch(endpoint, {
        cache: "no-store",
        redirect: "follow",
      });
      payload = await response.json();
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
    } catch (_) {
      payload = await loadCloudJsonp(endpoint);
    }
    if (!payload || payload.ok !== true) {
      throw new Error(payload?.error || "Google 試算表回應無效");
    }
    if (!Array.isArray(payload.scans)) {
      throw new Error("雲端回應缺少 scans 資料");
    }
    describeLoaded(payload.scans, "Google 試算表");
  } catch (error) {
    setStatus(
      elements.dataStatus,
      `雲端讀取失敗：${error.message}。也可以改用本機檔案。`,
      "error",
    );
  } finally {
    elements.loadCloud.disabled = false;
  }
}

function calculateScore() {
  if (!dataReady || !sourceRecords.length) {
    setStatus(elements.ruleStatus, "請先完成第一步並載入有效資料。", "error");
    return;
  }

  const stationOrder = engine.parseStationOrder(elements.stationOrder.value);
  if (!stationOrder.length) {
    setStatus(elements.ruleStatus, "請至少設定一個站點。", "error");
    elements.stationOrder.focus();
    return;
  }

  scoreResult = engine.scoreRecords(sourceRecords, stationOrder);
  elements.participantMetric.textContent = String(scoreResult.participantCount);
  elements.completedMetric.textContent = String(scoreResult.completedCount);
  elements.stationMetric.textContent = String(scoreResult.stationOrder.length);
  elements.scanMetric.textContent = String(scoreResult.validRecordCount);
  elements.exportButton.disabled = scoreResult.participants.length === 0;
  elements.emptyState.hidden = true;
  elements.resultView.hidden = false;
  resultReady = true;
  setStatus(
    elements.ruleStatus,
    `已依序使用 ${scoreResult.stationOrder.join(" → ")} 計分。`,
    "success",
  );
  renderResults();
  updateStepAccess();
  goToStep(3);
}

function formatTime(timestamp) {
  if (!Number.isFinite(timestamp)) return "—";
  return new Intl.DateTimeFormat("zh-TW", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date(timestamp));
}

function renderResults() {
  if (!scoreResult) return;
  const query = elements.search.value.trim().toLocaleLowerCase("zh-Hant");
  const participants = scoreResult.participants.filter((participant) =>
    participant.cardId.toLocaleLowerCase("zh-Hant").includes(query),
  );

  elements.resultBody.replaceChildren();
  participants.forEach((participant) => {
    const row = document.createElement("tr");
    if (!participant.complete) row.classList.add("is-incomplete");

    const rankCell = document.createElement("td");
    rankCell.dataset.label = "名次";
    const rank = document.createElement("span");
    rank.className = participant.rank
      ? "rank-badge"
      : "rank-badge rank-badge--empty";
    rank.textContent = participant.rank ? String(participant.rank) : "—";
    rankCell.append(rank);

    const cardCell = document.createElement("td");
    cardCell.dataset.label = "卡號";
    const card = document.createElement("strong");
    card.className = "card-id";
    card.textContent = participant.cardId;
    cardCell.append(card);

    const statusCell = document.createElement("td");
    statusCell.dataset.label = "狀態";
    const status = document.createElement("span");
    status.className = participant.complete
      ? "result-state result-state--complete"
      : "result-state result-state--progress";
    status.textContent = participant.complete
      ? "完賽"
      : `${participant.progress} / ${participant.totalStations}`;
    statusCell.append(status);

    const durationCell = document.createElement("td");
    durationCell.dataset.label = "成績";
    durationCell.className = "duration-cell";
    durationCell.textContent = engine.formatDuration(participant.elapsedMs);

    const startCell = document.createElement("td");
    startCell.dataset.label = "起點時間";
    startCell.textContent = formatTime(participant.startTime);

    const finishCell = document.createElement("td");
    finishCell.dataset.label = "終點時間";
    finishCell.textContent = formatTime(participant.finishTime);

    const routeCell = document.createElement("td");
    routeCell.dataset.label = "通過站點";
    routeCell.className = "route-cell";
    routeCell.textContent =
      participant.matched.map((record) => record.stationId).join(" → ") ||
      "尚未通過首站";

    row.append(
      rankCell,
      cardCell,
      statusCell,
      durationCell,
      startCell,
      finishCell,
      routeCell,
    );
    elements.resultBody.append(row);
  });

  elements.resultStatus.textContent = query
    ? `顯示 ${participants.length} / ${scoreResult.participants.length} 位參賽者`
    : `${sourceDescription} · 共 ${scoreResult.participants.length} 位參賽者`;
}

function csvCell(value) {
  return `"${String(value ?? "").replaceAll('"', '""')}"`;
}

function exportResults() {
  if (!scoreResult) return;
  const rows = [
    [
      "rank",
      "card_id",
      "status",
      "progress",
      "elapsed",
      "start_time",
      "finish_time",
      "stations",
    ],
    ...scoreResult.participants.map((participant) => [
      participant.rank ?? "",
      participant.cardId,
      participant.complete ? "complete" : "incomplete",
      `${participant.progress}/${participant.totalStations}`,
      engine.formatDuration(participant.elapsedMs),
      Number.isFinite(participant.startTime)
        ? new Date(participant.startTime).toISOString()
        : "",
      Number.isFinite(participant.finishTime)
        ? new Date(participant.finishTime).toISOString()
        : "",
      participant.matched.map((record) => record.stationId).join(" > "),
    ]),
  ];
  const csv =
    "\uFEFF" + rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
  const blob = new Blob([csv], {type: "text/csv;charset=utf-8"});
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `scanpoint-results-${new Date().toISOString().slice(0, 10)}.csv`;
  document.body.append(link);
  link.click();
  URL.revokeObjectURL(link.href);
  link.remove();
}

elements.stepButtons.forEach((button) => {
  button.addEventListener("click", () => {
    goToStep(Number(button.dataset.goStep));
  });
});
elements.goToRules.addEventListener("click", () => goToStep(2));
elements.loadCloud.addEventListener("click", loadCloud);
elements.keyFile.addEventListener("change", () =>
  importKeyBackup(elements.keyFile.files[0]),
);
elements.fileInput.addEventListener("change", () =>
  loadFiles(elements.fileInput.files),
);
elements.calculate.addEventListener("click", calculateScore);
elements.stationOrder.addEventListener("input", invalidateResults);
elements.search.addEventListener("input", renderResults);
elements.exportButton.addEventListener("click", exportResults);
elements.backToRules.addEventListener("click", () => goToStep(2));
elements.dropzone.addEventListener("dragover", (event) => {
  event.preventDefault();
  elements.dropzone.classList.add("is-dragging");
});
elements.dropzone.addEventListener("dragleave", () => {
  elements.dropzone.classList.remove("is-dragging");
});
elements.dropzone.addEventListener("drop", (event) => {
  event.preventDefault();
  elements.dropzone.classList.remove("is-dragging");
  loadFiles(event.dataTransfer.files);
});

renderStationChips([]);
resetResults();
goToStep(1);