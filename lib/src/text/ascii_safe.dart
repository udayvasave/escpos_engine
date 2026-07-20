/// ASCII-safe text helpers for single-byte thermal printer fonts.
library;

/// Makes receipt text safe for typical ESC/POS codepage fonts.
///
/// Most budget POS printers do not render UTF-8. Characters like `₹`, `·`,
/// or Hindi glyphs become garbage. This transliterates common receipt symbols
/// and replaces other non-ASCII runes with spaces.
String asciiSafe(String input) {
  final replaced = input
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAll('·', '*')
      .replaceAll('•', '*')
      .replaceAll('₹', 'Rs.')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('×', 'x')
      .replaceAll('…', '...')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'");

  final buffer = StringBuffer();
  for (final rune in replaced.runes) {
    if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
      buffer.writeCharCode(rune);
    } else if (rune >= 0x20 && rune <= 0x7E) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

/// Returns a hex preview of [bytes] for support / debug logs.
String bytesToHexPreview(List<int> bytes, {int max = 96}) {
  final n = bytes.length < max ? bytes.length : max;
  final parts = <String>[];
  for (var i = 0; i < n; i++) {
    parts.add(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  final body = parts.join(' ');
  return bytes.length > n ? '$body ...' : body;
}
