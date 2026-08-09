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

function doGet() {
  return jsonResponse({
    ok: true,
    service: 'scan_point Google Sheets uploader',
    schema_version: 1,
  });
}

function doPost(e) {
  try {
    const properties = PropertiesService.getScriptProperties();
    const spreadsheetId = properties.getProperty('SPREADSHEET_ID');
    const expectedKey = properties.getProperty('UPLOAD_KEY');

    if (!spreadsheetId || !expectedKey) {
      return jsonResponse({
        ok: false,
        error: 'Apps Script properties are not configured',
      });
    }

    const body = parseBody(e);
    if (!body || body.schema_version !== 1) {
      return jsonResponse({ok: false, error: 'Unsupported payload'});
    }
    if (!safeEqual(body.api_key, expectedKey)) {
      return jsonResponse({ok: false, error: 'Unauthorized'});
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
  const scanSheet = ensureSheet(spreadsheet, 'scans', SCAN_HEADERS);
  const operationSheet = ensureSheet(
    spreadsheet,
    'operations',
    OPERATION_HEADERS,
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

function upsertSummary(sheet, body, scans, operations, receivedAt) {
  const stationId = cleanText(body.station_id);
  const duplicateScans = scans.filter((record) => record.duplicate_of).length;
  const row = [
    stationId,
    cleanText(body.station_name),
    scans.length - duplicateScans,
    duplicateScans,
    scans.length,
    operations.length,
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

function ensureSheet(spreadsheet, name, headers) {
  const sheet =
      spreadsheet.getSheetByName(name) || spreadsheet.insertSheet(name);
  if (sheet.getLastRow() === 0) {
    const headerRange = sheet.getRange(1, 1, 1, headers.length);
    headerRange.setValues([headers]);
    headerRange.setFontWeight('bold');
    headerRange.setBackground('#dbeafe');
    sheet.setFrozenRows(1);
    sheet.autoResizeColumns(1, headers.length);
  }
  return sheet;
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