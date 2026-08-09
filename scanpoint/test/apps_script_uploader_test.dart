import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scan_point/src/upload/apps_script_uploader.dart';

void main() {
  test(
    'posts the Code.gs schema and follows the Google content redirect',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://script.googleusercontent.com/macros/echo?key=one-time',
            },
          );
        }
        return http.Response(
          jsonEncode({'ok': true, 'accepted': 7, 'duplicates': 2}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await AppsScriptUploader(client).upload(
        endpoint: Uri.parse(
          'https://script.google.com/macros/s/deployment/exec',
        ),
        payload: {
          'schema_version': 1,
          'api_key': 'secret',
          'scans': <Object?>[],
          'operations': <Object?>[],
        },
      );

      expect(result.ok, isTrue);
      expect(result.accepted, 7);
      expect(result.duplicates, 2);
      expect(requests.map((request) => request.method), ['POST', 'GET']);
      expect(requests.last.url.host, 'script.googleusercontent.com');
      final payload = jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(payload['api_key'], 'secret');
      expect(payload, containsPair('schema_version', 1));
    },
  );

  test('does not follow a redirect to an unrelated host', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'https://accounts.google.com/login'},
      );
    });

    final result = await AppsScriptUploader(client).upload(
      endpoint: Uri.parse('https://script.google.com/macros/s/deployment/exec'),
      payload: const {},
    );

    expect(result.ok, isFalse);
    expect(result.statusCode, 302);
    expect(result.error, '未預期的重新導向');
    expect(calls, 1);
  });

  test('surfaces an Apps Script JSON error', () async {
    final client = MockClient(
      (_) async => http.Response('{"ok":false,"error":"Unauthorized"}', 200),
    );

    final result = await AppsScriptUploader(client).upload(
      endpoint: Uri.parse('https://script.google.com/macros/s/deployment/exec'),
      payload: const {},
    );

    expect(result.ok, isFalse);
    expect(result.error, 'Unauthorized');
  });
}
