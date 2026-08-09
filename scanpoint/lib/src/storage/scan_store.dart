import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../model/scan_record.dart';
import '../scanner/scan_decoder.dart';

/// Result of handing a decoded card to the store.
class ScanOutcome {
  const ScanOutcome.recorded(this.record) : firstSeenAt = null, failed = false;
  const ScanOutcome.duplicate(this.record, this.firstSeenAt) : failed = false;
  const ScanOutcome.failed() : record = null, firstSeenAt = null, failed = true;

  final ScanRecord? record;
  final DateTime? firstSeenAt;
  final bool failed;

  bool get isDuplicate => firstSeenAt != null;
}

/// Append-only, redundantly written log.
///
/// No database on purpose. At an unattended station the realistic failure is a
/// flat battery or someone yanking the power, and a line-buffered text file that
/// is flushed per record degrades to "the last line might be short" — whereas a
/// half-written database page can take the whole file with it. Independent
/// copies mean a lost card is recoverable by reconciliation.
class ScanStore {
  ScanStore._(this._primaryDir, this._archiveDir, this._extraDir);

  final Directory _primaryDir;
  final Directory _archiveDir;

  /// Optional third copy, chosen by the operator — typically a USB stick.
  ///
  /// Additive, never a redirect: the two default copies keep being written
  /// exactly as before. Unplugging the stick therefore costs nothing that
  /// existed before it was plugged in, which is the whole point of it being an
  /// extra rather than a replacement.
  final Directory? _extraDir;

  final List<ScanRecord> _records = <ScanRecord>[];

  /// `"<stationId>|<cardId>"` -> first time that card was seen at that station.
  final Map<String, DateTime> _firstSeen = <String, DateTime>{};

  int _sequence = 0;

  /// Set when a write to any destination throws, surfaced in the admin panel.
  String? lastWriteError;

  static const String _logName = 'scans.jsonl';

  Directory get primaryDir => _primaryDir;
  Directory get archiveDir => _archiveDir;
  Directory? get extraDir => _extraDir;

  /// Where the extra copy for [stationId] goes, or null when none is set.
  ///
  /// One USB stick is very likely to collect several machines, so the extra
  /// copy is namespaced per station. Without this the second machine plugged in
  /// would overwrite the first one's log — [seedExtraCopy] rewrites files
  /// wholesale rather than appending, so the loss would be silent and total.
  Directory? extraDirFor(String stationId) {
    final extra = _extraDir;
    if (extra == null) return null;
    return Directory('${extra.path}/scan_point/${safeName(stationId)}');
  }

  /// Station ids are typed by hand and land in a path, so anything the
  /// filesystem would object to is folded away.
  static String safeName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  /// Scans recorded at [stationId], duplicates excluded.
  int countFor(String stationId) =>
      _records.where((r) => r.stationId == stationId && !r.isDuplicate).length;

  int get totalLines => _records.length;

  /// Complete scan history, newest first.
  List<ScanRecord> get history =>
      List<ScanRecord>.unmodifiable(_records.reversed);

  List<ScanRecord> recentFor(String stationId, {int limit = 12}) => _records
      .where((r) => r.stationId == stationId)
      .toList()
      .reversed
      .take(limit)
      .toList();

  /// Opens the store.
  ///
  /// [extraDir] adds a third copy alongside the two defaults; it never
  /// replaces them. The primary lives beside the executable; the AppData copy
  /// is an append-only archive that is never loaded automatically.
  static Future<ScanStore> open({String? extraDir}) async {
    final support = await getApplicationSupportDirectory();
    final executableDir = File(Platform.resolvedExecutable).parent;
    final primary = Directory('${executableDir.path}/data');
    // Keep the established AppData/data location so existing history remains
    // present. It is now an append-only archive, not a normal read source.
    final archive = Directory('${support.path}/data');

    await migrateLegacyLayout(
      legacyArchive: archive,
      primary: primary,
      marker: File('${support.path}/.storage-layout-v2'),
    );

    return openAt(
      primary: primary,
      archive: archive,
      extra: extraDir != null && extraDir.trim().isNotEmpty
          ? Directory(extraDir.trim())
          : null,
    );
  }

