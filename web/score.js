"use strict";

const engine = window.ScanPointScoreEngine;

const elements = {
  cloudUrl: document.querySelector("#score-cloud-url"),
  readKey: document.querySelector("#score-read-key"),
  loadCloud: document.querySelector("#load-cloud"),
  fileInput: document.querySelector("#score-files"),
  dropzone: document.querySelector("#score-dropzone"),
  dataStatus: document.querySelector("#score-data-status"),
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
  resultTable: document.querySelector("#score-result-table"),
  resultStatus: document.querySelector("#score-result-status"),
  search: document.querySelector("#score-search"),
  exportButton: document.querySelector("#export-score"),
  progressLinks: document.querySelectorAll("[data-score-section]"),
  progressBar: document.querySelector("#score-progress-bar"),
  progressLabel: document.querySelector("#score-progress-label"),
};

let sourceRecords = [];
let scoreResult = null;
let sourceDescription = "尚未載入";
let progressFrame = 0;

function setStatus(element, message, tone = "") {
  element.textContent = message;
  if (tone) element.dataset.tone = tone;
  else delete element.dataset.tone;
}

function describeLoaded(records, source) {
  const stations = engine.inferStations(records);
  sourceRecords = records;
  sourceDescription = source;
  elements.recordCount.textContent = String(records.length);
  elements.stationCount.textContent = String(stations.length);
  elements.sourceLabel.textContent = source;
  elements.stationOrder.value = stations.map((station) => station.id).join(", ");
  renderStationChips(stations);
  scoreResult = null;
  resetResults();
  setStatus(
    elements.dataStatus,
    `已載入 ${records.length} 筆資料，辨識到 ${stations.length} 個站點。`,
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
  elements.resultTable.hidden = true;
  elements.emptyState.hidden = false;
  elements.exportButton.disabled = true;
  elements.resultStatus.textContent = "載入資料並設定站點順序後即可計分。";
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

  if (!/^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec$/.test(endpointText)) {
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
      `雲端讀取失敗：${error.message}。也可以改用下方檔案匯入。`,
      "error",
    );
  } finally {
    elements.loadCloud.disabled = false;
  }
}

function calculateScore() {
  if (!sourceRecords.length) {
    setStatus(elements.ruleStatus, "請先載入雲端資料或本機檔案。", "error");
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
  elements.resultTable.hidden = false;
  setStatus(
    elements.ruleStatus,
    `已依序使用 ${scoreResult.stationOrder.join(" → ")} 計分。`,
    "success",
  );
  renderResults();
  document.querySelector("#score-results").scrollIntoView({
    behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
      ? "auto"
      : "smooth",
    block: "start",
  });
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
    rank.className = participant.rank ? "rank-badge" : "rank-badge rank-badge--empty";
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
      participant.matched.map((record) => record.stationId).join(" → ") || "尚未通過首站";

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
    ["rank", "card_id", "status", "progress", "elapsed", "start_time", "finish_time", "stations"],
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
  const csv = "\uFEFF" + rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
  const blob = new Blob([csv], {type: "text/csv;charset=utf-8"});
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `scanpoint-results-${new Date().toISOString().slice(0, 10)}.csv`;
  document.body.append(link);
  link.click();
  URL.revokeObjectURL(link.href);
  link.remove();
}

function updateProgress() {
  const marker = window.scrollY + window.innerHeight * 0.4;
  const sections = Array.from(elements.progressLinks, (link) =>
    document.querySelector("#" + link.dataset.scoreSection),
  );
  let active = 0;
  sections.forEach((section, index) => {
    if (section.offsetTop <= marker) active = index;
  });
  if (
    window.scrollY + window.innerHeight >=
    document.documentElement.scrollHeight - 4
  ) {
    active = sections.length - 1;
  }
  elements.progressLinks.forEach((link, index) => {
    if (index === active) link.setAttribute("aria-current", "step");
    else link.removeAttribute("aria-current");
  });
  elements.progressBar.style.width = `${((active + 1) / sections.length) * 100}%`;
  elements.progressLabel.value = `步驟 ${active + 1} / ${sections.length}`;
}

function scheduleProgress() {
  if (progressFrame) return;
  progressFrame = requestAnimationFrame(() => {
    progressFrame = 0;
    updateProgress();
  });
}

elements.loadCloud.addEventListener("click", loadCloud);
elements.fileInput.addEventListener("change", () => loadFiles(elements.fileInput.files));
elements.calculate.addEventListener("click", calculateScore);
elements.search.addEventListener("input", renderResults);
elements.exportButton.addEventListener("click", exportResults);
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
window.addEventListener("scroll", scheduleProgress, {passive: true});
window.addEventListener("resize", scheduleProgress);

renderStationChips([]);
resetResults();
updateProgress();