"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const engine = require("../score-engine.js");

test("parseDataText accepts JSON arrays, wrapped JSON, and JSONL", () => {
  const record = scan("A", "CP1", "2026-08-10T01:00:00Z");
  assert.deepEqual(engine.parseDataText(JSON.stringify([record]), "scans.json"), [record]);
  assert.deepEqual(
    engine.parseDataText(JSON.stringify({scans: [record]}), "scans.json"),
    [record],
  );
  assert.deepEqual(
    engine.parseDataText(`${JSON.stringify(record)}\n`, "scans.jsonl"),
    [record],
  );
});

test("parseStationOrder accepts common separators and removes duplicates", () => {
  assert.deepEqual(
    engine.parseStationOrder("CP1, CP2 → CP3；CP2\nCP4"),
    ["CP1", "CP2", "CP3", "CP4"],
  );
});

test("scoreRecords deduplicates the same stable record id", () => {
  const first = scan("A", "CP1", "2026-08-10T01:00:00Z", "stable-1");
  const result = engine.scoreRecords(
    [first, {...first}, scan("A", "CP2", "2026-08-10T01:00:10Z", "stable-2")],
    ["CP1", "CP2"],
  );
  assert.equal(result.validRecordCount, 2);
  assert.equal(result.participants[0].scanCount, 2);
  assert.equal(result.participants[0].complete, true);
});

test("equal elapsed times share the same rank", () => {
  const result = engine.scoreRecords(
    [
      scan("A", "CP1", "2026-08-10T01:00:00Z"),
      scan("A", "CP2", "2026-08-10T01:00:10Z"),
      scan("B", "CP1", "2026-08-10T01:01:00Z"),
      scan("B", "CP2", "2026-08-10T01:01:10Z"),
    ],
    ["CP1", "CP2"],
  );
  assert.deepEqual(result.participants.map((participant) => participant.rank), [1, 1]);
});

test("formatDuration keeps centiseconds and supports hours", () => {
  assert.equal(engine.formatDuration(39050), "00:39.05");
  assert.equal(engine.formatDuration(3_661_230), "1:01:01.23");
  assert.equal(engine.formatDuration(null), "—");
});

function scan(card, station, at, recordId = "") {
  return {
    record_id: recordId || `${card}-${station}-${at}`,
    card_id: card,
    station_id: station,
    station_name: station,
    at_utc: at,
    duplicate_of: "",
  };
}