  /// Copies the previous AppData primary into the new EXE-side primary once.
  ///
  /// The marker prevents this from becoming an automatic recovery mechanism:
  /// if the EXE-side data is later removed or damaged, the archive is not read
  /// or copied back automatically.
  static Future<void> migrateLegacyLayout({
    required Directory legacyArchive,
    required Directory primary,
    required File marker,
  }) async {
    if (marker.existsSync()) return;
    await primary.create(recursive: true);

    var complete = true;
    if (legacyArchive.existsSync()) {
      for (final entity in legacyArchive.listSync()) {
        if (entity is! File) continue;
        final target = File('${primary.path}/${entity.uri.pathSegments.last}');
        try {
          if (!target.existsSync() || target.lengthSync() == 0) {
            await entity.copy(target.path);
          }
        } catch (_) {
          complete = false;
        }
      }
    }

    if (!complete) return;
    try {
      await marker.parent.create(recursive: true);
      await marker.writeAsString(
        DateTime.now().toUtc().toIso8601String(),
        flush: true,
      );
    } catch (_) {
      // Repeating a missing-file-only migration is safe on the next launch.
    }
  }

  /// Confirms a chosen folder can actually be written to, by writing to it.
  ///
  /// Checking `existsSync` is not enough: a removable drive can be present but
  /// read-only, and a network share can be mounted but not writable. Returns
  /// null when the folder is usable, otherwise a message to show the operator.
  static Future<String?> probeWritable(String path) async {
    try {
      final dir = Directory(path);
      await dir.create(recursive: true);
      final probe = File(
        '${dir.path}/.scan_point_write_test_'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Writes the whole log into the extra folder, so a stick plugged in halfway
  /// through the event ends up holding the event, not just the rest of it.
  Future<String?> seedExtraCopy() async {
    if (_extraDir == null) return null;
    try {
      // Records are grouped by station because each station owns a folder on
      // the stick, and by day because the CSV is split per day.
      final byStation = <String, List<ScanRecord>>{};
      for (final record in _records) {
        byStation.putIfAbsent(record.stationId, () => []).add(record);
      }

      for (final station in byStation.entries) {
        final dir = extraDirFor(station.key)!;
        await dir.create(recursive: true);

        final jsonl = StringBuffer();
        final csvByDay = <String, StringBuffer>{};
        for (final record in station.value) {
          jsonl.writeln(jsonEncode(record.toJson()));
          csvByDay
              .putIfAbsent(
                _dayStamp(record.at),
                () => StringBuffer('${ScanRecord.csvHeader}\n'),
              )
              .writeln(record.toCsvRow());
        }

        await File(
          '${dir.path}/$_logName',
        ).writeAsString(jsonl.toString(), flush: true);
        for (final day in csvByDay.entries) {
          await File(
            '${dir.path}/scans-${day.key}.csv',
          ).writeAsString(day.value.toString(), flush: true);
        }
      }
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static String _dayStamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  /// Same as [open] with the directories supplied, so tests can point at a temp
  /// folder instead of the real app-support location.
  static Future<ScanStore> openAt({
    required Directory primary,
    required Directory archive,
    Directory? extra,
  }) async {
    // The EXE-side primary is the active data source and must be available.
    await primary.create(recursive: true);

    final store = ScanStore._(primary, archive, extra);
    for (final dir in [archive, ?extra]) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        store.lastWriteError =
            '${dir == archive ? 'AppData 常駐紀錄' : '額外備份'}資料夾無法使用:$e';
      }
    }

    await store._loadPrimary();
    return store;
  }

  Future<void> _loadPrimary() async {
    // Deliberately do not fall back to the AppData archive. It is continuously
    // written for manual recovery only and must not silently change live state.
    final file = File('${_primaryDir.path}/$_logName');
    if (file.existsSync()) {
      final loaded = <ScanRecord>[];
      for (final line in await file.readAsLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          loaded.add(
            ScanRecord.fromJson(jsonDecode(trimmed) as Map<String, dynamic>),
          );
        } catch (_) {
          // A torn final line from a power cut. Everything before it is intact.
        }
      }
      _records
        ..clear()
        ..addAll(loaded);
    }

    _firstSeen.clear();
    _sequence = 0;
    for (final r in _records) {
      _sequence = r.sequence > _sequence ? r.sequence : _sequence;
      if (r.isDuplicate) continue;
      _firstSeen.putIfAbsent(_key(r.stationId, r.cardId), () => r.at);
    }
  }

  String _key(String stationId, String cardId) => '$stationId|$cardId';

  /// Persist one decoded card. Duplicates are still written — the evidence that
  /// a runner scanned twice is worth keeping — but do not advance the count.
  Future<ScanOutcome> record({
    required String cardId,
    required String stationId,
    required String stationName,
    required FrameTerminator terminator,
    required String raw,
  }) async {
    final now = DateTime.now();
    final firstSeen = _firstSeen[_key(stationId, cardId)];

    final record = ScanRecord(
      sequence: ++_sequence,
      cardId: cardId,
      at: now,
      stationId: stationId,
      stationName: stationName,
      terminator: terminator,
      raw: raw,
      duplicateOf: firstSeen,
    );

    final ok = await _write(record);
    if (!ok) {
      _sequence--;
      return const ScanOutcome.failed();
    }

    _records.add(record);
    if (firstSeen == null) {
      _firstSeen[_key(stationId, cardId)] = now;
      return ScanOutcome.recorded(record);
    }
    return ScanOutcome.duplicate(record, firstSeen);
  }

  Future<bool> _write(ScanRecord record) async {
    final jsonLine = '${jsonEncode(record.toJson())}\n';
    final csvDay = _dayStamp(record.at);
    final extra = extraDirFor(record.stationId);

    var anyOk = false;
    final failed = <String>[];

    // (folder, label, also writes the CSV)
    final targets = <(Directory, String, bool)>[
      (_primaryDir, '主檔', true),
      (_archiveDir, 'AppData 常駐紀錄', true),
      if (extra != null) (extra, '額外備份', true),
    ];

    for (final (dir, label, withCsv) in targets) {
      try {
        await dir.create(recursive: true);
        await File(
          '${dir.path}/$_logName',
        ).writeAsString(jsonLine, mode: FileMode.append, flush: true);
        anyOk = true;
      } catch (_) {
        failed.add(label);
        continue;
      }
      if (!withCsv) continue;
      try {
        final csv = File('${dir.path}/scans-$csvDay.csv');
        final needsHeader = !csv.existsSync() || csv.lengthSync() == 0;
        await csv.writeAsString(
          '${needsHeader ? '${ScanRecord.csvHeader}\n' : ''}${record.toCsvRow()}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        failed.add('$label CSV');
      }
    }

    lastWriteError = failed.isEmpty ? null : '寫入失敗:${failed.join('、')}';
    // One surviving copy of the JSONL is enough to call the scan recorded; the
    // runner must not be sent away for a failure that did not lose data.
    return anyOk;
  }

  /// Copies every log file into [destination] under a timestamped folder.
  Future<Directory> exportAll(Directory destination) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')
        .first;
    final target = Directory('${destination.path}/export-$stamp');
    await target.create(recursive: true);
    for (final entity in _primaryDir.listSync()) {
      if (entity is File) {
        await entity.copy('${target.path}/${entity.uri.pathSegments.last}');
      }
    }
    return target;
  }

  /// Every record as a JSON list, for the manual upload.
  List<Map<String, dynamic>> toJsonList() =>
      _records.map((r) => r.toJson()).toList();
}
