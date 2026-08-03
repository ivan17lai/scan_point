import 'dart:convert';
import 'dart:io';

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

  /// Values that must never reach the log. It travels on a USB stick and may
  /// end up in a shared spreadsheet.
  static const Set<String> _redacted = {'pin', 'upload_token'};

  set targets(List<Directory> value) => _targets = value;

  Future<void> record(
    EventType type, {
    String? stationId,
    Map<String, Object?> detail = const {},
  }) async {
    final now = DateTime.now();
    final line = <String, Object?>{
      'at_local': now.toIso8601String(),
      'at_utc': now.toUtc().toIso8601String(),
      'type': type.wire,
      'station_id': ?stationId,
      if (detail.isNotEmpty) 'detail': redact(detail),
    };
    final encoded = '${jsonEncode(line)}\n';

    for (final dir in _targets) {
      try {
        await dir.create(recursive: true);
        await File(
          '${dir.path}/$fileName',
        ).writeAsString(encoded, mode: FileMode.append, flush: true);
      } catch (_) {
        // Deliberately silent: see the class doc.
      }
    }
  }

  /// Replaces secret values with a marker, keeping the fact that the field
  /// changed — which is the part worth auditing.
  static Map<String, Object?> redact(Map<String, Object?> detail) => {
    for (final entry in detail.entries)
      entry.key: _redacted.contains(entry.key) ? '<已隱藏>' : entry.value,
  };
}
