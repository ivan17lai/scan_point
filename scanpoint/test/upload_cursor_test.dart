import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/upload/upload_cursor.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('upload_cursor_test'));
  tearDown(() => root.deleteSync(recursive: true));

  UploadCursorStore openStore() =>
      UploadCursorStore(File('${root.path}/${UploadCursorStore.fileName}'));

  group('resumeAt', () {
    final ids = ['a', 'b', 'c', 'd'];

    test('resumes after the confirmed entries', () {
      expect(UploadCursor.resumeAt(ids, 2, 'b'), 2);
      expect(UploadCursor.resumeAt(ids, 4, 'd'), 4);
      expect(UploadCursor.resumeAt(ids, 0, ''), 0);
    });

    test('restarts when the log is not the one the count came from', () {
      // Restored from a backup taken earlier: shorter than the count.
      expect(UploadCursor.resumeAt(['a'], 3, 'c'), 0);
      // Rebuilt with different content: the boundary id no longer matches.
      expect(UploadCursor.resumeAt(ids, 2, 'z'), 0);
      // A count with no boundary id to check it against is not trusted.
      expect(UploadCursor.resumeAt(ids, 2, ''), 0);
      // Nonsense from a corrupted file must not skip anything.
      expect(UploadCursor.resumeAt(ids, -5, 'a'), 0);
    });
  });

  test('a cursor from another spreadsheet is discarded, not trusted', () {
    const cursor = UploadCursor(
      spreadsheetId: 'sheet-one',
      scans: 10,
      lastScanId: 'scan-10',
      operations: 4,
      lastOperationId: 'event-4',
    );

    expect(cursor.forSpreadsheet('sheet-one').scans, 10);

    final repointed = cursor.forSpreadsheet('sheet-two');
    expect(repointed.spreadsheetId, 'sheet-two');
    expect(repointed.scans, 0);
    expect(repointed.lastScanId, '');
    expect(repointed.operations, 0);
  });

  test('advanced records the id sitting at each new boundary', () {
    const cursor = UploadCursor(spreadsheetId: 'sheet-one');
    final advanced = cursor.advanced(
      scanIds: ['s1', 's2', 's3'],
      scanCount: 2,
      operationIds: ['e1', 'e2'],
      operationCount: 0,
    );

    expect(advanced.spreadsheetId, 'sheet-one');
    expect(advanced.scans, 2);
    expect(advanced.lastScanId, 's2');
    expect(advanced.operations, 0);
    expect(advanced.lastOperationId, '');
  });

  test('survives a round trip through the file', () async {
    final store = openStore();
    expect((await store.load()).scans, 0);

    const cursor = UploadCursor(
      spreadsheetId: 'sheet-one',
      scans: 7,
      lastScanId: 'scan-7',
      operations: 3,
      lastOperationId: 'event-3',
    );
    expect(await store.save(cursor), isNull);

    final loaded = await openStore().load();
    expect(loaded.spreadsheetId, 'sheet-one');
    expect(loaded.scans, 7);
    expect(loaded.lastScanId, 'scan-7');
    expect(loaded.operations, 3);
    expect(loaded.lastOperationId, 'event-3');
  });

  test('an unreadable cursor means a full resend, not a crash', () async {
    final file = File('${root.path}/${UploadCursorStore.fileName}');
    await file.writeAsString('{"spreadsheet_id": "sheet-one", "scans": 4');

    final loaded = await UploadCursorStore(file).load();
    expect(loaded.scans, 0);
    expect(loaded.spreadsheetId, '');
  });

  test('a cursor missing fields falls back to nothing confirmed', () async {
    final file = File('${root.path}/${UploadCursorStore.fileName}');
    await file.writeAsString(jsonEncode({'spreadsheet_id': 'sheet-one'}));

    final loaded = await UploadCursorStore(file).load();
    expect(loaded.spreadsheetId, 'sheet-one');
    expect(loaded.scans, 0);
    expect(loaded.lastScanId, '');
  });
}
