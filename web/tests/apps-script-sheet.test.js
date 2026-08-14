"use strict";

// Code.gs only ever runs inside Apps Script, so it is loaded into a VM context
// with the four Google globals it touches stubbed out. The stub sheet records
// the order of setNumberFormat / setValues calls, which is the whole question
// for text-format handling: formatting after the write is too late.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const SPREADSHEET_ID = "sheet-id-for-tests";
const UPLOAD_KEY = "upload-key-for-tests";

function createSheet(name, {maxRows = 1000} = {}) {
  const cells = [];
  const calls = [];
  const rangeFor = (row, column, rowCount, columnCount) => ({
    setNumberFormat(format) {
      calls.push({op: "setNumberFormat", row, rowCount, format});
      return this;
    },
    setValues(values) {
      calls.push({op: "setValues", row, rowCount});
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
    setFontWeight: () => rangeFor(row, column, rowCount, columnCount),
    setBackground: () => rangeFor(row, column, rowCount, columnCount),
  });

  return {
    name,
    calls,
    cells,
    getRange: rangeFor,
    getMaxRows: () => maxRows,
    getLastRow: () => cells.length,
    setFrozenRows: () => undefined,
    autoResizeColumns: () => undefined,
  };
}

function loadCodeGs(sheets) {
  const source = fs.readFileSync(
    path.resolve(__dirname, "..", "google_apps_script", "Code.gs"),
    "utf8",
  );
  const context = {
    SpreadsheetApp: {
      openById: () => ({
        getSheetByName: (name) => sheets[name] || null,
        insertSheet: (name) => {
          sheets[name] = createSheet(name);
          return sheets[name];
        },
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
          ({SPREADSHEET_ID, UPLOAD_KEY, READ_KEY: "read-key-for-tests"})[key] || "",
      }),
    },
    Utilities: {
      DigestAlgorithm: {SHA_256: "sha256"},
      computeDigest: (_algorithm, value) =>
        Array.from(require("node:crypto").createHash("sha256").update(value).digest()),
    },
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return context;
}

function post(code, scans) {
  const response = code.doPost({
    postData: {
      contents: JSON.stringify({
        schema_version: 1,
        api_key: UPLOAD_KEY,
        spreadsheet_id: SPREADSHEET_ID,
        batch_id: "CP1-1",
        station_id: "CP1",
        station_name: "起點",
        uploaded_at: "2026-08-10T01:00:00.000Z",
        scans,
        operations: [],
      }),
    },
  });
  return JSON.parse(response.text);
}

function scan(recordId, card) {
  return {
    record_id: recordId,
    seq: 1,
    card,
    station_id: "CP1",
    station_name: "起點",
    at_local: "2026-08-10T09:00:00.000",
    at_utc: "2026-08-10T01:00:00.000Z",
    term: "questionMark",
  };
}

test("every appended block of scans is formatted as text before it is written", () => {
  const sheets = {};
  const code = loadCodeGs(sheets);

  assert.equal(post(code, [scan("scan-1", "0012345678")]).ok, true);
  // A second upload appends into rows the sheet was not created with. This is
  // the case that used to arrive unformatted once a sheet outgrew its rows.
  assert.equal(post(code, [scan("scan-2", "0087654321")]).ok, true);

  // Row 1 is the header, written once when the sheet is created.
  const appends = sheets.scans.calls.filter((call) => call.row > 1);
  const writes = appends.filter((call) => call.op === "setValues");
  assert.equal(writes.length, 2, "expected one append per upload");

  for (const write of writes) {
    const index = appends.indexOf(write);
    assert.deepEqual(
      appends[index - 1],
      {op: "setNumberFormat", row: write.row, rowCount: write.rowCount, format: "@"},
      `row ${write.row} was written without being formatted as text first`,
    );
  }
});

test("card ids with leading zeros survive a read-back", () => {
  const sheets = {};
  const code = loadCodeGs(sheets);
  post(code, [scan("scan-1", "0012345678")]);

  const payload = JSON.parse(
    code.doGet({
      parameter: {action: "scores", read_key: "read-key-for-tests"},
    }).text,
  );
  assert.equal(payload.ok, true);
  assert.equal(payload.scans.length, 1);
  assert.equal(payload.scans[0].card_id, "0012345678");
});

test("a record id already in the sheet is counted as a duplicate, not appended twice", () => {
  const sheets = {};
  const code = loadCodeGs(sheets);
  post(code, [scan("scan-1", "A1")]);
  const second = post(code, [scan("scan-1", "A1"), scan("scan-2", "A2")]);

  assert.equal(second.scans.accepted, 1);
  assert.equal(second.scans.duplicates, 1);
  assert.equal(sheets.scans.getLastRow(), 3, "header plus two distinct records");
});
