const SCANPOINT_CONFIG = Object.freeze({
  spreadsheetId: '__SCANPOINT_SPREADSHEET_ID__',
  uploadKey: '__SCANPOINT_UPLOAD_KEY__',
  readKey: '__SCANPOINT_READ_KEY__',
});

const SCAN_HEADERS = [
  'record_id', 'station_id', 'station_name', 'sequence', 'card_id',
  'at_local', 'at_utc', 'duplicate_of', 'terminator', 'received_at',
];

const OPERATION_HEADERS = [
  'event_id', 'station_id', 'event_type', 'at_local', 'at_utc',
  'detail_json', 'received_at',
];

const UPLOAD_HEADERS = [
  'batch_id', 'station_id', 'station_name', 'uploaded_at_client',
  'received_at_server', 'scans_sent', 'operations_sent', 'accepted',
  'duplicates',
];

const SUMMARY_HEADERS = [
  'station_id', 'station_name', 'valid_scans', 'duplicate_scans',
  'total_scans', 'operations', 'last_uploaded_at',
];

function doGet(e) {
  const action = cleanText(e && e.parameter && e.parameter.action);
  try {
    if (action === 'scores') return readScores(e);
    return jsonResponse({
      ok: true,
      service: 'scan_point Google Sheets uploader',
      schema_version: 1,
    });
  } catch (error) {
    const value = {
      ok: false,
      error: String(error && error.message ? error.message : error),
    };
    return action === 'scores'
      ? scoreResponse(e, value)
      : jsonResponse(value);
  }
}

function readScores(e) {
  const spreadsheetId = configValue('spreadsheetId');
  const expectedReadKey = configValue('readKey');
  const actualReadKey = e && e.parameter && e.parameter.read_key;

  if (!spreadsheetId || !expectedReadKey) {
    return scoreResponse(e, {
      ok: false,
      error: 'Code.gs or Script Properties score configuration is incomplete',
    });
  }
  if (!safeEqual(actualReadKey, expectedReadKey)) {
    return scoreResponse(e, {ok: false, error: 'Unauthorized'});
  }

  const spreadsheet = SpreadsheetApp.openById(spreadsheetId);
  const sheet = spreadsheet.getSheetByName('scans');
  if (!sheet || sheet.getLastRow() < 2) {
    return scoreResponse(e, {
      ok: true,
      schema_version: 1,
      generated_at: new Date().toISOString(),
      scans: [],
    });
  }

  const rowCount = sheet.getLastRow() - 1;
  if (rowCount > 50000) {
    return scoreResponse(e, {
      ok: false,
      error: 'Score data exceeds the 50000 row limit',
    });
  }

  const values = sheet
    .getRange(2, 1, rowCount, SCAN_HEADERS.length)
    .getValues();
  const scans = values.map((row) => {
    const record = {};
    SCAN_HEADERS.forEach((header, index) => {
      record[header] = normalizeCell(row[index]);
    });
    return record;
  });

  return scoreResponse(e, {
    ok: true,
    schema_version: 1,
    generated_at: new Date().toISOString(),
    scans,
  });
}

