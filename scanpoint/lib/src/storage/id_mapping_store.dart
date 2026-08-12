import 'dart:io';

import '../model/id_mapping.dart';

/// Owns the canonical display mapping beside `scan_point.exe`.
class IdMappingStore {
  IdMappingStore._(this.file, this.mapping, this.loadWarning);

  static const String fileName = 'id-mapping.json';

  final File file;
  IdMapping mapping;
  String? loadWarning;

  int get count => mapping.length;
  String? labelFor(String id) => mapping.labelFor(id);

  static Future<IdMappingStore> open({File? overrideFile}) async {
    final file =
        overrideFile ??
        File('${File(Platform.resolvedExecutable).parent.path}/$fileName');
    if (!file.existsSync()) {
      return IdMappingStore._(file, IdMapping.empty, null);
    }
    try {
      final mapping = IdMapping.parse(
        await file.readAsString(),
        fileName: file.path,
      );
      return IdMappingStore._(file, mapping, null);
    } on Object catch (error) {
      return IdMappingStore._(file, IdMapping.empty, '對照表無法讀取：$error');
    }
  }

  Future<IdMapping> import(File source) async {
    final next = IdMapping.parse(
      await source.readAsString(),
      fileName: source.path,
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(next.encode(), flush: true);
    mapping = next;
    loadWarning = null;
    return next;
  }

  Future<void> clear() async {
    if (file.existsSync()) await file.delete();
    mapping = IdMapping.empty;
    loadWarning = null;
  }
}
