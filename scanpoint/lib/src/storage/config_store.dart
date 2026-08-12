import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/station_config.dart';

/// Loads and saves local station settings and remote-upload settings.
///
/// `station.json` is trusted only next to the executable. Old copies in
/// Documents or AppData must never change the identity of a newly extracted
/// station package.
///
/// `station.json` contains only station identity and local behavior.
/// `cloud.config` is the sole source for `SPREADSHEET_ID`, `UPLOAD_URL`, and
/// `UPLOAD_KEY`; it keeps the existing portable/Documents/AppData fallback.
class ConfigStore {
  ConfigStore._(this._besideFile, this._cloudFiles, this.loadedFrom);

  final File _besideFile;
  final List<File> _cloudFiles;

  /// Paths the active station and cloud settings came from.
  final String loadedFrom;

  static const String _stationFileName = 'station.json';
  static const String _cloudFileName = 'cloud.config';

  static Future<(ConfigStore, StationConfig)> open() async {
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();

    final appSupportFile = File('${support.path}/$_stationFileName');
    final documentsFile = File(
      '${documents.path}/OrienteeringSystem/$_stationFileName',
    );
    await documentsFile.parent.create(recursive: true);

    final beside = File(
      '${File(Platform.resolvedExecutable).parent.path}/$_stationFileName',
    );
    final cloudFiles = <File>[
      File('${beside.parent.path}/$_cloudFileName'),
      File('${documentsFile.parent.path}/$_cloudFileName'),
      File('${appSupportFile.parent.path}/$_cloudFileName'),
    ];

    final config = await _tryReadStation(beside);
    final stationSource = config == null ? '預設值(尚未設定)' : beside.path;

    var cloudSource = '未設定';
    var cloudSettings = const <String, String>{};
    for (final cloudFile in cloudFiles) {
      final result = await _tryReadCloud(cloudFile);
      if (result.$1) {
        cloudSource = cloudFile.path;
        cloudSettings = result.$2;
        break;
      }
    }

    final loaded = (config ?? const StationConfig()).copyWith(
      spreadsheetId: cloudSettings['SPREADSHEET_ID'] ?? '',
      uploadUrl: cloudSettings['UPLOAD_URL'] ?? '',
      uploadToken: cloudSettings['UPLOAD_KEY'] ?? '',
    );
    return (
      ConfigStore._(beside, cloudFiles, '站點：$stationSource；雲端：$cloudSource'),
      loaded,
    );
  }

  static Future<StationConfig?> _tryReadStation(File file) async {
    try {
      if (!file.existsSync()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return StationConfig.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<(bool, Map<String, String>)> _tryReadCloud(File file) async {
    try {
      if (!file.existsSync()) return (false, const <String, String>{});
      return (true, parseCloudConfig(await file.readAsString()));
    } catch (_) {
      return (false, const <String, String>{});
    }
  }

  static Map<String, String> parseCloudConfig(String text) {
    final values = <String, String>{};
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim().toUpperCase();
      if (!const {'SPREADSHEET_ID', 'UPLOAD_URL', 'UPLOAD_KEY'}.contains(key)) {
        continue;
      }
      values[key] = line.substring(separator + 1).trim();
    }
    return Map<String, String>.unmodifiable(values);
  }

  static String encodeCloudConfig(StationConfig config) => <String>[
    '# ScanPoint remote upload configuration',
    for (final entry in config.cloudSettings.entries)
      '${entry.key}=${_singleLine(entry.value)}',
    '',
  ].join('\n');

  /// Writes local settings and cloud settings to separate files.
  Future<void> save(StationConfig config) async {
    await writeStationFile(config, _besideFile);

    final cloudText = encodeCloudConfig(config);
    for (final file in _cloudFiles) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(cloudText, flush: true);
      } catch (_) {
        // The executable directory can be read-only; writable copies remain.
      }
    }
  }

  @visibleForTesting
  static Future<void> writeStationFile(StationConfig config, File file) async {
    final stationText = const JsonEncoder.withIndent(
      '  ',
    ).convert(config.toJson());
    await file.parent.create(recursive: true);
    await file.writeAsString(stationText, flush: true);
  }

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]'), '').trim();
}