// Sheets may store a timestamp written as text as a real date value. Reading
// the display string would then hand the scoring page a localised date it
// cannot parse, and the row would be dropped without a word — so the
// underlying value is read and dates are re-encoded as ISO 8601.
function normalizeCell(value) {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function scoreResponse(e, value) {
  const callback = cleanText(e && e.parameter && e.parameter.callback);
  if (!callback) return jsonResponse(value);
  if (!/^[a-zA-Z_$][0-9a-zA-Z_$]{0,80}$/.test(callback)) {
    return jsonResponse({ok: false, error: 'Invalid callback'});
  }
  return ContentService
    .createTextOutput(callback + '(' + JSON.stringify(value) + ');')
    .setMimeType(ContentService.MimeType.JAVASCRIPT);
}

function doPost(e) {
  try {
    const spreadsheetId = configValue('spreadsheetId');
    const expectedKey = configValue('uploadKey');

    if (!spreadsheetId || !expectedKey) {
      return jsonResponse({
        ok: false,
        error: 'Code.gs or Script Properties configuration is incomplete',
      });
    }

    const body = parseBody(e);
    if (!body || body.schema_version !== 1) {
      return jsonResponse({ok: false, error: 'Unsupported payload'});
    }
    if (!safeEqual(body.api_key, expectedKey)) {
      return jsonResponse({ok: false, error: 'Unauthorized'});
    }
    if (!safeEqual(body.spreadsheet_id, spreadsheetId)) {
      return jsonResponse({ok: false, error: 'Spreadsheet ID mismatch'});
    }

    const scans = Array.isArray(body.scans) ? body.scans : [];
    const operations = Array.isArray(body.operations) ? body.operations : [];
    if (scans.length > 50000 || operations.length > 50000) {
      return jsonResponse({ok: false, error: 'Payload is too large'});
    }

    const lock = LockService.getScriptLock();
    lock.waitLock(30000);
    try {
      return writeUpload(spreadsheetId, body, scans, operations);
    } finally {
      lock.releaseLock();
    }
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: String(error && error.message ? error.message : error),
    });
  }
}

function writeUpload(spreadsheetId, body, scans, operations) {
  const spreadsheet = SpreadsheetApp.openById(spreadsheetId);
  const scanSheet = ensureSheet(spreadsheet, 'scans', SCAN_HEADERS, true);
  const operationSheet = ensureSheet(
    spreadsheet,
    'operations',
    OPERATION_HEADERS,
    true,
  );
  const uploadSheet = ensureSheet(spreadsheet, 'uploads', UPLOAD_HEADERS);
  const summarySheet = ensureSheet(spreadsheet, 'summary', SUMMARY_HEADERS);

  const receivedAt = new Date().toISOString();
  const existingScanIds = readIds(scanSheet);
  const existingOperationIds = readIds(operationSheet);

  const scanRows = [];
  let scanDuplicates = 0;
  for (const record of scans) {
    const id = cleanText(record.record_id);
    if (!id || existingScanIds.has(id)) {
      scanDuplicates++;
      continue;
    }
    existingScanIds.add(id);
    scanRows.push([
      id,
      cleanText(record.station_id || body.station_id),
      cleanText(record.station_name || body.station_name),
      Number(record.seq || 0),
      cleanText(record.card),
      cleanText(record.at_local),
      cleanText(record.at_utc),
      cleanText(record.duplicate_of),
      cleanText(record.term),
      receivedAt,
    ]);
  }

  const operationRows = [];
  let operationDuplicates = 0;
  for (const event of operations) {
    const id = cleanText(event.event_id);
    if (!id || existingOperationIds.has(id)) {
      operationDuplicates++;
      continue;
    }
    existingOperationIds.add(id);
    operationRows.push([
      id,
      cleanText(event.station_id || body.station_id),
      cleanText(event.type),
      cleanText(event.at_local),
      cleanText(event.at_utc),
      cleanText(JSON.stringify(event.detail || {})),
      receivedAt,
    ]);
  }

  appendRows(scanSheet, scanRows);
  appendRows(operationSheet, operationRows);

  const accepted = scanRows.length + operationRows.length;
  const duplicates = scanDuplicates + operationDuplicates;
  appendRows(uploadSheet, [[
    cleanText(body.batch_id),
    cleanText(body.station_id),
    cleanText(body.station_name),
    cleanText(body.uploaded_at),
    receivedAt,
    scans.length,
    operations.length,
    accepted,
    duplicates,
  ]]);

  upsertSummary(summarySheet, body, scans, operations, receivedAt);
  SpreadsheetApp.flush();

  return jsonResponse({
    ok: true,
    accepted,
    duplicates,
    scans: {
      accepted: scanRows.length,
      duplicates: scanDuplicates,
    },
    operations: {
      accepted: operationRows.length,
      duplicates: operationDuplicates,
    },
    received_at: receivedAt,
  });
}

