import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scan_point/src/upload/apps_script_uploader.dart';
import 'package:scan_point/src/upload/batch_upload.dart';
import 'package:scan_point/src/upload/upload_cursor.dart';

void main() {
  late Directory root;
  final endpoint = Uri.parse(
    'https://script.google.com/macros/s/deployment/exec',
  );

  setUp(() => root = Directory.systemTemp.createTempSync('batch_upload_test'));
  tearDown(() => root.deleteSync(recursive: true));

  UploadCursorStore openCursors() =>
      UploadCursorStore(File('${root.path}/${UploadCursorStore.fileName}'));

  List<Map<String, dynamic>> scans(int count, {int from = 1}) => [
    for (var index = from; index < from + count; index++)
      <String, dynamic>{
        'record_id': 'scan-$index',
        'seq': index,
        'card': 'CARD$index',
        'station_id': 'CP1',
        'at_utc': '2026-08-10T01:00:00.000Z',
      },
  ];

  List<Map<String, dynamic>> operations(int count) => [
    for (var index = 1; index <= count; index++)
      <String, dynamic>{'event_id': 'event-$index', 'type': 'scan_ok'},
  ];

  /// Accepts everything, recording each payload it was sent.
  (http.Client, List<Map<String, dynamic>>) acceptingClient({
    bool Function(int call)? failOn,
  }) {
    final payloads = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      payloads.add(payload);
      if (failOn != null && failOn(payloads.length)) {
        return http.Response('{"ok":false,"error":"Service unavailable"}', 200);
      }
      return http.Response(
        jsonEncode({
          'ok': true,
          'accepted':
              (payload['scans'] as List).length +
              (payload['operations'] as List).length,
          'duplicates': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    return (client, payloads);
  }

  Future<BatchUploadResult> upload(
    http.Client client, {
    required List<Map<String, dynamic>> scanLog,
    List<Map<String, dynamic>> operationLog = const [],
    int batchSize = 2000,
    String spreadsheetId = 'sheet-one',
  }) => BatchUpload(
    uploader: AppsScriptUploader(client),
    cursors: openCursors(),
    batchSize: batchSize,
  ).run(
    endpoint: endpoint,
    apiKey: 'secret',
    spreadsheetId: spreadsheetId,
    stationId: 'CP1',
    stationName: '起點',
    scans: scanLog,
    operations: operationLog,
  );

  test('a second upload sends only what the sheet has not confirmed', () async {
    final (client, payloads) = acceptingClient();

    final first = await upload(client, scanLog: scans(3));
    expect(first.ok, isTrue);
    expect(first.sentScans, 3);
    expect(first.batches, 1);

    // Two more scans arrive; the log is the whole log, as it always is.
    final second = await upload(client, scanLog: scans(5));
    expect(second.ok, isTrue);
    expect(second.sentScans, 2, reason: 'only the new records');
    expect(
      (payloads.last['scans'] as List)
          .map((record) => (record as Map)['record_id']),
      ['scan-4', 'scan-5'],
    );
  });

  test('an upload with nothing new sends no request at all', () async {
    final (client, payloads) = acceptingClient();
    await upload(client, scanLog: scans(3));

    final repeat = await upload(client, scanLog: scans(3));
    expect(repeat.ok, isTrue);
    expect(repeat.nothingToSend, isTrue);
    expect(repeat.batches, 0);
    expect(payloads, hasLength(1), reason: 'no second request was made');
  });

  test('a long log is split into bounded batches', () async {
    final (client, payloads) = acceptingClient();

    final result = await upload(client, scanLog: scans(5), batchSize: 2);

    expect(result.ok, isTrue);
    expect(result.batches, 3);
    expect(result.sentScans, 5);
    expect(
      payloads.map((payload) => (payload['scans'] as List).length),
      [2, 2, 1],
    );
    // Each request is its own batch as far as the receiver is concerned.
    expect(payloads.map((payload) => payload['batch_id']).toSet(), hasLength(3));
  });

  test('a failure mid-run keeps the batches that were confirmed', () async {
    final (client, payloads) = acceptingClient(failOn: (call) => call == 3);

    final result = await upload(client, scanLog: scans(10), batchSize: 2);

    expect(result.ok, isFalse);
    expect(result.isPartial, isTrue);
    expect(result.sentScans, 4, reason: 'two batches confirmed before failing');
    expect(result.error, 'Service unavailable');

    final cursor = await openCursors().load();
    expect(cursor.scans, 4);
    expect(cursor.lastScanId, 'scan-4');

    // Pressing upload again resumes instead of starting over.
    payloads.clear();
    final (retryClient, retryPayloads) = acceptingClient();
    final retry = await upload(retryClient, scanLog: scans(10), batchSize: 2);

    expect(retry.ok, isTrue);
    expect(retry.sentScans, 6);
    expect(
      (retryPayloads.first['scans'] as List)
          .map((record) => (record as Map)['record_id']),
      ['scan-5', 'scan-6'],
    );
  });

  test('a log that no longer matches the cursor is resent in full', () async {
    final (client, _) = acceptingClient();
    await upload(client, scanLog: scans(4));

    // The log was restored from a backup and now holds different records.
    final (rebuiltClient, rebuiltPayloads) = acceptingClient();
    final result = await upload(
      rebuiltClient,
      scanLog: scans(2, from: 100),
    );

    expect(result.sentScans, 2);
    expect(
      (rebuiltPayloads.single['scans'] as List)
          .map((record) => (record as Map)['record_id']),
      ['scan-100', 'scan-101'],
    );
  });

  test('repointing at another spreadsheet uploads the whole log', () async {
    final (client, _) = acceptingClient();
    await upload(client, scanLog: scans(4));

    final (freshClient, freshPayloads) = acceptingClient();
    final result = await upload(
      freshClient,
      scanLog: scans(4),
      spreadsheetId: 'sheet-two',
    );

    expect(result.sentScans, 4);
    expect((freshPayloads.single['scans'] as List), hasLength(4));
  });

  test('scans and operations advance on their own cursors', () async {
    final (client, payloads) = acceptingClient();

    final result = await upload(
      client,
      scanLog: scans(3),
      operationLog: operations(5),
      batchSize: 2,
    );

    expect(result.ok, isTrue);
    expect(result.sentScans, 3);
    expect(result.sentOperations, 5);
    expect(
      payloads.map((payload) => (payload['scans'] as List).length),
      [2, 1, 0],
    );
    expect(
      payloads.map((payload) => (payload['operations'] as List).length),
      [2, 2, 1],
    );

    final cursor = await openCursors().load();
    expect(cursor.scans, 3);
    expect(cursor.operations, 5);
    expect(cursor.lastOperationId, 'event-5');
  });

  test('every batch carries the station totals, not the slice size', () async {
    final (client, payloads) = acceptingClient();
    final log = [
      ...scans(2),
      {...scans(1, from: 3).single, 'duplicate_of': '2026-08-10T01:00:00.000'},
    ];

    await upload(client, scanLog: log, batchSize: 1);

    for (final payload in payloads) {
      final totals = payload['station_totals'] as Map<String, dynamic>;
      expect(totals['scans'], 3);
      expect(totals['duplicate_scans'], 1);
    }
  });

  test('a network failure is reported without advancing the cursor', () async {
    final client = MockClient((_) async => throw const SocketException('down'));

    final result = await upload(client, scanLog: scans(3));

    expect(result.ok, isFalse);
    expect(result.isPartial, isFalse);
    expect(result.error, contains('down'));
    expect((await openCursors().load()).scans, 0);
  });
}
