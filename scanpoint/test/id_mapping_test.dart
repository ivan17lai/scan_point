import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/model/id_mapping.dart';
import 'package:scan_point/src/storage/id_mapping_store.dart';

void main() {
  group('IdMapping', () {
    test('parses UTF-8 CSV without losing leading zeroes or quoted text', () {
      final mapping = IdMapping.parse(
        '\ufeffid,text\r\n00123,"第一組, 王小明"\r\nABC,救護組\r\n',
        fileName: 'runners.csv',
      );

      expect(mapping.length, 2);
      expect(mapping.labelFor('00123'), '第一組, 王小明');
      expect(mapping.labelFor('ABC'), '救護組');
      expect(mapping.labelFor('missing'), isNull);
    });

    test('parses canonical JSON and simple object maps', () {
      final canonical = IdMapping.parse('''
{
  "format": "scanpoint-id-mapping",
  "schema_version": 1,
  "entries": [
    {"id": "A01", "text": "選手 A"}
  ]
}
''');
      final simple = IdMapping.parse('{"B02":"選手 B"}');

      expect(canonical.labelFor('A01'), '選手 A');
      expect(simple.labelFor('B02'), '選手 B');
      expect(IdMapping.parse(canonical.encode()).toJson(), canonical.toJson());
    });

    test('rejects missing headers, empty cells, and duplicate IDs', () {
      expect(
        () => IdMapping.parse('bib,team\nA01,A'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => IdMapping.parse('id,text\nA01,'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => IdMapping.parse('id,text\nA01,A\nA01,B'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test(
    'IdMappingStore imports, reloads, and clears the EXE-side file',
    () async {
      final temp = await Directory.systemTemp.createTemp('scanpoint-id-map-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = File('${temp.path}/source.csv')
        ..writeAsStringSync('id,text\n0007,第七棒\n');
      final target = File('${temp.path}/id-mapping.json');

      final store = await IdMappingStore.open(overrideFile: target);
      expect(store.count, 0);
      expect(await store.import(source), isA<IdMapping>());
      expect(store.labelFor('0007'), '第七棒');
      expect(target.readAsStringSync(), contains('scanpoint-id-mapping'));

      final reopened = await IdMappingStore.open(overrideFile: target);
      expect(reopened.labelFor('0007'), '第七棒');
      await reopened.clear();
      expect(reopened.count, 0);
      expect(target.existsSync(), isFalse);
    },
  );
}
