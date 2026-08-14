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

    test('rejects the characters the scoring page splits a station order on', () {
      // Each of these would be torn into two station ids by the scoring page's
      // order field, leaving every runner short of a checkpoint nobody visited.
      for (final id in ['CP1,CP2', 'CP1，CP2', 'CP1;CP2', 'CP1；CP2',
                        'CP1>CP2', 'CP1→CP2', 'CP1\nCP2']) {
        expect(
          StationSetupValidator.validateStationId(id),
          isNotNull,
          reason: '$id 應該被拒絕',
        );
      }
    });

    test('rejects characters a backup folder name cannot carry', () {
      // ScanStore.safeName folds these to `_`, so two different ids would
      // silently share one folder on the stick.
      for (final id in ['CP/1', r'CP\1', 'CP:1', 'CP*1', 'CP?1', 'CP|1']) {
        expect(
          StationSetupValidator.validateStationId(id),
          isNotNull,
          reason: '$id 應該被拒絕',
        );
      }
    });

    test('accepts the ids stations actually use', () {
      for (final id in ['CP1', 'CP01', 'cp-1', 'CP_1', 'start.a', 'A', '1']) {
        expect(
          StationSetupValidator.validateStationId(id),
          isNull,
          reason: '$id 應該被接受',
        );
      }
      expect(StationSetupValidator.validateStationId(' CP1 '), isNull);
    });

    test('rejects an over-long station id', () {
      expect(StationSetupValidator.validateStationId('C' * 32), isNull);
      expect(StationSetupValidator.validateStationId('C' * 33), isNotNull);
    });

    test('a rejected station id is reported before the name is looked at', () {
      expect(
        StationSetupValidator.validateIdentity(
          stationId: 'CP1,CP2',
          stationName: '未命名站點',
        ),
        contains('站點編號'),
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
