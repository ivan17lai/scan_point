import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/scanner/scan_decoder.dart';
import 'package:scan_point/src/storage/scan_store.dart';

void main() {
  late Directory root;
  late Directory primary;
  late Directory mirror;
  late Directory export;

  Future<ScanStore> openStore() =>
      ScanStore.openAt(primary: primary, mirror: mirror, export: export);

  Future<ScanOutcome> scan(ScanStore store, String card) => store.record(
    cardId: card,
    stationId: 'CP3',
    stationName: '水源地',
    terminator: FrameTerminator.semicolon,
    raw: card,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('scan_store_test');
    primary = Directory('${root.path}/primary');
    mirror = Directory('${root.path}/mirror');
    export = Directory('${root.path}/export');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('writes every scan to the primary, the mirror, and the CSV', () async {
    final store = await openStore();
    await scan(store, 'A7F3C210');

    final primaryLines = File(
      '${primary.path}/scans.jsonl',
    ).readAsLinesSync().where((l) => l.trim().isNotEmpty);
    final mirrorLines = File(
      '${mirror.path}/scans.jsonl',
    ).readAsLinesSync().where((l) => l.trim().isNotEmpty);

    expect(primaryLines, hasLength(1));
    expect(mirrorLines, hasLength(1));
    expect(jsonDecode(primaryLines.first)['card'], 'A7F3C210');

    final csv = primary.listSync().whereType<File>().firstWhere(
      (f) => f.path.endsWith('.csv'),
    );
    final csvLines = csv.readAsLinesSync();
    expect(csvLines.first, startsWith('seq,card_id'));
    expect(csvLines[1], contains('A7F3C210'));
  });

  test(
    'a second scan of the same card is flagged, not counted again',
    () async {
      final store = await openStore();
      final first = await scan(store, 'BEEF01');
      final second = await scan(store, 'BEEF01');

      expect(first.isDuplicate, isFalse);
      expect(second.isDuplicate, isTrue);
      expect(second.firstSeenAt, first.record!.at);
      expect(store.countFor('CP3'), 1);
      // The duplicate is still on disk — the evidence matters even though the
      // count does not move.
      expect(store.totalLines, 2);
    },
  );

  test('the same card at a different station is a new record', () async {
    final store = await openStore();
    await scan(store, 'BEEF01');
    final other = await store.record(
      cardId: 'BEEF01',
      stationId: 'CP4',
      stationName: '稜線',
      terminator: FrameTerminator.semicolon,
      raw: 'BEEF01',
    );

    expect(other.isDuplicate, isFalse);
    expect(store.countFor('CP3'), 1);
    expect(store.countFor('CP4'), 1);
  });

  test('reopening restores the count and the duplicate memory', () async {
    final first = await openStore();
    await scan(first, 'AAAA1111');
    await scan(first, 'BBBB2222');

    final reopened = await openStore();
    expect(reopened.countFor('CP3'), 2);
    expect((await scan(reopened, 'AAAA1111')).isDuplicate, isTrue);
  });

  test(
    'a torn last line from a power cut does not lose earlier scans',
    () async {
      final store = await openStore();
      await scan(store, 'AAAA1111');
      await scan(store, 'BBBB2222');

      // Simulate the write that was in flight when the power went.
      final file = File('${primary.path}/scans.jsonl');
      file.writeAsStringSync('{"seq":3,"card":"CCC', mode: FileMode.append);

      final reopened = await ScanStore.openAt(
        primary: primary,
        mirror: Directory('${root.path}/empty-mirror'),
        export: export,
      );
      expect(reopened.countFor('CP3'), 2);
    },
  );

  test('falls back to the mirror when the primary is missing', () async {
    final store = await openStore();
    await scan(store, 'AAAA1111');
    File('${primary.path}/scans.jsonl').deleteSync();

    final reopened = await openStore();
    expect(reopened.countFor('CP3'), 1);
  });

  test('export copies the log files into a timestamped folder', () async {
    final store = await openStore();
    await scan(store, 'AAAA1111');

    final target = await store.exportAll();
    final names = target
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList();
    expect(names, contains('scans.jsonl'));
    expect(names.any((n) => n.endsWith('.csv')), isTrue);
  });
}
