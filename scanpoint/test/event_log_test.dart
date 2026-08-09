import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/storage/event_log.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('event_log_test'));
  tearDown(() => root.deleteSync(recursive: true));

  List<Map<String, dynamic>> read(Directory dir) =>
      File('${dir.path}/${EventLog.fileName}')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();

  List<String> readCsv(Directory dir) =>
      File('${dir.path}/${EventLog.csvFileName}').readAsLinesSync();

  test('writes one line per event to every target', () async {
    final app = Directory('${root.path}/app');
    final usb = Directory('${root.path}/usb');
    final log = EventLog([app, usb]);

    await log.record(EventType.appStart, stationId: 'CP3');
    await log.record(
      EventType.scanFail,
      stationId: 'CP3',
      detail: {'code': 'E-02'},
    );

    for (final dir in [app, usb]) {
      final lines = read(dir);
      expect(lines, hasLength(2));
      expect(lines.first['type'], 'app_start');
      expect(lines.first['station_id'], 'CP3');
      expect(lines.last['detail']['code'], 'E-02');
      expect(lines.last['at_utc'], endsWith('Z'));

      final csv = readCsv(dir);
      expect(csv, hasLength(3), reason: '標題列加上兩筆事件');
      expect(csv.first, contains('event_type'));
      expect(csv[1], contains('app_start'));
      expect(csv[2], contains('scan_fail'));
      expect(csv[2], contains('E-02'));
    }
  });

  test('never writes the PIN or the upload token', () async {
    final app = Directory('${root.path}/app');
    final log = EventLog([app]);

    await log.record(
      EventType.configChange,
      stationId: 'CP3',
      detail: {
        'station_name': '水源地',
        'pin': '135790',
        'upload_token': 'super-secret',
      },
    );

    final raw = File('${app.path}/${EventLog.fileName}').readAsStringSync();
    final csvRaw = File(
      '${app.path}/${EventLog.csvFileName}',
    ).readAsStringSync();
    expect(raw, contains('水源地'), reason: '非機密的變更要看得見');
    expect(raw, isNot(contains('135790')));
    expect(raw, isNot(contains('super-secret')));
    expect(csvRaw, contains('水源地'));
    expect(csvRaw, isNot(contains('135790')));
    expect(csvRaw, isNot(contains('super-secret')));

    final detail = read(app).single['detail'] as Map<String, dynamic>;
    expect(
      detail.keys,
      containsAll(['pin', 'upload_token']),
      reason: '欄位被改過這件事本身要留下',
    );
  });

  test('an unusable target never throws', () async {
    // A file sitting where the folder should be — a stick that was configured
    // but never plugged in behaves the same way.
    final blocked = File('${root.path}/blocked')..writeAsStringSync('x');
    final good = Directory('${root.path}/good');
    final log = EventLog([Directory(blocked.path), good]);

    await expectLater(log.record(EventType.appStart), completes);
    expect(read(good), hasLength(1), reason: '可用的目標仍要寫進去');
    expect(readCsv(good), hasLength(2));
  });
  test('history reads newest first and skips a torn final line', () async {
    final app = Directory('${root.path}/app');
    final archive = Directory('${root.path}/archive');
    final log = EventLog([app, archive]);

    await log.record(EventType.appStart, stationId: 'CP3');
    await log.record(
      EventType.scanFail,
      stationId: 'CP3',
      detail: {'code': 'E-02'},
    );
    await File(
      '${app.path}/${EventLog.fileName}',
    ).writeAsString('{"incomplete":', mode: FileMode.append);

    await File('${archive.path}/${EventLog.fileName}').writeAsString(
      '${jsonEncode({'event_id': 'archive-only', 'at_local': DateTime.now().toIso8601String(), 'at_utc': DateTime.now().toUtc().toIso8601String(), 'type': 'archive_only', 'station_id': 'CP3'})}\n',
      mode: FileMode.append,
    );

    final history = await log.history();

    expect(history, hasLength(2), reason: 'AppData archive 的額外事件不得混入正常歷史');
    expect(history.first.type, EventType.scanFail.wire);
    expect(history.first.detail['code'], 'E-02');
    expect(history.last.type, EventType.appStart.wire);
    expect(history.first.eventId, startsWith('event-'));
    expect(history.first.toJson()['event_id'], history.first.eventId);
  });
}
