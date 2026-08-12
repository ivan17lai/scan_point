import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/model/station_config.dart';
import 'package:scan_point/src/storage/config_store.dart';

void main() {
  test('cloud.config round-trips spreadsheet id, url, and key', () {
    const config = StationConfig(
      spreadsheetId: 'spreadsheet-id-1234567890',
      uploadUrl: 'https://script.google.com/macros/s/deployment/exec',
      uploadToken: 'upload-key-1234567890',
    );

    final encoded = ConfigStore.encodeCloudConfig(config);
    final decoded = ConfigStore.parseCloudConfig(encoded);

    expect(decoded, config.cloudSettings);
    expect(encoded, isNot(contains('station_id')));
  });

  test('cloud.config ignores comments and unknown keys', () {
    final decoded = ConfigStore.parseCloudConfig('''
# Comment
spreadsheet_id = sheet-12345678901234567890
UNKNOWN=value
UPLOAD_URL=https://script.google.com/macros/s/deployment/exec
UPLOAD_KEY=key=value
''');

    expect(decoded, <String, String>{
      'SPREADSHEET_ID': 'sheet-12345678901234567890',
      'UPLOAD_URL': 'https://script.google.com/macros/s/deployment/exec',
      'UPLOAD_KEY': 'key=value',
    });
  });

  test('station settings are written to every requested copy', () async {
    final temp = await Directory.systemTemp.createTemp('scanpoint-config-');
    addTearDown(() => temp.delete(recursive: true));
    final beside = File('${temp.path}/portable/station.json');
    final support = File('${temp.path}/support/station.json');

    const config = StationConfig(stationId: 'CP1', stationName: '水源地');
    await ConfigStore.writeStationCopies(config, [beside, support]);

    for (final file in [beside, support]) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(json['station_id'], 'CP1');
      expect(json['station_name'], '水源地');
    }
  });
}
