import 'dart:convert';

/// Produces a compact deterministic identifier for records that may be retried.
String stableRecordId(String prefix, Iterable<Object?> parts) {
  const offset = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xffffffffffffffff;

  var hash = offset;
  for (final byte in utf8.encode(jsonEncode(parts.toList()))) {
    hash ^= byte;
    hash = (hash * prime) & mask;
  }
  return '$prefix-${hash.toRadixString(16).padLeft(16, '0')}';
}
