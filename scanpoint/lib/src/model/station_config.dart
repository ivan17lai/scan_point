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
    String? extraDir,
  }) => StationConfig(
    stationId: stationId ?? this.stationId,
    stationName: stationName ?? this.stationName,
    pin: pin ?? this.pin,
    uploadUrl: uploadUrl ?? this.uploadUrl,
    uploadToken: uploadToken ?? this.uploadToken,
    extraDir: extraDir ?? this.extraDir,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'station_id': stationId,
    'station_name': stationName,
    'pin': pin,
    'upload_url': uploadUrl,
    'upload_token': uploadToken,
    'extra_dir': extraDir,
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
      // `mirror_dir` was the key in the first draft, when the chosen folder
      // replaced the mirror instead of adding to it.
      extraDir:
          json['extra_dir'] as String? ?? json['mirror_dir'] as String? ?? '',
    );
  }
}
