import 'dart:convert';

import 'package:http/http.dart' as http;

class AppsScriptUploadResult {
  const AppsScriptUploadResult({
    required this.ok,
    required this.statusCode,
    this.accepted = 0,
    this.duplicates = 0,
    this.error,
  });

  final bool ok;
  final int statusCode;
  final int accepted;
  final int duplicates;
  final String? error;
}

/// Sends one upload and follows only Apps Script ContentService redirects.
class AppsScriptUploader {
  AppsScriptUploader(http.Client client) : _client = client;

  final http.Client _client;

  Future<AppsScriptUploadResult> upload({
    required Uri endpoint,
    required Map<String, Object?> payload,
  }) async {
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      })
      ..body = jsonEncode(payload);

    var response = await http.Response.fromStream(await _client.send(request));
    if (_isRedirect(response.statusCode)) {
      final location = response.headers['location'];
      final redirect = location == null ? null : endpoint.resolve(location);
      if (redirect == null || !_isGoogleContentHost(redirect.host)) {
        return AppsScriptUploadResult(
          ok: false,
          statusCode: response.statusCode,
          error: '未預期的重新導向',
        );
      }
      response = await _client.get(
        redirect,
        headers: const {'Accept': 'application/json'},
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return AppsScriptUploadResult(
        ok: false,
        statusCode: response.statusCode,
        error: 'HTTP ${response.statusCode}',
      );
    }

    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map) {
        throw const FormatException('Response is not an object');
      }
      final json = body.cast<String, dynamic>();
      return AppsScriptUploadResult(
        ok: json['ok'] == true,
        statusCode: response.statusCode,
        accepted: (json['accepted'] as num?)?.toInt() ?? 0,
        duplicates: (json['duplicates'] as num?)?.toInt() ?? 0,
        error: json['ok'] == true ? null : json['error']?.toString() ?? '上傳被拒絕',
      );
    } on FormatException {
      return AppsScriptUploadResult(
        ok: false,
        statusCode: response.statusCode,
        error: '伺服器回傳格式不正確',
      );
    }
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  static bool _isGoogleContentHost(String host) =>
      host == 'script.googleusercontent.com' ||
      host.endsWith('.script.googleusercontent.com');
}
