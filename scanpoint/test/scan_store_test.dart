import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/scanner/scan_decoder.dart';
import 'package:scan_point/src/storage/scan_store.dart';

void main() {
  late Directory root;
  late Directory primary;
  late Directory archive;
  late Directory export;

  Future<ScanStore> openStore() =>
      ScanStore.openAt(primary: primary, archive: archive);

  Future<ScanOutcome> scan(ScanStore store, String card) => store.record(
    cardId: card,
    stationId: 'CP3',
    stationName: '水源地',
    terminator: FrameTerminator.questionMark,
    raw: card,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('scan_store_test');
    primary = Directory('${root.path}/primary');
    archive = Directory('${root.path}/archive');
    export = Directory('${root.path}/export');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('writes every scan to the primary, the archive, and the CSV', () async {
    final store = await openStore();
    await scan(store, 'A7F3C210');

    final primaryLines = File(
      '${primary.path}/scans.jsonl',
    ).readAsLinesSync().where((l) => l.trim().isNotEmpty);
    final archiveLines = File(
      '${archive.path}/scans.jsonl',
    ).readAsLinesSync().where((l) => l.trim().isNotEmpty);

    expect(primaryLines, hasLength(1));
    expect(archiveLines, hasLength(1));
    final stored = jsonDecode(primaryLines.first) as Map<String, dynamic>;
    expect(stored['card'], 'A7F3C210');
    expect(stored['record_id'], startsWith('scan-'));

    // The archive is a full copy, CSV included — not a partial one.
    for (final dir in [primary, archive]) {
      final csv = dir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.csv'),
        orElse: () => throw StateError('${dir.path} 少了 CSV'),
      );
      final csvLines = csv.readAsLinesSync();
      expect(csvLines.first, startsWith('seq,card_id'));
      expect(csvLines[1], contains('A7F3C210'));
    }
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
      terminator: FrameTerminator.questionMark,
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
        archive: Directory('${root.path}/empty-archive'),
      );
      expect(reopened.countFor('CP3'), 2);
    },
  );

  test('does not load the archive when the primary is missing', () async {
    final store = await openStore();
    await scan(store, 'AAAA1111');
    File('${primary.path}/scans.jsonl').deleteSync();

    final reopened = await openStore();
    expect(reopened.countFor('CP3'), 0);
    expect(
      File('${archive.path}/scans.jsonl').existsSync(),
      isTrue,
      reason: '常駐紀錄仍保留，但不自動還原',
    );
  });

  test('legacy AppData files migrate only once', () async {
    final legacy = Directory('${root.path}/legacy')..createSync();
    final migratedPrimary = Directory('${root.path}/migrated-primary');
    final marker = File('${root.path}/.storage-layout-v2');
    File('${legacy.path}/scans.jsonl').writeAsStringSync('scan-history');
    File('${legacy.path}/events.jsonl').writeAsStringSync('event-history');

    await ScanStore.migrateLegacyLayout(
      legacyArchive: legacy,
      primary: migratedPrimary,
      marker: marker,
    );

    expect(
      File('${migratedPrimary.path}/scans.jsonl').readAsStringSync(),
      'scan-history',
    );
    expect(
      File('${migratedPrimary.path}/events.jsonl').readAsStringSync(),
      'event-history',
    );
    expect(marker.existsSync(), isTrue);

    File('${migratedPrimary.path}/scans.jsonl').deleteSync();
    await ScanStore.migrateLegacyLayout(
      legacyArchive: legacy,
      primary: migratedPrimary,
      marker: marker,
    );
    expect(
      File('${migratedPrimary.path}/scans.jsonl').existsSync(),
      isFalse,
      reason: '標記存在後不得把 archive 自動復原回主記錄',
    );
  });

  Iterable<String> linesOf(String path) =>
      File(path).readAsLinesSync().where((l) => l.trim().isNotEmpty);

  test(
    'the extra folder adds a copy without displacing the defaults',
    () async {
      final store = await openStore();
      await scan(store, 'AAAA1111');
      await scan(store, 'BBBB2222');

      // Operator plugs in a USB stick mid-event and adds it as an extra copy.
      final usb = Directory('${root.path}/usb');
      final withUsb = await ScanStore.openAt(
        primary: primary,
        archive: archive,
        extra: usb,
      );
      expect(await withUsb.seedExtraCopy(), isNull);

      // Namespaced per station, so one stick can collect several machines.
      final stationDir = withUsb.extraDirFor('CP3')!;
      expect(stationDir.path, '${usb.path}/scan_point/CP3');
      expect(
        linesOf('${stationDir.path}/scans.jsonl'),
        hasLength(2),
        reason: '既有紀錄要整份複製過去',
      );
      expect(
        stationDir.listSync().whereType<File>().any(
          (f) => f.path.endsWith('.csv'),
        ),
        isTrue,
        reason: '隨身碟上要有可直接開啟的 CSV',
      );

      await scan(withUsb, 'CCCC3333');

      // Three copies now, and the two defaults are untouched by the addition.
      expect(linesOf('${primary.path}/scans.jsonl'), hasLength(3));
      expect(linesOf('${archive.path}/scans.jsonl'), hasLength(3));
      expect(linesOf('${stationDir.path}/scans.jsonl'), hasLength(3));
    },
  );

  test('two stations sharing one stick do not overwrite each other', () async {
    final usb = Directory('${root.path}/usb');

    Future<void> runStation(String station) async {
      final store = await ScanStore.openAt(
        primary: Directory('${root.path}/$station-primary'),
        archive: Directory('${root.path}/$station-archive'),
        extra: usb,
      );
      await store.record(
        cardId: 'CARD$station',
        stationId: station,
        stationName: station,
        terminator: FrameTerminator.questionMark,
        raw: 'CARD$station',
      );
      await store.seedExtraCopy();
    }

    await runStation('CP3');
    await runStation('CP4');

    expect(linesOf('${usb.path}/scan_point/CP3/scans.jsonl'), hasLength(1));
    expect(linesOf('${usb.path}/scan_point/CP4/scans.jsonl'), hasLength(1));
  });

  test('a station id that is not a legal folder name is folded', () {
    expect(ScanStore.safeName('CP/3'), 'CP_3');
    expect(ScanStore.safeName('  '), 'unknown');
    expect(ScanStore.safeName('終點:A'), '終點_A');
  });

  test('pulling the stick out leaves the default copies intact', () async {
    final usb = Directory('${root.path}/usb');
    final store = await ScanStore.openAt(
      primary: primary,
      archive: archive,
      extra: usb,
    );
    await scan(store, 'AAAA1111');

    // Reopening without the extra folder is what happens after it is removed.
    final without = await openStore();
    await scan(without, 'BBBB2222');

    expect(without.countFor('CP3'), 2);
    expect(linesOf('${primary.path}/scans.jsonl'), hasLength(2));
    expect(linesOf('${archive.path}/scans.jsonl'), hasLength(2));
  });

  test(
    'probeWritable accepts a usable folder and rejects an unusable one',
    () async {
      expect(await ScanStore.probeWritable('${root.path}/fresh'), isNull);

      // A path occupied by a file cannot become a directory — portable stand-in
      // for a read-only drive or a share that is mounted but not writable.
      final blocker = File('${root.path}/blocker')..writeAsStringSync('x');
      expect(await ScanStore.probeWritable(blocker.path), isNotNull);
    },
  );

  test('a scan still counts when the extra copy fails', () async {
    // The extra path is blocked by a file — stands in for a stick that was
    // configured but never plugged in.
    final blocked = File('${root.path}/blocked')..writeAsStringSync('x');
    final store = await ScanStore.openAt(
      primary: primary,
      archive: archive,
      extra: Directory(blocked.path),
    );

    final outcome = await scan(store, 'AAAA1111');

    expect(outcome.failed, isFalse, reason: '主檔寫成功就不該退回選手');
    expect(store.countFor('CP3'), 1);
    expect(store.lastWriteError, isNotNull, reason: '但要留下警告');
  });

  test('export copies the log files into a timestamped folder', () async {
    final store = await openStore();
    await scan(store, 'AAAA1111');

    final target = await store.exportAll(export);
    final names = target
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList();
    expect(names, contains('scans.jsonl'));
    expect(names.any((n) => n.endsWith('.csv')), isTrue);
  });
}
