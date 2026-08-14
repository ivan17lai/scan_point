import 'dart:convert';
import 'dart:io';

/// How much of each append-only log the receiving spreadsheet has confirmed.
///
/// Both logs only ever grow, so "the first N entries are already up there" is
/// enough to resume from — provided the log is still the one the count was
/// taken from. The id sitting at the boundary is kept for exactly that check.
class UploadCursor {
  const UploadCursor({
    this.spreadsheetId = '',
    this.scans = 0,
    this.lastScanId = '',
    this.operations = 0,
    this.lastOperationId = '',
  });

  /// Nothing confirmed yet — also what an unreadable or absent file means.
  static const UploadCursor none = UploadCursor();

  final String spreadsheetId;
  final int scans;
  final String lastScanId;
  final int operations;
  final String lastOperationId;

  /// Where to resume in [ids], given [uploaded] entries were confirmed and
  /// [lastId] was the id at that boundary.
  ///
  /// Returns 0 — resend everything — whenever the log no longer looks like the
  /// one the count came from: shorter than the count, or carrying a different
  /// id at the boundary. That is what a log restored from a backup or rebuilt
  /// after a disk problem looks like, and the two mistakes available here are
  /// not equal. Re-sending costs bandwidth, and the receiver drops what it
  /// already holds. Skipping costs someone their result. So anything
  /// unexpected starts again.
  static int resumeAt(List<String> ids, int uploaded, String lastId) {
    if (uploaded <= 0 || uploaded > ids.length) return 0;
    if (lastId.isEmpty || ids[uploaded - 1] != lastId) return 0;
    return uploaded;
  }

  int scanResumeAt(List<String> ids) => resumeAt(ids, scans, lastScanId);

  int operationResumeAt(List<String> ids) =>
      resumeAt(ids, operations, lastOperationId);

  /// A cursor recorded against a different spreadsheet describes rows this one
  /// does not have, so it is discarded rather than trusted. Repointing a
  /// station at a fresh sheet has to upload the whole event into it.
  UploadCursor forSpreadsheet(String id) =>
      id == spreadsheetId ? this : UploadCursor(spreadsheetId: id);

  UploadCursor advanced({
    required List<String> scanIds,
    required int scanCount,
    required List<String> operationIds,
    required int operationCount,
  }) => UploadCursor(
    spreadsheetId: spreadsheetId,
    scans: scanCount,
    lastScanId: scanCount > 0 ? scanIds[scanCount - 1] : '',
    operations: operationCount,
    lastOperationId: operationCount > 0 ? operationIds[operationCount - 1] : '',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': 1,
    'spreadsheet_id': spreadsheetId,
    'scans': scans,
    'last_scan_id': lastScanId,
    'operations': operations,
    'last_operation_id': lastOperationId,
  };

  static UploadCursor fromJson(Map<String, dynamic> json) => UploadCursor(
    spreadsheetId: json['spreadsheet_id'] as String? ?? '',
    scans: (json['scans'] as num?)?.toInt() ?? 0,
    lastScanId: json['last_scan_id'] as String? ?? '',
    operations: (json['operations'] as num?)?.toInt() ?? 0,
    lastOperationId: json['last_operation_id'] as String? ?? '',
  );
}

/// Keeps the cursor beside the log it describes.
///
/// Nothing here throws. Losing this file costs one redundant full upload,
/// which the receiver deduplicates anyway; refusing to upload because the
/// bookkeeping could not be read would trade that for the thing uploading
/// exists to prevent.
class UploadCursorStore {
  const UploadCursorStore(this.file);

  static const String fileName = 'upload-cursor.json';

  final File file;

  Future<UploadCursor> load() async {
    try {
      if (!file.existsSync()) return UploadCursor.none;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return UploadCursor.none;
      return UploadCursor.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return UploadCursor.none;
    }
  }

  /// Returns null on success, otherwise a message for the operational log.
  ///
  /// A failure here is not an upload failure: the batch it describes did reach
  /// the sheet. It only means the next attempt re-sends that batch.
  Future<String?> save(UploadCursor cursor) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString('${jsonEncode(cursor.toJson())}\n', flush: true);
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
