import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/model/station_setup_validator.dart';

void main() {
  group('station identity', () {
    test('requires a station id and a real name', () {
      expect(
        StationSetupValidator.validateIdentity(
          stationId: ' ',
          stationName: '水源地',
        ),
        '請輸入站點編號',
      );
      expect(
        StationSetupValidator.validateIdentity(
          stationId: 'CP1',
          stationName: '未命名站點',
        ),
        '請輸入實際站點名稱',
      );
      expect(
        StationSetupValidator.validateIdentity(
          stationId: ' CP1 ',
          stationName: ' 水源地 ',
        ),
        isNull,
      );
    });
  });

  group('management PIN', () {
    test('requires at least four ASCII digits', () {
      expect(StationSetupValidator.validatePin('123'), isNotNull);
      expect(StationSetupValidator.validatePin('12A4'), isNotNull);
      expect(StationSetupValidator.validatePin('１２３４'), isNotNull);
      expect(StationSetupValidator.validatePin('1234'), isNull);
      expect(StationSetupValidator.validatePin('246810'), isNull);
    });

    test('requires matching confirmation', () {
      expect(
        StationSetupValidator.validateConfirmation('246810', '246811'),
        '兩次輸入的管理 PIN 不一致',
      );
      expect(
        StationSetupValidator.validateConfirmation('246810', '246810'),
        isNull,
      );
    });
  });
}