// The summary describes a station, not a request. A station now sends only
// what this sheet has not confirmed yet, so the batch in hand is a slice and
// counting it would make the summary report whichever slice arrived last. The
// station therefore states its own totals, which it is the only party that
// knows. A payload without them came from a station still sending its whole
// log every time, where the batch is the total.
function upsertSummary(sheet, body, scans, operations, receivedAt) {
  const stationId = cleanText(body.station_id);
  const totals = body.station_totals || {};
  const totalScans = numberOr(totals.scans, scans.length);
  const duplicateScans = numberOr(
    totals.duplicate_scans,
    scans.filter((record) => record.duplicate_of).length,
  );
  const row = [
    stationId,
    cleanText(body.station_name),
    totalScans - duplicateScans,
    duplicateScans,
    totalScans,
    numberOr(totals.operations, operations.length),
    receivedAt,
  ];

  let targetRow = sheet.getLastRow() + 1;
  if (sheet.getLastRow() >= 2) {
    const ids = sheet
      .getRange(2, 1, sheet.getLastRow() - 1, 1)
      .getDisplayValues();
    const index = ids.findIndex((value) => value[0] === stationId);
    if (index >= 0) targetRow = index + 2;
  }

  const range = sheet.getRange(targetRow, 1, 1, SUMMARY_HEADERS.length);
  range.setValues([row]);
}

// `asText` keeps a record sheet's columns formatted as plain text. Without it
// Sheets reinterprets what is written: an ISO timestamp becomes a date value
// that reads back in the spreadsheet's locale, and a card id with leading
// zeros becomes a number that no longer matches the card. Both losses are
// silent, and both only surface once the results are already wrong.
function ensureSheet(spreadsheet, name, headers, asText) {
  const sheet =
      spreadsheet.getSheetByName(name) || spreadsheet.insertSheet(name);
  if (sheet.getLastRow() === 0) {
    if (asText) {
      sheet
        .getRange(1, 1, sheet.getMaxRows(), headers.length)
        .setNumberFormat('@');
    }
    const headerRange = sheet.getRange(1, 1, 1, headers.length);
    headerRange.setValues([headers]);
    headerRange.setFontWeight('bold');
    headerRange.setBackground('#dbeafe');
    sheet.setFrozenRows(1);
    sheet.autoResizeColumns(1, headers.length);
  }
  return sheet;
}

function numberOr(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : fallback;
}

function readIds(sheet) {
  if (sheet.getLastRow() < 2) return new Set();
  return new Set(
    sheet
      .getRange(2, 1, sheet.getLastRow() - 1, 1)
      .getDisplayValues()
      .map((row) => row[0])
      .filter(Boolean),
  );
}

function appendRows(sheet, rows) {
  if (!rows.length) return;
  const range = sheet.getRange(
    sheet.getLastRow() + 1,
    1,
    rows.length,
    rows[0].length,
  );
  range.setValues(rows);
}

function parseBody(e) {
  if (!e || !e.postData || !e.postData.contents) return null;
  return JSON.parse(e.postData.contents);
}

function safeEqual(actual, expected) {
  const left = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    String(actual || ''),
  );
  const right = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    String(expected || ''),
  );
  if (left.length !== right.length) return false;

  let difference = 0;
  for (let i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference === 0;
}

function configValue(name) {
  const value = String(SCANPOINT_CONFIG[name] || '');
  if (value && !/^__SCANPOINT_[A-Z_]+__$/.test(value)) return value;
  const propertyNames = {
    spreadsheetId: 'SPREADSHEET_ID',
    uploadKey: 'UPLOAD_KEY',
    readKey: 'READ_KEY',
  };
  return PropertiesService.getScriptProperties().getProperty(propertyNames[name]) || '';
}

function cleanText(value) {
  if (value === null || value === undefined) return '';
  const text = String(value);
  return /^[=+\-@]/.test(text) ? "'" + text : text;
}

function jsonResponse(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}