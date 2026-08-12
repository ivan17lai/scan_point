import 'dart:convert';
import 'dart:io';

import '../model/stable_record_id.dart';

/// What happened. Kept as a closed set so the log can be filtered after an
/// event without guessing at free-text strings.
enum EventType {
  appStart('app_start'),
  appExit('app_exit'),
  scanOk('scan_ok'),
  scanDuplicate('scan_duplicate'),
  scanFail('scan_fail'),
  adminUnlock('admin_unlock'),
  adminPinRejected('admin_pin_rejected'),
  adminExit('admin_exit'),
  configChange('config_change'),
  storageChange('storage_change'),
  exportRun('export'),
  uploadRun('upload'),
  writeError('write_error');

  const EventType(this.wire);
  final String wire;
}

/// One decoded line from the operational history.
class EventRecord {
  const EventRecord({
    required this.eventId,
    required this.at,
    required this.type,
    required this.stationId,
    required this.detail,
  });

  final String eventId;
  final DateTime at;
  final String type;
  final String? stationId;
  final Map<String, Object?> detail;

  static EventRecord fromJson(Map<String, dynamic> json) {
    final rawDetail = json['detail'];
    final detail = rawDetail is Map
        ? <String, Object?>{
            for (final entry in rawDetail.entries)
              entry.key.toString(): entry.value,
          }
        : const <String, Object?>{};
    final at =
        DateTime.tryParse(json['at_local'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final type = json['type'] as String? ?? 'unknown';
    final stationId = json['station_id'] as String?;
    return EventRecord(
      eventId:
          json['event_id'] as String? ??
          stableRecordId('event', [
            stationId,
            type,
            json['at_utc'] ?? json['at_local'],
            detail,
          ]),
      at: at,
      type: type,
      stationId: stationId,
      detail: detail,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'event_id': eventId,
    'station_id': stationId,
    'type': type,
    'at_local': at.toIso8601String(),
    'at_utc': at.toUtc().toIso8601String(),
    if (detail.isNotEmpty) 'detail': detail,
  };
}

/// Append-only record of everything the software did, next to the scan log.
///
/// Separate from the scan log on purpose. The scan log is the result — the rows
/// that become someone's finishing time — and it stays clean enough to hand to
/// a spreadsheet untouched. This is the operational trail: failed reads, PIN
/// attempts, settings that were changed and when. After an unattended event the
/// question is usually "why is this runner's punch missing", and answering it
/// needs the failures and the configuration changes, not just the successes.
///
/// Nothing here is allowed to throw. A station that stops recording scans
/// because its diary could not be written would be an absurd way to lose a
/// race.
class EventLog {
  EventLog(this._targets);

  /// Folders that receive the log, in write order.
  List<Directory> _targets;

  static const String fileName = 'events.jsonl';
  static const String csvFileName = 'system_operations.csv';
  static const String _csvHeader =
      'at_local,at_utc,event_type,station_id,detail';

  /// Values that must never reach the log. It travels on a USB stick and may
  /// end up in a shared spreadsheet.
  static const Set<String> _redacted = {'pin', 'upload_token', 'UPLOAD_KEY'};

  set targets(List<Directory> value) => _targets = value;

  /// Reads the EXE-side primary operational log, newest first.
  ///
  /// Other targets are append-only safety copies. They are intentionally not
  /// used as automatic fallbacks, so old archive data cannot silently alter the
  /// live station state.
  Future<List<EventRecord>> history() async {
    if (_targets.isEmpty) return const <EventRecord>[];
    final file = File('${_targets.first.path}/$fileName');
    if (!file.existsSync()) return const <EventRecord>[];

    final loaded = <EventRecord>[];
    try {
      for (final line in await file.readAsLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          loaded.add(
            EventRecord.fromJson(jsonDecode(trimmed) as Map<String, dynamic>),
          );
        } catch (_) {
          // Keep every intact line around a torn or malformed one.
        }
      }
    } catch (_) {
      return const <EventRecord>[];
    }
    return List<EventRecord>.unmodifiable(loaded.reversed);
  }

  Future<void> record(
    EventType type, {
    String? stationId,
    Map<String, Object?> detail = const {},
  }) async {
    final now = DateTime.now();
    final safeDetail = detail.isEmpty
        ? const <String, Object?>{}
        : redact(detail);
    final line = <String, Object?>{
      'event_id': stableRecordId('event', [
        stationId,
        type.wire,
        now.toUtc().toIso8601String(),
        safeDetail,
      ]),
      'at_local': now.toIso8601String(),
      'at_utc': now.toUtc().toIso8601String(),
      'type': type.wire,
      'station_id': ?stationId,
      if (safeDetail.isNotEmpty) 'detail': safeDetail,
    };
    final encoded = '${jsonEncode(line)}\n';
    final csvRow = [
      _quoteCsv(now.toIso8601String()),
      _quoteCsv(now.toUtc().toIso8601String()),
      _quoteCsv(type.wire),
      _quoteCsv(stationId ?? ''),
      _quoteCsv(detail.isEmpty ? '' : jsonEncode(safeDetail)),
    ].join(',');

    for (final dir in _targets) {
      try {
        await dir.create(recursive: true);
        await File(
          '${dir.path}/$fileName',
        ).writeAsString(encoded, mode: FileMode.append, flush: true);
      } catch (_) {
        // Deliberately silent: see the class doc.
      }
      try {
        final csv = File('${dir.path}/$csvFileName');
        final needsHeader = !csv.existsSync() || csv.lengthSync() == 0;
        await csv.writeAsString(
          '${needsHeader ? '\uFEFF$_csvHeader\n' : ''}$csvRow\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // The machine-readable log and other targets must still be attempted.
      }
    }
  }

  static String _quoteCsv(String value) => '"${value.replaceAll('"', '""')}"';

  /// Replaces secret values with a marker, keeping the fact that the field
  /// changed — which is the part worth auditing.
  static Map<String, Object?> redact(Map<String, Object?> detail) => {
    for (final entry in detail.entries)
      entry.key: _redacted.contains(entry.key) ? '<已隱藏>' : entry.value,
  };
}
