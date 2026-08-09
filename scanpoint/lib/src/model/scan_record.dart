import '../scanner/scan_decoder.dart';

/// One line of the log. Written identically to the primary store, the mirror,
/// and the CSV so the three copies can be reconciled after the event.
class ScanRecord {
  const ScanRecord({
    required this.sequence,
    required this.cardId,
    required this.at,
    required this.stationId,
    required this.stationName,
    required this.terminator,
    required this.raw,
    this.duplicateOf,
  });

  final int sequence;
  final String cardId;
  final DateTime at;
  final String stationId;
  final String stationName;
  final FrameTerminator terminator;

  /// Exactly what came off the wire before normalisation, kept for diagnosing a
  /// misconfigured reader.
  final String raw;

  /// When this card was first seen at this station. Null for the first scan.
  final DateTime? duplicateOf;

  bool get isDuplicate => duplicateOf != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'seq': sequence,
    'card': cardId,
    'at_local': at.toIso8601String(),
    'at_utc': at.toUtc().toIso8601String(),
    'station_id': stationId,
    'station_name': stationName,
    'term': terminator.name,
    'raw': raw,
    if (duplicateOf != null) 'duplicate_of': duplicateOf!.toIso8601String(),
  };

  static ScanRecord fromJson(Map<String, dynamic> json) => ScanRecord(
    sequence: (json['seq'] as num?)?.toInt() ?? 0,
    cardId: json['card'] as String? ?? '',
    at: DateTime.tryParse(json['at_local'] as String? ?? '') ?? DateTime.now(),
    stationId: json['station_id'] as String? ?? '',
    stationName: json['station_name'] as String? ?? '',
    terminator: FrameTerminator.values.firstWhere(
      (t) => t.name == json['term'],
      orElse: () => FrameTerminator.questionMark,
    ),
    raw: json['raw'] as String? ?? '',
    duplicateOf: json['duplicate_of'] == null
        ? null
        : DateTime.tryParse(json['duplicate_of'] as String),
  );

  static const String csvHeader =
      'seq,card_id,at_local,at_utc,station_id,station_name,terminator,duplicate_of';

  String toCsvRow() {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    return [
      '$sequence',
      q(cardId),
      q(at.toIso8601String()),
      q(at.toUtc().toIso8601String()),
      q(stationId),
      q(stationName),
      terminator.name,
      q(duplicateOf?.toIso8601String() ?? ''),
    ].join(',');
  }
}
