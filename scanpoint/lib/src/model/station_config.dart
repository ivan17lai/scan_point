/// Station identity, operator settings, and loaded cloud settings.
///
/// Local station values can be dropped next to the executable in
/// `station.json`. Remote-upload values are loaded only from `cloud.config`.
class StationConfig {
  const StationConfig({
    this.stationId = 'CP1',
    this.stationName = '未命名站點',
    this.pin = defaultPin,
    this.spreadsheetId = '',
    this.uploadUrl = '',
    this.uploadToken = '',
    this.extraDir = '',
  });

  /// An additional folder to copy the log into — typically a USB stick. Empty
  /// means no extra copy.
  ///
  /// Additive, never a redirect: the two default copies are written exactly as
  /// before, so unplugging the stick leaves the machine no worse off than
  /// before it was plugged in. Nothing may redirect the primary — an unattended
  /// station that silently stops recording is the worst failure this system
  /// has, so its destination must always be mounted and always writable.
  final String extraDir;

  /// Ships in public source, so it protects nothing on its own. The admin panel
  /// says so in as many words while it is still in use.
  static const String defaultPin = '246810';

  bool get isPinDefault => pin == defaultPin;

  /// The complete package ships with these two placeholder values. Seeing the
  /// pair together means the operator has not yet identified this station.
  bool get needsStationSetup =>
      stationId.trim() == 'CP1' && stationName.trim() == '未命名站點';

  final String stationId;
  final String stationName;

  /// Digits only — entry reads physical number keys, so any non-digit character
  /// here would be impossible to type at the PIN screen.
  final String pin;

  /// Google spreadsheet identity stored in `cloud.config`.
  final String spreadsheetId;

  /// Apps Script `/exec` endpoint stored in `cloud.config`.
  final String uploadUrl;

  /// Sent as `Authorization: Bearer <token>`. Stored only in `cloud.config`.
  final String uploadToken;

  bool get hasCompleteCloudConfig =>
      spreadsheetId.trim().isNotEmpty &&
      uploadUrl.trim().isNotEmpty &&
      uploadToken.trim().isNotEmpty;

  StationConfig copyWith({
    String? stationId,
    String? stationName,
    String? pin,
    String? spreadsheetId,
    String? uploadUrl,
    String? uploadToken,
    String? extraDir,
  }) => StationConfig(
    stationId: stationId ?? this.stationId,
    stationName: stationName ?? this.stationName,
    pin: pin ?? this.pin,
    spreadsheetId: spreadsheetId ?? this.spreadsheetId,
    uploadUrl: uploadUrl ?? this.uploadUrl,
    uploadToken: uploadToken ?? this.uploadToken,
    extraDir: extraDir ?? this.extraDir,
  );

  /// Values allowed in `station.json`. No remote-upload setting belongs here.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'station_id': stationId,
    'station_name': stationName,
    'pin': pin,
    'extra_dir': extraDir,
  };

  /// Values written to `cloud.config` and used to audit config changes.
  Map<String, String> get cloudSettings => <String, String>{
    'SPREADSHEET_ID': spreadsheetId,
    'UPLOAD_URL': uploadUrl,
    'UPLOAD_KEY': uploadToken,
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
      // Remote-upload values deliberately never come from station.json.
      spreadsheetId: '',
      uploadUrl: '',
      uploadToken: '',
      // `mirror_dir` was the key in the first draft, when the chosen folder
      // replaced the mirror instead of adding to it.
      extraDir:
          json['extra_dir'] as String? ?? json['mirror_dir'] as String? ?? '',
    );
  }
}
