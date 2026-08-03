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

/// Append-only, triple-written log.
///
/// No database on purpose. At an unattended station the realistic failure is a
/// flat battery or someone yanking the power, and a line-buffered text file that
/// is flushed per record degrades to "the last line might be short" — whereas a
/// half-written database page can take the whole file with it. Three copies in
/// two directories means a lost card is recoverable by reconciliation.
class ScanStore {
  ScanStore._(this._primaryDir, this._mirrorDir, this._exportDir);

  final Directory _primaryDir;
  final Directory _mirrorDir;
  final Directory _exportDir;

  final List<ScanRecord> _records = <ScanRecord>[];

  /// `"<stationId>|<cardId>"` -> first time that card was seen at that station.
  final Map<String, DateTime> _firstSeen = <String, DateTime>{};

  int _sequence = 0;

  /// Set when a write to any destination throws, surfaced in the admin panel.
  String? lastWriteError;

  static const String _logName = 'scans.jsonl';

  Directory get primaryDir => _primaryDir;
  Directory get mirrorDir => _mirrorDir;
  Directory get exportDir => _exportDir;

  /// Scans recorded at [stationId], duplicates excluded.
  int countFor(String stationId) =>
      _records.where((r) => r.stationId == stationId && !r.isDuplicate).length;

  int get totalLines => _records.length;

  List<ScanRecord> recentFor(String stationId, {int limit = 12}) => _records
      .where((r) => r.stationId == stationId)
      .toList()
      .reversed
      .take(limit)
      .toList();

  static Future<ScanStore> open() async {
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();

    final primary = Directory('${support.path}/data');
    final mirror = Directory('${documents.path}/OrienteeringSystem/mirror');
    final export = Directory('${documents.path}/OrienteeringSystem/export');
    for (final dir in [primary, mirror, export]) {
      await dir.create(recursive: true);
    }

    return openAt(primary: primary, mirror: mirror, export: export);
  }

  /// Same as [open] with the directories supplied, so tests can point at a temp
  /// folder instead of the real app-support location.
  static Future<ScanStore> openAt({
    required Directory primary,
    required Directory mirror,
    required Directory export,
  }) async {
    for (final dir in [primary, mirror, export]) {
      await dir.create(recursive: true);
    }
    final store = ScanStore._(primary, mirror, export);
    await store._load();
    return store;
  }

  Future<void> _load() async {
    // The primary is authoritative on load; if it is missing or truncated the
    // mirror is tried, which is the whole reason the mirror exists.
    for (final dir in [_primaryDir, _mirrorDir]) {
      final file = File('${dir.path}/$_logName');
      if (!file.existsSync()) continue;
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
      if (loaded.length > _records.length) {
        _records
          ..clear()
          ..addAll(loaded);
      }
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
    final csvDay =
        '${record.at.year.toString().padLeft(4, '0')}-'
        '${record.at.month.toString().padLeft(2, '0')}-'
        '${record.at.day.toString().padLeft(2, '0')}';

    var primaryOk = false;
    var anyOk = false;
    Object? firstError;

    for (final dir in [_primaryDir, _mirrorDir]) {
      try {
        await File(
          '${dir.path}/$_logName',
        ).writeAsString(jsonLine, mode: FileMode.append, flush: true);
        anyOk = true;
        if (dir == _primaryDir) primaryOk = true;
      } catch (e) {
        firstError ??= e;
      }
    }

    try {
      final csv = File('${_primaryDir.path}/scans-$csvDay.csv');
      final needsHeader = !csv.existsSync() || csv.lengthSync() == 0;
      await csv.writeAsString(
        '${needsHeader ? '${ScanRecord.csvHeader}\n' : ''}${record.toCsvRow()}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      firstError ??= e;
    }

    if (firstError != null) {
      lastWriteError = '${primaryOk ? '鏡像檔' : '主檔'}寫入異常:$firstError';
    } else {
      lastWriteError = null;
    }
    // One surviving copy of the JSONL is enough to call the scan recorded; the
    // runner must not be sent away for a failure that did not lose data.
    return anyOk;
  }

  /// Copies every log file into the export folder under a timestamped name.
  Future<Directory> exportAll() async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')
        .first;
    final target = Directory('${_exportDir.path}/export-$stamp');
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
