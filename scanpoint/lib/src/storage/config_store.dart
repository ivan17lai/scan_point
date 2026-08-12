import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/station_config.dart';

/// Loads and saves local station settings and remote-upload settings.
///
/// Both files use the same read priority:
///   1. Next to the executable.
///   2. `Documents/OrienteeringSystem`.
///   3. The app support directory.
///
/// `station.json` contains only station identity and local behavior.
/// `cloud.config` is the sole source for `SPREADSHEET_ID`, `UPLOAD_URL`, and
/// `UPLOAD_KEY`.
class ConfigStore {
  ConfigStore._(
    this._besideFile,
    this._appSupportFile,
    this._documentsFile,
    this._cloudFiles,
    this.loadedFrom,
  );

  final File _besideFile;
  final File _appSupportFile;
  final File _documentsFile;
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

    StationConfig? config;
    StationConfig? packagedPlaceholder;
    String? packagedPlaceholderSource;
    var stationSource = '預設值(尚未設定)';
    for (final candidate in [beside, documentsFile, appSupportFile]) {
      final parsed = await _tryReadStation(candidate);
      if (parsed == null) continue;
      if (parsed.needsStationSetup) {
        packagedPlaceholder ??= parsed;
        packagedPlaceholderSource ??= candidate.path;
        continue;
      }
      config = parsed;
      stationSource = candidate.path;
      break;
    }
    if (config == null && packagedPlaceholder != null) {
      config = packagedPlaceholder;
      stationSource = packagedPlaceholderSource!;
    }

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
      ConfigStore._(
        beside,
        appSupportFile,
        documentsFile,
        cloudFiles,
        '站點：$stationSource；雲端：$cloudSource',
      ),
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
    await writeStationCopies(config, [
      _besideFile,
      _appSupportFile,
      _documentsFile,
    ]);

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
  static Future<void> writeStationCopies(
    StationConfig config,
    Iterable<File> files,
  ) async {
    final stationText = const JsonEncoder.withIndent(
      '  ',
    ).convert(config.toJson());
    for (final file in files) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(stationText, flush: true);
      } catch (_) {
        // Best effort: one surviving copy is enough to restart configured.
      }
    }
  }

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]'), '').trim();
}
