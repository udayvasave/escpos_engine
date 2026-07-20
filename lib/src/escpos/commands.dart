/// ESC/POS command byte sequences used by the encoding layer.
library;

import 'dart:typed_data';

/// Low-level ESC/POS command builders.
///
/// This class only produces raw command bytes. It does not talk to printers.
class EscPosCommands {
  EscPosCommands._();

  /// Initialize printer: ESC @
  static Uint8List initialize() => Uint8List.fromList(const [0x1B, 0x40]);

  /// Feed [lines] lines: ESC d n
  static Uint8List feedLines(int lines) {
    final n = lines.clamp(0, 255);
    return Uint8List.fromList([0x1B, 0x64, n]);
  }

  /// Partial cut: GS V 1
  static Uint8List cutPartial() =>
      Uint8List.fromList(const [0x1D, 0x56, 0x01]);

  /// Full cut: GS V 0
  static Uint8List cutFull() => Uint8List.fromList(const [0x1D, 0x56, 0x00]);

  /// Align left / center / right: ESC a n
  static Uint8List align(int n) =>
      Uint8List.fromList([0x1B, 0x61, n.clamp(0, 2)]);

  /// Emphasized text on/off: ESC E n
  static Uint8List bold(bool enabled) =>
      Uint8List.fromList([0x1B, 0x45, enabled ? 1 : 0]);

  /// Print mode: ESC ! n
  ///
  /// Widely supported on cheap POS58/80 printers for bold + double size.
  /// Bit 3 = emphasized, bit 4 = double-height, bit 5 = double-width.
  static Uint8List printMode({
    bool bold = false,
    bool doubleWidth = false,
    bool doubleHeight = false,
  }) {
    var n = 0;
    if (bold) n |= 0x08;
    if (doubleHeight) n |= 0x10;
    if (doubleWidth) n |= 0x20;
    return Uint8List.fromList([0x1B, 0x21, n]);
  }

  /// Character size: GS ! n
  ///
  /// Supports 1x-8x on Epson-class printers. Many budget POS58 printers
  /// ignore this and only honor [printMode] (ESC !).
  static Uint8List characterSize({int widthScale = 1, int heightScale = 1}) {
    final width = (widthScale.clamp(1, 8) - 1) & 0x07;
    final height = (heightScale.clamp(1, 8) - 1) & 0x07;
    return Uint8List.fromList([0x1D, 0x21, (width << 4) | height]);
  }

  /// Line feed.
  static Uint8List lineFeed() => Uint8List.fromList(const [0x0A]);

  /// Raster bit-image: GS v 0 m xL xH yL yH [data]
  ///
  /// [widthBytes] is the number of data bytes per row (pixels / 8, rounded up).
  /// [height] is the image height in pixels.
  /// [m] selects density: 0 normal, 1 double-width, 2 double-height, 3 both.
  static Uint8List rasterBitImage({
    required int widthBytes,
    required int height,
    required Uint8List bitmap,
    int m = 0,
  }) {
    if (widthBytes <= 0 || height <= 0) {
      throw ArgumentError('Raster image dimensions must be positive');
    }
    final expected = widthBytes * height;
    if (bitmap.length < expected) {
      throw ArgumentError(
        'Bitmap length ${bitmap.length} is shorter than $expected bytes',
      );
    }

    final xL = widthBytes & 0xFF;
    final xH = (widthBytes >> 8) & 0xFF;
    final yL = height & 0xFF;
    final yH = (height >> 8) & 0xFF;

    final header = Uint8List.fromList([
      0x1D, // GS
      0x76, // v
      0x30, // 0
      m & 0x03,
      xL,
      xH,
      yL,
      yH,
    ]);

    final out = Uint8List(header.length + expected);
    out.setRange(0, header.length, header);
    out.setRange(header.length, out.length, bitmap, 0);
    return out;
  }

  /// Column bit-image: ESC * m nL nH [data]
  ///
  /// [m] 32 = 24-dot single density (3 bytes per column).
  /// Used as a fallback when GS v 0 is unreliable on budget printers.
  static Uint8List escStarBitImage({
    required int widthPixels,
    required Uint8List columnData,
    int m = 32,
  }) {
    if (widthPixels <= 0) {
      throw ArgumentError('widthPixels must be positive');
    }
    final expected = widthPixels * 3;
    if (columnData.length < expected) {
      throw ArgumentError(
        'Column data length ${columnData.length} is shorter than $expected',
      );
    }
    final nL = widthPixels & 0xFF;
    final nH = (widthPixels >> 8) & 0xFF;
    final header = Uint8List.fromList([0x1B, 0x2A, m, nL, nH]);
    final out = Uint8List(header.length + expected);
    out.setRange(0, header.length, header);
    out.setRange(header.length, out.length, columnData, 0);
    return out;
  }

  /// Stores QR data in the printer symbol storage area: GS ( k.
  static Uint8List qrStore(List<int> data) {
    final len = data.length + 3;
    final pL = len & 0xFF;
    final pH = (len >> 8) & 0xFF;
    return Uint8List.fromList([
      0x1D,
      0x28,
      0x6B,
      pL,
      pH,
      0x31,
      0x50,
      0x30,
      ...data,
    ]);
  }

  /// Sets QR module size: GS ( k.
  static Uint8List qrSize(int size) {
    return Uint8List.fromList([
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x43,
      size.clamp(1, 16),
    ]);
  }

  /// Sets QR error correction level: GS ( k.
  static Uint8List qrErrorCorrection(int level) {
    return Uint8List.fromList([
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x45,
      level,
    ]);
  }

  /// Prints a stored QR symbol: GS ( k.
  static Uint8List qrPrint() {
    return Uint8List.fromList(const [
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x51,
      0x30,
    ]);
  }

  /// Code 128 barcode: GS k m d1..dk NUL.
  static Uint8List code128Barcode(List<int> data) {
    return Uint8List.fromList([0x1D, 0x6B, 0x49, data.length, ...data]);
  }

  /// Cash drawer pulse: ESC p m t1 t2.
  static Uint8List pulse({int pin = 0, int onTime = 25, int offTime = 250}) {
    return Uint8List.fromList([
      0x1B,
      0x70,
      pin.clamp(0, 1),
      onTime.clamp(0, 255),
      offTime.clamp(0, 255),
    ]);
  }
}
