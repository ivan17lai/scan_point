class StationSetupValidator {
  const StationSetupValidator._();

  static String? validateIdentity({
    required String stationId,
    required String stationName,
  }) {
    if (stationId.trim().isEmpty) return '請輸入站點編號';
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
