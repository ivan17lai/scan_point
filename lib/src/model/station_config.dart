/// Station identity and operator settings.
///
/// Can be dropped next to the executable before the event (`station.json`) so a
/// machine arrives on site already configured, and can be edited on site from
/// the admin panel.
class StationConfig {
  const StationConfig({
    this.stationId = 'CP1',
    this.stationName = '未命名站點',
    this.pin = defaultPin,
    this.uploadUrl = '',
    this.uploadToken = '',
    this.mirrorDir = '',
    this.exportDir = '',
  });

  /// Where the redundant copy of the log is written. Empty means the default
  /// under the user's documents folder.
  ///
  /// Only the *mirror* is movable, never the primary. The primary has to be
  /// somewhere that is always mounted and always writable, because an
  /// unattended station that silently stops recording is the worst failure this
  /// system has. Point this at a USB stick and the log survives the machine;
  /// pull that stick out mid-event and scanning carries on against the primary
  /// with a warning on screen.
  final String mirrorDir;

  /// Where "匯出全部紀錄" writes. Empty means the default under documents.
  final String exportDir;

  /// Ships in public source, so it protects nothing on its own. The admin panel
  /// says so in as many words while it is still in use.
  static const String defaultPin = '246810';

  bool get isPinDefault => pin == defaultPin;

  final String stationId;
  final String stationName;

  /// Digits only — entry reads physical number keys, so any non-digit character
  /// here would be impossible to type at the PIN screen.
  final String pin;

  /// Manual upload target. Empty means the admin panel offers export only.
  final String uploadUrl;

  /// Sent as `Authorization: Bearer <token>` when non-empty.
  final String uploadToken;

  StationConfig copyWith({
    String? stationId,
    String? stationName,
    String? pin,
    String? uploadUrl,
    String? uploadToken,
    String? mirrorDir,
    String? exportDir,
  }) => StationConfig(
    stationId: stationId ?? this.stationId,
    stationName: stationName ?? this.stationName,
    pin: pin ?? this.pin,
    uploadUrl: uploadUrl ?? this.uploadUrl,
    uploadToken: uploadToken ?? this.uploadToken,
    mirrorDir: mirrorDir ?? this.mirrorDir,
    exportDir: exportDir ?? this.exportDir,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'station_id': stationId,
    'station_name': stationName,
    'pin': pin,
    'upload_url': uploadUrl,
    'upload_token': uploadToken,
    'mirror_dir': mirrorDir,
    'export_dir': exportDir,
  };

  static StationConfig fromJson(Map<String, dynamic> json) {
    final rawPin = (json['pin'] as String? ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return StationConfig(
      stationId: (json['station_id'] as String?)?.trim().isNotEmpty == true
          ? (json['station_id'] as String).trim()
          : 'CP1',
      stationName: (json['station_name'] as String?)?.trim().isNotEmpty == true
          ? (json['station_name'] as String).trim()
          : '未命名站點',
      pin: rawPin.length >= 4 ? rawPin : defaultPin,
      uploadUrl: json['upload_url'] as String? ?? '',
      uploadToken: json['upload_token'] as String? ?? '',
      mirrorDir: json['mirror_dir'] as String? ?? '',
      exportDir: json['export_dir'] as String? ?? '',
    );
  }
}
