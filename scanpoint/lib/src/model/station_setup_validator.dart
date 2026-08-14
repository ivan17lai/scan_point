class StationSetupValidator {
  const StationSetupValidator._();

  /// A station id is not free text — it is carried by three things that each
  /// constrain it, and none of them complain when it is wrong.
  ///
  /// It becomes a folder name on the backup stick, where `ScanStore.safeName`
  /// folds anything the filesystem rejects into `_`, so `CP/1` and `CP_1` would
  /// quietly share one folder. It is written into a CSV column. And it is typed
  /// back into the scoring page's station-order field, which splits on
  /// `, ， ; ； > →` and newlines — an id carrying any of those is torn into two
  /// stations that nobody ever visits, and every runner is scored as unfinished.
  ///
  /// So the character set is settled here, at the one moment the operator is
  /// looking at a screen and can still fix it, rather than after the event.
  /// The display name is where free text belongs and stays unrestricted.
  static final RegExp _stationIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,32}$');

  static String? validateStationId(String stationId) {
    final id = stationId.trim();
    if (id.isEmpty) return '請輸入站點編號';
    if (!_stationIdPattern.hasMatch(id)) {
      return '站點編號只能使用英文字母、數字、句點、底線與連字號,最多 32 字';
    }
    return null;
  }

  static String? validateIdentity({
    required String stationId,
    required String stationName,
  }) {
    final idError = validateStationId(stationId);
    if (idError != null) return idError;
    final name = stationName.trim();
    if (name.isEmpty || name == '未命名站點') return '請輸入實際站點名稱';
    return null;
  }

  static String? validatePin(String pin) {
    if (pin.length < 4 || !RegExp(r'^\d+$').hasMatch(pin)) {
      return '管理 PIN 至少要 4 位數字';
    }
    return null;
  }

  static String? validateConfirmation(String pin, String confirmation) {
    return pin == confirmation ? null : '兩次輸入的管理 PIN 不一致';
  }
}
