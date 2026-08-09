import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../model/station_config.dart';

/// Loads and saves [StationConfig].
///
/// Read order lets a machine be provisioned before the event and still be
/// corrected on site:
///   1. `station.json` next to the executable — what you drop in before handing
///      the laptop to a marshal.
///   2. `Documents/OrienteeringSystem/station.json` — same idea, editable
///      without touching the install folder.
///   3. The app support copy — what the admin panel writes.
/// Later sources only fill in if the earlier ones are absent, so an on-site edit
/// (written to both 2 and 3) beats a stale pre-provisioned file only if the
/// operator removes the one beside the executable. That is deliberate: the file
/// you shipped with the machine wins unless you delete it.
class ConfigStore {
  ConfigStore._(this._appSupportFile, this._documentsFile, this.loadedFrom);

  final File _appSupportFile;
  final File _documentsFile;

  /// Path the active config came from, shown in the admin panel.
  final String loadedFrom;

  static const String _fileName = 'station.json';

  static Future<(ConfigStore, StationConfig)> open() async {
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();

    final appSupportFile = File('${support.path}/$_fileName');
    final documentsFile = File(
      '${documents.path}/OrienteeringSystem/$_fileName',
    );
    await documentsFile.parent.create(recursive: true);

    final beside = File(
      '${File(Platform.resolvedExecutable).parent.path}/$_fileName',
    );

    StationConfig? config;
    var source = '預設值(尚未設定)';
    for (final candidate in [beside, documentsFile, appSupportFile]) {
      final parsed = await _tryRead(candidate);
      if (parsed != null) {
        config = parsed;
        source = candidate.path;
        break;
      }
    }

    return (
      ConfigStore._(appSupportFile, documentsFile, source),
      config ?? const StationConfig(),
    );
  }

  static Future<StationConfig?> _tryRead(File file) async {
    try {
      if (!file.existsSync()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return StationConfig.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Writes to both the app support copy and the Documents copy so a reinstall
  /// does not lose the station identity.
  Future<void> save(StationConfig config) async {
    final text = const JsonEncoder.withIndent('  ').convert(config.toJson());
    for (final file in [_appSupportFile, _documentsFile]) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(text, flush: true);
      } catch (_) {
        // Best effort: one surviving copy is enough to restart configured.
      }
    }
  }
}
