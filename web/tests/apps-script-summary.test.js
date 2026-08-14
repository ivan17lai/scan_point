"use strict";

// The summary sheet is the one place a station's totals are read back by a
// human, and it is now fed by uploads that carry a slice of the log rather
// than all of it. Code.gs only runs inside Apps Script, so it is loaded into a
// VM context with the Google globals it touches stubbed out.

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const SPREADSHEET_ID = "sheet-id-for-tests";
const UPLOAD_KEY = "upload-key-for-tests";
const SUMMARY_COLUMNS = [
  "station_id",
  "station_name",
  "valid_scans",
  "duplicate_scans",
  "total_scans",
  "operations",
  "last_uploaded_at",
];

function createSheet() {
  const cells = [];
  const noop = () => range(1, 1, 1, 1);
  const range = (row, column, rowCount, columnCount) => ({
    setNumberFormat: noop,
    setFontWeight: noop,
    setBackground: noop,
    setValues(values) {
      values.forEach((line, offset) => {
        cells[row + offset - 1] = line.slice();
      });
      return this;
    },
    getValues: () =>
      Array.from({length: rowCount}, (_, offset) =>
        Array.from(
          {length: columnCount},
          (_, index) => (cells[row + offset - 1] || [])[column + index - 1] ?? "",
        ),
      ),
    getDisplayValues() {
      return this.getValues().map((line) => line.map((value) => String(value ?? "")));
    },
  });

  return {
    cells,
    getRange: range,
    getMaxRows: () => 1000,
    getLastRow: () => cells.length,
    setFrozenRows: () => undefined,
    autoResizeColumns: () => undefined,
  };
}

function loadCodeGs() {
  const sheets = {};
  const source = fs.readFileSync(
    path.resolve(__dirname, "..", "google_apps_script", "Code.gs"),
    "utf8",
  );
  const context = {
    SpreadsheetApp: {
      openById: () => ({
        getSheetByName: (name) => sheets[name] || null,
        insertSheet: (name) => (sheets[name] = createSheet()),
      }),
      flush: () => undefined,
    },
    ContentService: {
      MimeType: {JSON: "json", JAVASCRIPT: "javascript"},
      createTextOutput: (text) => ({setMimeType: () => ({text})}),
    },
    LockService: {
      getScriptLock: () => ({waitLock: () => undefined, releaseLock: () => undefined}),
    },
    PropertiesService: {
      getScriptProperties: () => ({
        getProperty: (key) =>
          ({SPREADSHEET_ID, UPLOAD_KEY, READ_KEY: "read-key"})[key] || "",
      }),
    },
    Utilities: {
      DigestAlgorithm: {SHA_256: "sha256"},
      computeDigest: (_algorithm, value) =>
        Array.from(crypto.createHash("sha256").update(value).digest()),
    },
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return {code: context, sheets};
}

function post(code, {scans = [], operations = [], stationTotals}) {
  const body = {
    schema_version: 1,
    api_key: UPLOAD_KEY,
    spreadsheet_id: SPREADSHEET_ID,
    batch_id: "CP1-1",
    station_id: "CP1",
    station_name: "起點",
    uploaded_at: "2026-08-10T01:00:00.000Z",
    scans,
    operations,
  };
  if (stationTotals) body.station_totals = stationTotals;
  const response = code.doPost({postData: {contents: JSON.stringify(body)}});
  return JSON.parse(response.text);
}

function scan(index, extra = {}) {
  return {
    record_id: `scan-${index}`,
    seq: index,
    card: `CARD${index}`,
    station_id: "CP1",
    station_name: "起點",
    at_utc: "2026-08-10T01:00:00.000Z",
    ...extra,
  };
}

function summaryRow(sheets) {
  const row = sheets.summary.cells[1];
  return Object.fromEntries(SUMMARY_COLUMNS.map((name, index) => [name, row[index]]));
}

test("the summary reports the station's totals, not the batch that arrived", () => {
  const {code, sheets} = loadCodeGs();

  // An incremental uploader sends a slice and states what the station holds.
  post(code, {
    scans: [scan(9), scan(10)],
    stationTotals: {scans: 10, duplicate_scans: 3, operations: 42},
  });

  assert.deepEqual(summaryRow(sheets), {
    station_id: "CP1",
    station_name: "起點",
    valid_scans: 7,
    duplicate_scans: 3,
    total_scans: 10,
    operations: 42,
    last_uploaded_at: summaryRow(sheets).last_uploaded_at,
  });
});

test("successive slices do not shrink the summary to the last one", () => {
  const {code, sheets} = loadCodeGs();

  post(code, {
    scans: [scan(1), scan(2), scan(3)],
    stationTotals: {scans: 3, duplicate_scans: 0, operations: 3},
  });
  assert.equal(summaryRow(sheets).total_scans, 3);

  post(code, {
    scans: [scan(4)],
    stationTotals: {scans: 4, duplicate_scans: 1, operations: 5},
  });
  const row = summaryRow(sheets);
  assert.equal(row.total_scans, 4);
  assert.equal(row.valid_scans, 3);
  assert.equal(row.duplicate_scans, 1);
  assert.equal(sheets.summary.getLastRow(), 2, "one row per station, updated in place");
});

test("a station still sending its whole log is counted as before", () => {
  const {code, sheets} = loadCodeGs();

  post(code, {
    scans: [scan(1), scan(2), scan(3, {duplicate_of: "2026-08-10T01:00:00.000"})],
    operations: [{event_id: "event-1", type: "scan_ok"}],
  });

  const row = summaryRow(sheets);
  assert.equal(row.total_scans, 3);
  assert.equal(row.duplicate_scans, 1);
  assert.equal(row.valid_scans, 2);
  assert.equal(row.operations, 1);
});

test("unusable totals fall back to the batch rather than writing nonsense", () => {
  const {code, sheets} = loadCodeGs();

  post(code, {
    scans: [scan(1), scan(2)],
    stationTotals: {scans: "not a number", duplicate_scans: -4, operations: null},
  });

  const row = summaryRow(sheets);
  assert.equal(row.total_scans, 2);
  assert.equal(row.duplicate_scans, 0);
  assert.equal(row.valid_scans, 2);
  assert.equal(row.operations, 0);
});
