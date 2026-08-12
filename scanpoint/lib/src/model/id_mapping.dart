import 'dart:convert';

/// A display-only lookup table for scanned card IDs.
///
/// Scan records always keep the original ID. This table is deliberately kept
/// outside [ScanRecord] so changing a label cannot change duplicate detection,
/// exports, uploads, or scoring.
class IdMapping {
  const IdMapping._(this.entries);

  static const empty = IdMapping._(<String, String>{});
  static const int maxEntries = 10000;
  static const int maxIdLength = 256;
  static const int maxTextLength = 120;

  final Map<String, String> entries;

  int get length => entries.length;
  bool get isEmpty => entries.isEmpty;

  String? labelFor(String id) => entries[id.trim()];

  static IdMapping parse(String source, {String fileName = ''}) {
    if (source.length > 2 * 1024 * 1024) {
      throw const FormatException('對照表檔案不可超過 2 MB');
    }
    final text = source.replaceFirst('\ufeff', '').trim();
    if (text.isEmpty) throw const FormatException('對照表是空的');

    final looksLikeJson =
        fileName.toLowerCase().endsWith('.json') ||
        text.startsWith('{') ||
        text.startsWith('[');
    final rows = looksLikeJson ? _parseJson(text) : _parseTable(text);
    return IdMapping._(Map<String, String>.unmodifiable(_validate(rows)));
  }

  Map<String, Object> toJson() => <String, Object>{
    'format': 'scanpoint-id-mapping',
    'schema_version': 1,
    'entries': [
      for (final entry in entries.entries)
        <String, String>{'id': entry.key, 'text': entry.value},
    ],
  };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  static List<(Object?, Object?)> _parseJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded.map(_jsonEntry).toList(growable: false);
    }
    if (decoded is! Map) {
      throw const FormatException('JSON 對照表必須是物件或陣列');
    }

    final rawEntries = decoded['entries'];
    if (rawEntries is List) {
      return rawEntries.map(_jsonEntry).toList(growable: false);
    }

    final metadataKeys = <Object?>{'format', 'schema_version'};
    return [
      for (final entry in decoded.entries)
        if (!metadataKeys.contains(entry.key)) (entry.key, entry.value),
    ];
  }

  static (Object?, Object?) _jsonEntry(Object? value) {
    if (value is! Map) {
      throw const FormatException('JSON 每筆對照必須包含 id 與 text');
    }
    return (
      value['id'] ?? value['card_id'] ?? value['card'] ?? value['uid'],
      value['text'] ?? value['label'] ?? value['name'] ?? value['display_text'],
    );
  }

  static List<(Object?, Object?)> _parseTable(String text) {
    final delimiter = _firstRecord(text).contains('\t') ? '\t' : ',';
    final records = _parseDelimited(text, delimiter);
    if (records.isEmpty) throw const FormatException('對照表是空的');

    final header = records.first.map(_headerKey).toList(growable: false);
    final idIndex = header.indexWhere(
      (value) => const {'id', 'card_id', 'card', 'uid'}.contains(value),
    );
    final textIndex = header.indexWhere(
      (value) => const {
        'text',
        'label',
        'name',
        'display_text',
        '顯示文字',
        '名稱',
      }.contains(value),
    );
    if (idIndex < 0 || textIndex < 0) {
      throw const FormatException('第一列標題必須包含 id 與 text');
    }

    final result = <(Object?, Object?)>[];
    for (final record in records.skip(1)) {
      if (record.every((cell) => cell.trim().isEmpty)) continue;
      result.add((
        idIndex < record.length ? record[idIndex] : null,
        textIndex < record.length ? record[textIndex] : null,
      ));
    }
    return result;
  }

  static String _firstRecord(String text) => text.split(RegExp(r'\r?\n')).first;

  static String _headerKey(String value) => value.trim().toLowerCase();

  static List<List<String>> _parseDelimited(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;

    void finishCell() {
      row.add(cell.toString());
      cell = StringBuffer();
    }

    void finishRow() {
      finishCell();
      rows.add(row);
      row = <String>[];
    }

    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '"') {
        if (quoted && index + 1 < text.length && text[index + 1] == '"') {
          cell.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && char == delimiter) {
        finishCell();
      } else if (!quoted && (char == '\n' || char == '\r')) {
        if (char == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index++;
        }
        finishRow();
      } else {
        cell.write(char);
      }
    }
    if (quoted) throw const FormatException('CSV 引號沒有正確關閉');
    if (cell.isNotEmpty || row.isNotEmpty) finishRow();
    return rows;
  }

  static Map<String, String> _validate(List<(Object?, Object?)> rows) {
    if (rows.length > maxEntries) {
      throw const FormatException('對照表最多可包含 10000 筆');
    }
    final result = <String, String>{};
    for (var index = 0; index < rows.length; index++) {
      final id = rows[index].$1?.toString().trim() ?? '';
      final label = rows[index].$2?.toString().trim() ?? '';
      final line = index + 2;
      if (id.isEmpty || label.isEmpty) {
        throw FormatException('第 $line 列的 id 或 text 是空的');
      }
      if (id.length > maxIdLength || label.length > maxTextLength) {
        throw FormatException('第 $line 列的內容過長');
      }
      if (result.containsKey(id)) {
        throw FormatException('對照表有重複 ID：$id');
      }
      result[id] = label;
    }
    if (result.isEmpty) throw const FormatException('對照表沒有任何資料');
    return result;
  }
}
