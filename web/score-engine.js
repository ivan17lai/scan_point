"use strict";

(function attachScoreEngine(root, factory) {
  const engine = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = engine;
  }
  root.ScanPointScoreEngine = engine;
})(typeof globalThis !== "undefined" ? globalThis : this, () => {
  function parseCsv(text) {
    const rows = [];
    let row = [];
    let field = "";
    let quoted = false;

    for (let index = 0; index < text.length; index += 1) {
      const char = text[index];
      const next = text[index + 1];

      if (quoted) {
        if (char === '"' && next === '"') {
          field += '"';
          index += 1;
        } else if (char === '"') {
          quoted = false;
        } else {
          field += char;
        }
      } else if (char === '"') {
        quoted = true;
      } else if (char === ",") {
        row.push(field);
        field = "";
      } else if (char === "\n") {
        row.push(field.replace(/\r$/, ""));
        rows.push(row);
        row = [];
        field = "";
      } else {
        field += char;
      }
    }

    if (field || row.length) {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
    }

    const nonEmptyRows = rows.filter((values) =>
      values.some((value) => value.trim() !== ""),
    );
    if (nonEmptyRows.length < 2) return [];

    const headers = nonEmptyRows[0].map((header) =>
      header.replace(/^\uFEFF/, "").trim(),
    );
    return nonEmptyRows.slice(1).map((values) =>
      Object.fromEntries(headers.map((header, index) => [header, values[index] || ""])),
    );
  }

  // Records the parts of a file we could not use, so the caller can say so
  // instead of quietly handing back fewer records than the operator supplied.
  function noteIssue(issues, type, count) {
    if (!count || !Array.isArray(issues)) return;
    issues.push({type, count});
  }

  function parseJsonText(text, issues = null) {
    const trimmed = text.replace(/^\uFEFF/, "").trim();
    if (!trimmed) return [];

    try {
      const value = JSON.parse(trimmed);
      if (Array.isArray(value)) return value;
      if (Array.isArray(value.scans)) return value.scans;
      if (Array.isArray(value.records)) return value.records;
      if (
        value &&
        typeof value === "object" &&
        (value.card_id || value.cardId || value.card) &&
        (value.station_id || value.stationId)
      ) {
        return [value];
      }
      return [];
    } catch (_) {
      // JSONL, one record per line. A station that loses power mid-write leaves
      // a torn last line, and the station's own reader keeps everything before
      // it — so the whole file must not be thrown away here over that one line.
      const records = [];
      let unreadable = 0;
      for (const line of trimmed.split(/\r?\n/)) {
        if (!line.trim()) continue;
        try {
          records.push(JSON.parse(line));
        } catch (_) {
          unreadable += 1;
        }
      }
      noteIssue(issues, "unreadableLines", unreadable);
      return records;
    }
  }

  function parseDataText(text, filename = "", issues = null) {
    const extension = filename.toLowerCase().split(".").pop();
    return extension === "csv" ? parseCsv(text) : parseJsonText(text, issues);
  }

  function clean(value) {
    return value === null || value === undefined ? "" : String(value).trim();
  }

  function normalizeRecord(source) {
    const atText = clean(
      source.at_utc || source.atUtc || source.at_local || source.atLocal || source.at,
    );
    const timestamp = Date.parse(atText);
    const record = {
      recordId: clean(source.record_id || source.recordId),
      cardId: clean(source.card_id || source.cardId || source.card),
      stationId: clean(source.station_id || source.stationId),
      stationName: clean(source.station_name || source.stationName),
      atText,
      timestamp,
      duplicateOf: clean(source.duplicate_of || source.duplicateOf),
    };
    record.valid =
      Boolean(record.cardId && record.stationId && atText) &&
      Number.isFinite(record.timestamp);
    return record;
  }

  function normalizeRecords(records) {
    return records.map(normalizeRecord).filter((record) => record.valid);
  }

  function parseStationOrder(value) {
    const seen = new Set();
    return String(value || "")
      .split(/[\n,，;；>→]+/)
      .map((part) => part.trim())
      .filter((part) => part && !seen.has(part) && seen.add(part));
  }

  function inferStations(records) {
    const names = new Map();
    for (const record of normalizeRecords(records)) {
      if (!names.has(record.stationId) || !names.get(record.stationId)) {
        names.set(record.stationId, record.stationName);
      }
    }
    return Array.from(names, ([id, name]) => ({id, name}))
      .sort((left, right) =>
        left.id.localeCompare(right.id, "zh-Hant", {
          numeric: true,
          sensitivity: "base",
        }),
      );
  }

  function recordIdentity(record) {
    return (
      record.recordId ||
      [record.cardId, record.stationId, record.timestamp].join("\u001f")
    );
  }

  function scoreRecords(sourceRecords, requestedStationOrder) {
    const stationOrder = Array.isArray(requestedStationOrder)
      ? requestedStationOrder.filter(Boolean)
      : parseStationOrder(requestedStationOrder);
    const unique = new Map();

    for (const record of normalizeRecords(sourceRecords)) {
      if (record.duplicateOf) continue;
      unique.set(recordIdentity(record), record);
    }

    const records = Array.from(unique.values());
    const groups = new Map();
    for (const record of records) {
      if (!groups.has(record.cardId)) groups.set(record.cardId, []);
      groups.get(record.cardId).push(record);
    }

    const participants = [];
    for (const [cardId, cardRecords] of groups) {
      cardRecords.sort((left, right) => left.timestamp - right.timestamp);
      const matched = [];
      let cursor = 0;

      for (const stationId of stationOrder) {
        let foundAt = -1;
        for (let index = cursor; index < cardRecords.length; index += 1) {
          if (cardRecords[index].stationId === stationId) {
            foundAt = index;
            break;
          }
        }
        if (foundAt < 0) break;
        matched.push(cardRecords[foundAt]);
        cursor = foundAt + 1;
      }

      const complete =
        stationOrder.length > 0 && matched.length === stationOrder.length;
      const startTime = matched[0]?.timestamp ?? null;
      const finishTime = complete ? matched[matched.length - 1].timestamp : null;
      const elapsedMs =
        complete && startTime !== null && finishTime !== null
          ? Math.max(0, finishTime - startTime)
          : null;

      participants.push({
        cardId,
        complete,
        progress: matched.length,
        totalStations: stationOrder.length,
        startTime,
        finishTime,
        elapsedMs,
        matched,
        scanCount: cardRecords.length,
      });
    }

    participants.sort((left, right) => {
      if (left.complete !== right.complete) return left.complete ? -1 : 1;
      if (left.complete) {
        return (
          left.elapsedMs - right.elapsedMs ||
          left.finishTime - right.finishTime ||
          left.cardId.localeCompare(right.cardId)
        );
      }
      return (
        right.progress - left.progress ||
        (left.startTime ?? Number.MAX_SAFE_INTEGER) -
          (right.startTime ?? Number.MAX_SAFE_INTEGER) ||
        left.cardId.localeCompare(right.cardId)
      );
    });

    let rank = 0;
    let previousElapsed = null;
    participants.forEach((participant, index) => {
      if (!participant.complete) {
        participant.rank = null;
        return;
      }
      if (participant.elapsedMs !== previousElapsed) rank = index + 1;
      participant.rank = rank;
      previousElapsed = participant.elapsedMs;
    });

    return {
      stationOrder,
      participants,
      validRecordCount: records.length,
      participantCount: participants.length,
      completedCount: participants.filter((participant) => participant.complete).length,
    };
  }

  function formatDuration(milliseconds) {
    if (!Number.isFinite(milliseconds)) return "—";
    const totalSeconds = Math.floor(milliseconds / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    const centiseconds = Math.floor((milliseconds % 1000) / 10);
    const base = [minutes, seconds]
      .map((value) => String(value).padStart(2, "0"))
      .join(":");
    return hours > 0
      ? `${hours}:${base}.${String(centiseconds).padStart(2, "0")}`
      : `${base}.${String(centiseconds).padStart(2, "0")}`;
  }

  return {
    formatDuration,
    inferStations,
    normalizeRecord,
    normalizeRecords,
    parseCsv,
    parseDataText,
    parseJsonText,
    parseStationOrder,
    scoreRecords,
  };
});