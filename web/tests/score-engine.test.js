"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const engine = require("../score-engine.js");

test("parseCsv supports quoted values and UTF-8 headers", () => {
  const rows = engine.parseCsv(
    "\uFEFFcard_id,station_id,station_name,at_utc\n" +
      '"A,01",CP1,"起點, 北側",2026-08-10T01:00:00Z\n',
  );

  assert.equal(rows.length, 1);
  assert.equal(rows[0].card_id, "A,01");
  assert.equal(rows[0].station_name, "起點, 北側");
});

test("scoreRecords ranks completed cards by elapsed time", () => {
  const records = [
    scan("A", "CP1", "2026-08-10T01:00:00Z"),
    scan("A", "CP2", "2026-08-10T01:00:10Z"),
    scan("A", "CP3", "2026-08-10T01:00:30Z"),
    scan("B", "CP1", "2026-08-10T01:01:00Z"),
    scan("B", "CP2", "2026-08-10T01:01:05Z"),
    scan("B", "CP3", "2026-08-10T01:01:20Z"),
    scan("C", "CP1", "2026-08-10T01:02:00Z"),
    scan("C", "CP2", "2026-08-10T01:02:05Z"),
  ];

  const result = engine.scoreRecords(records, ["CP1", "CP2", "CP3"]);

  assert.deepEqual(
    result.participants.map((participant) => participant.cardId),
    ["B", "A", "C"],
  );
  assert.equal(result.participants[0].rank, 1);
  assert.equal(result.participants[0].elapsedMs, 20000);
  assert.equal(result.participants[2].complete, false);
  assert.equal(result.participants[2].progress, 2);
});

test("duplicate markers and out-of-order scans do not advance the route", () => {
  const records = [
    scan("A", "CP2", "2026-08-10T01:00:00Z"),
    scan("A", "CP1", "2026-08-10T01:00:05Z"),
    {...scan("A", "CP2", "2026-08-10T01:00:08Z"), duplicate_of: "x"},
    scan("A", "CP3", "2026-08-10T01:00:12Z"),
  ];

  const result = engine.scoreRecords(records, ["CP1", "CP2", "CP3"]);
  assert.equal(result.participants[0].progress, 1);
  assert.equal(result.participants[0].complete, false);
});

test("inferStations uses natural station id ordering", () => {
  const stations = engine.inferStations([
    scan("A", "CP10", "2026-08-10T01:00:00Z"),
    scan("A", "CP2", "2026-08-10T01:01:00Z"),
    scan("A", "CP1", "2026-08-10T01:02:00Z"),
  ]);

  assert.deepEqual(
    stations.map((station) => station.id),
    ["CP1", "CP2", "CP10"],
  );
});

test("a torn final line keeps the records written before it", () => {
  const intact = JSON.stringify(scan("A", "CP1", "2026-08-10T01:00:00Z"));
  const issues = [];
  // What a station leaves behind when the power is cut mid-write.
  const records = engine.parseDataText(
    `${intact}\n{"record_id":"scan-2","card_id":"B","stat`,
    "scans.jsonl",
    issues,
  );

  assert.equal(records.length, 1);
  assert.equal(records[0].card_id, "A");
  assert.deepEqual(issues, [{type: "unreadableLines", count: 1}]);
});

function scan(card, station, at) {
  return {
    record_id: `${card}-${station}-${at}`,
    card_id: card,
    station_id: station,
    station_name: station,
    at_utc: at,
    duplicate_of: "",
  };
}