import 'dart:math';

import 'apps_script_uploader.dart';
import 'upload_cursor.dart';

/// Reported after each confirmed batch, so a long upload is visibly moving.
class BatchUploadProgress {
  const BatchUploadProgress({
    required this.sentScans,
    required this.scansToSend,
    required this.sentOperations,
    required this.operationsToSend,
    required this.batches,
  });

  final int sentScans;
  final int scansToSend;
  final int sentOperations;
  final int operationsToSend;
  final int batches;
}

class BatchUploadResult {
  const BatchUploadResult({
    required this.ok,
    this.accepted = 0,
    this.duplicates = 0,
    this.sentScans = 0,
    this.sentOperations = 0,
    this.scansToSend = 0,
    this.operationsToSend = 0,
    this.batches = 0,
    this.statusCode = 0,
    this.error,
  });

  final bool ok;
  final int accepted;
  final int duplicates;

  /// Confirmed by the receiver during this run.
  final int sentScans;
  final int sentOperations;

  /// What was outstanding when the run started.
  final int scansToSend;
  final int operationsToSend;

  final int batches;
  final int statusCode;
  final String? error;

  /// The sheet already held everything this station has.
  bool get nothingToSend => scansToSend == 0 && operationsToSend == 0;

  /// A run that failed after some batches were confirmed and recorded.
  bool get isPartial => !ok && (sentScans > 0 || sentOperations > 0);
}

/// Sends only what the receiver has not confirmed, in bounded batches.
///
/// The station used to post its whole log — every scan and every operational
/// event — on every upload, and the receiver read its entire sheet back to
/// deduplicate. Both sides therefore did work proportional to the length of
/// the event on each attempt, so uploading got slower exactly as the event got
/// longer, until one request could no longer finish inside either the client
/// timeout or the Apps Script execution limit. And it failed whole: nothing
/// was durable, so the retry was the same losing request again, which is the
/// worst possible behaviour at the end of a long day.
///
/// Each request now carries a bounded slice, and the cursor advances only over
/// a slice the receiver confirmed. A failure halfway keeps everything before
/// it, and pressing upload again resumes instead of restarting.
class BatchUpload {
  const BatchUpload({
    required this.uploader,
    required this.cursors,
    this.batchSize = 2000,
    this.requestTimeout = const Duration(seconds: 60),
  });

  final AppsScriptUploader uploader;
  final UploadCursorStore cursors;

  /// Rows of each kind per request. The receiver rejects payloads above 50000,
  /// and a batch also has to fit comfortably inside one Apps Script execution.
  final int batchSize;

  final Duration requestTimeout;

  /// [scans] and [operations] are the complete logs, oldest entry first — the
  /// order they were written in, which is what the cursor counts against.
  Future<BatchUploadResult> run({
    required Uri endpoint,
    required String apiKey,
    required String spreadsheetId,
    required String stationId,
    required String stationName,
    required List<Map<String, dynamic>> scans,
    required List<Map<String, dynamic>> operations,
    void Function(BatchUploadProgress progress)? onProgress,
  }) async {
    final scanIds = _idsOf(scans, 'record_id');
    final operationIds = _idsOf(operations, 'event_id');

    var cursor = (await cursors.load()).forSpreadsheet(spreadsheetId);
    var scanAt = cursor.scanResumeAt(scanIds);
    var operationAt = cursor.operationResumeAt(operationIds);

    final scansToSend = scans.length - scanAt;
    final operationsToSend = operations.length - operationAt;
    var sentScans = 0;
    var sentOperations = 0;
    var accepted = 0;
    var duplicates = 0;
    var batches = 0;

    BatchUploadResult outcome({
      required bool ok,
      int statusCode = 0,
      String? error,
    }) => BatchUploadResult(
      ok: ok,
      accepted: accepted,
      duplicates: duplicates,
      sentScans: sentScans,
      sentOperations: sentOperations,
      scansToSend: scansToSend,
      operationsToSend: operationsToSend,
      batches: batches,
      statusCode: statusCode,
      error: error,
    );

    // The station reports its own totals so the receiver's per-station summary
    // still describes the station rather than whichever slice arrived last.
    final stationTotals = <String, Object?>{
      'scans': scans.length,
      'duplicate_scans': scans
          .where((record) => _isNotBlank(record['duplicate_of']))
          .length,
      'operations': operations.length,
    };

    while (scanAt < scans.length || operationAt < operations.length) {
      final scanEnd = min(scans.length, scanAt + batchSize);
      final operationEnd = min(operations.length, operationAt + batchSize);
      batches++;

      final AppsScriptUploadResult result;
      try {
        final now = DateTime.now();
        result = await uploader
            .upload(
              endpoint: endpoint,
              payload: <String, Object?>{
                'schema_version': 1,
                'api_key': apiKey,
                'spreadsheet_id': spreadsheetId,
                'batch_id':
                    '$stationId-${now.toUtc().microsecondsSinceEpoch}-$batches',
                'station_id': stationId,
                'station_name': stationName,
                'uploaded_at': now.toIso8601String(),
                'station_totals': stationTotals,
                'scans': scans.sublist(scanAt, scanEnd),
                'operations': operations.sublist(operationAt, operationEnd),
              },
            )
            .timeout(requestTimeout);
      } catch (e) {
        return outcome(ok: false, error: '$e');
      }

      if (!result.ok) {
        return outcome(
          ok: false,
          statusCode: result.statusCode,
          error: result.error,
        );
      }

      accepted += result.accepted;
      duplicates += result.duplicates;
      sentScans += scanEnd - scanAt;
      sentOperations += operationEnd - operationAt;
      scanAt = scanEnd;
      operationAt = operationEnd;

      // Saved per batch, not once at the end: the point of the slice is that
      // what it delivered survives whatever happens to the next one.
      cursor = cursor.advanced(
        scanIds: scanIds,
        scanCount: scanAt,
        operationIds: operationIds,
        operationCount: operationAt,
      );
      await cursors.save(cursor);

      onProgress?.call(
        BatchUploadProgress(
          sentScans: sentScans,
          scansToSend: scansToSend,
          sentOperations: sentOperations,
          operationsToSend: operationsToSend,
          batches: batches,
        ),
      );
    }

    return outcome(ok: true);
  }

  static List<String> _idsOf(List<Map<String, dynamic>> entries, String key) =>
      entries
          .map((entry) => entry[key]?.toString() ?? '')
          .toList(growable: false);

  static bool _isNotBlank(Object? value) =>
      value != null && value.toString().trim().isNotEmpty;
}
