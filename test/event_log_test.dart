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
    expect(raw, contains('水源地'), reason: '非機密的變更要看得見');
    expect(raw, isNot(contains('135790')));
    expect(raw, isNot(contains('super-secret')));

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
  });
}
