import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/model/station_config.dart';

void main() {
  test('station.json never contains remote-upload settings', () {
    const config = StationConfig(
      spreadsheetId: 'spreadsheet-id-1234567890',
      uploadUrl: 'https://script.google.com/macros/s/deployment/exec',
      uploadToken: 'secret-value',
    );

    expect(config.toJson(), isNot(contains('spreadsheet_id')));
    expect(config.toJson(), isNot(contains('upload_url')));
    expect(config.toJson(), isNot(contains('upload_token')));
    expect(config.cloudSettings, <String, String>{
      'SPREADSHEET_ID': 'spreadsheet-id-1234567890',
      'UPLOAD_URL': 'https://script.google.com/macros/s/deployment/exec',
      'UPLOAD_KEY': 'secret-value',
    });
  });

  test('legacy remote fields in station.json are ignored', () {
    final config = StationConfig.fromJson(<String, dynamic>{
      'station_id': 'CP9',
      'station_name': '九號站',
      'pin': '1234',
      'spreadsheet_id': 'legacy-sheet',
      'upload_url': 'https://example.test/exec',
      'upload_token': 'legacy-secret',
    });

    expect(config.spreadsheetId, isEmpty);
    expect(config.uploadUrl, isEmpty);
    expect(config.uploadToken, isEmpty);
  });

  test('cloud config is complete only when all three values exist', () {
    expect(const StationConfig().hasCompleteCloudConfig, isFalse);
    expect(
      const StationConfig(
        spreadsheetId: 'sheet',
        uploadUrl: 'url',
        uploadToken: 'key',
      ).hasCompleteCloudConfig,
      isTrue,
    );
  });

  test('only the complete packaged placeholder needs station setup', () {
    expect(const StationConfig().needsStationSetup, isTrue);
    expect(
      const StationConfig(
        stationId: 'CP1',
        stationName: '水源地',
      ).needsStationSetup,
      isFalse,
    );
    expect(const StationConfig(stationId: 'CP2').needsStationSetup, isFalse);
  });
}
