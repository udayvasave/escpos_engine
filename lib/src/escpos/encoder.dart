/// Encodes printable content into ESC/POS byte streams.
library;

import 'dart:typed_data';

import '../image/image_converter.dart';
import '../models/paper_size.dart';
import '../models/printer_profile.dart';
import '../receipt/receipt.dart';
import '../receipt/receipt_element.dart';
import '../text/ascii_safe.dart';
import 'commands.dart';
import 'qr_raster.dart';

/// Builds complete ESC/POS jobs from higher-level content.
class EscPosEncoder {
  const EscPosEncoder();

  /// Encodes a declarative [Receipt] into ESC/POS bytes.
  Future<Uint8List> encode(
    Receipt receipt, {
    PrinterProfile profile = PrinterProfile.generic80,
    bool initialize = true,
  }) async {
    final chunks = <Uint8List>[];
    if (initialize) {
      chunks.add(EscPosCommands.initialize());
    }

    for (final element in receipt.elements) {
      chunks.addAll(await _encodeElement(element, profile));
    }

    return _concat(chunks);
  }

  /// Encodes a decoded/converted monochrome raster into a printable job.
  Uint8List encodeRasterImage(
    EscPosRasterImage raster, {
    bool initialize = true,
    bool center = true,
    int feedAfter = 2,
    bool cut = false,
  }) {
    final chunks = <Uint8List>[];

    if (initialize) {
      chunks.add(EscPosCommands.initialize());
    }
    if (center) {
      chunks.add(EscPosCommands.align(1));
    }

    chunks.add(
      EscPosCommands.rasterBitImage(
        widthBytes: raster.widthBytes,
        height: raster.height,
        bitmap: raster.bytes,
      ),
    );

    if (center) {
      chunks.add(EscPosCommands.align(0));
    }
    if (feedAfter > 0) {
      chunks.add(EscPosCommands.feedLines(feedAfter));
    }
    if (cut) {
      chunks.add(EscPosCommands.cutPartial());
    }

    return _concat(chunks);
  }

  /// Convenience: convert image bytes and encode a full print job.
  Future<Uint8List> encodeImageBytes(
    Uint8List imageBytes, {
    PaperSize paperSize = PaperSize.mm80,
    int? maxWidthDots,
    bool dither = true,
    int threshold = 128,
    bool initialize = true,
    bool center = true,
    int feedAfter = 2,
    bool cut = false,
  }) async {
    final converter = ImageConverter(
      maxWidthDots: maxWidthDots ?? paperSize.widthDots,
      dither: dither,
      threshold: threshold,
    );
    final raster = await converter.convert(imageBytes);
    return encodeRasterImage(
      raster,
      initialize: initialize,
      center: center,
      feedAfter: feedAfter,
      cut: cut,
    );
  }

  Future<List<Uint8List>> _encodeElement(
    ReceiptElement element,
    PrinterProfile profile,
  ) async {
    return switch (element) {
      TextElement e => _encodeText(e, profile),
      ImageElement e => await _encodeImage(e, profile),
      RasterImageElement e => _encodeRasterElement(e, profile),
      RowElement e => _encodeRow(e, profile),
      DividerElement e => _encodeDivider(e, profile),
      FeedElement e => [EscPosCommands.feedLines(e.lines)],
      CutElement e => [
          e.mode == CutMode.full
              ? EscPosCommands.cutFull()
              : EscPosCommands.cutPartial(),
        ],
      BarcodeElement e => _encodeBarcode(e, profile),
      QrElement e => await _encodeQr(e, profile),
      DrawerElement e => _encodeDrawer(e, profile),
      _ => throw UnsupportedError('Unsupported receipt element: $element'),
    };
  }

  List<Uint8List> _encodeText(TextElement element, PrinterProfile profile) {
    // Prefer ESC ! for bold/double-size: budget POS58 printers often ignore GS !.
    // Still send GS ! so Epson-class devices can honor 3x-8x scales.
    final doubleWidth = element.widthScale >= 2;
    final doubleHeight = element.heightScale >= 2;
    return [
      EscPosCommands.align(_alignmentValue(element.alignment)),
      EscPosCommands.printMode(
        bold: element.bold,
        doubleWidth: doubleWidth,
        doubleHeight: doubleHeight,
      ),
      EscPosCommands.characterSize(
        widthScale: element.widthScale,
        heightScale: element.heightScale,
      ),
      _encodeTextBytes(element.text, profile),
      EscPosCommands.lineFeed(),
      EscPosCommands.characterSize(),
      EscPosCommands.printMode(),
      EscPosCommands.align(0),
    ];
  }

  Future<List<Uint8List>> _encodeImage(
    ImageElement element,
    PrinterProfile profile,
  ) async {
    final converter = ImageConverter(
      maxWidthDots: element.maxWidthDots ?? profile.maxRasterWidthDots,
      dither: element.dither,
      threshold: element.threshold,
    );
    final raster = await converter.convert(element.bytes);
    return _encodeRasterElement(
      RasterImageElement(raster, alignment: element.alignment),
      profile,
    );
  }

  List<Uint8List> _encodeRasterElement(
    RasterImageElement element,
    PrinterProfile profile,
  ) {
    final chunks = <Uint8List>[
      EscPosCommands.align(_alignmentValue(element.alignment)),
    ];

    if (profile.imageEncoding == ImageEncodingMode.escStar) {
      chunks.addAll(_encodeEscStar(element.raster));
    } else {
      if (!profile.supportsRasterGsV0) {
        throw UnsupportedError(
          '${profile.name} does not support GS v 0 raster',
        );
      }
      chunks.add(
        EscPosCommands.rasterBitImage(
          widthBytes: element.raster.widthBytes,
          height: element.raster.height,
          bitmap: element.raster.bytes,
        ),
      );
    }

    chunks.add(EscPosCommands.align(0));
    return chunks;
  }

  List<Uint8List> _encodeEscStar(EscPosRasterImage raster) {
    final out = <Uint8List>[];
    final width = raster.widthPixels;
    for (var y = 0; y < raster.height; y += 24) {
      final columns = Uint8List(width * 3);
      for (var x = 0; x < width; x++) {
        var b0 = 0;
        var b1 = 0;
        var b2 = 0;
        for (var k = 0; k < 8; k++) {
          if (_isBlack(raster, x, y + k)) b0 |= 0x80 >> k;
          if (_isBlack(raster, x, y + 8 + k)) b1 |= 0x80 >> k;
          if (_isBlack(raster, x, y + 16 + k)) b2 |= 0x80 >> k;
        }
        final i = x * 3;
        columns[i] = b0;
        columns[i + 1] = b1;
        columns[i + 2] = b2;
      }
      out.add(
        EscPosCommands.escStarBitImage(
          widthPixels: width,
          columnData: columns,
        ),
      );
      out.add(EscPosCommands.lineFeed());
    }
    return out;
  }

  bool _isBlack(EscPosRasterImage raster, int x, int y) {
    if (x < 0 || y < 0 || x >= raster.widthPixels || y >= raster.height) {
      return false;
    }
    final byteIndex = y * raster.widthBytes + (x >> 3);
    final bit = 7 - (x & 7);
    return (raster.bytes[byteIndex] & (1 << bit)) != 0;
  }

  List<Uint8List> _encodeRow(RowElement element, PrinterProfile profile) {
    if (element.columns.isEmpty) {
      return const [];
    }

    final totalWeight = element.columns.fold<int>(
      0,
      (sum, column) =>
          sum + column.width.clamp(1, profile.charactersPerLine).toInt(),
    );
    final line = StringBuffer();
    var used = 0;

    for (var i = 0; i < element.columns.length; i++) {
      final column = element.columns[i];
      final isLast = i == element.columns.length - 1;
      final width = isLast
          ? profile.charactersPerLine - used
          : (profile.charactersPerLine * column.width / totalWeight).floor();
      used += width;
      line.write(
        _fitText(
          profile.asciiSafeText ? asciiSafe(column.text) : column.text,
          width,
          column.alignment,
        ),
      );
    }

    return [
      _encodeTextBytes(line.toString(), profile),
      EscPosCommands.lineFeed(),
    ];
  }

  List<Uint8List> _encodeDivider(
    DividerElement element,
    PrinterProfile profile,
  ) {
    final char = element.character.isEmpty ? '-' : element.character[0];
    return [
      _encodeTextBytes(
        List<String>.filled(profile.charactersPerLine, char).join(),
        profile,
      ),
      EscPosCommands.lineFeed(),
    ];
  }

  Future<List<Uint8List>> _encodeQr(
    QrElement element,
    PrinterProfile profile,
  ) async {
    final asRaster = element.asRaster ?? profile.qrAsRaster;
    if (asRaster) {
      final raster = const QrRasterEncoder().encode(
        element.data,
        errorCorrection: element.errorCorrection,
        moduleSize: (element.size / 2).ceil().clamp(2, 8),
      );
      return _encodeRasterElement(
        RasterImageElement(raster, alignment: element.alignment),
        profile,
      );
    }

    if (!profile.supportsQr) {
      throw UnsupportedError('${profile.name} does not support QR commands');
    }
    final data = _encodeString(element.data, profile);
    return [
      EscPosCommands.align(_alignmentValue(element.alignment)),
      EscPosCommands.qrSize(element.size),
      EscPosCommands.qrErrorCorrection(_qrErrorCorrectionValue(
        element.errorCorrection,
      )),
      EscPosCommands.qrStore(data),
      EscPosCommands.qrPrint(),
      EscPosCommands.lineFeed(),
      EscPosCommands.align(0),
    ];
  }

  List<Uint8List> _encodeBarcode(
    BarcodeElement element,
    PrinterProfile profile,
  ) {
    if (!profile.supportsBarcode) {
      throw UnsupportedError(
        '${profile.name} does not support barcode commands',
      );
    }
    return [
      EscPosCommands.align(_alignmentValue(element.alignment)),
      EscPosCommands.code128Barcode(_encodeString(element.data, profile)),
      EscPosCommands.lineFeed(),
      EscPosCommands.align(0),
    ];
  }

  List<Uint8List> _encodeDrawer(
    DrawerElement element,
    PrinterProfile profile,
  ) {
    if (!profile.supportsCashDrawer) {
      throw UnsupportedError(
        '${profile.name} does not support cash drawer pulse',
      );
    }
    return [
      EscPosCommands.pulse(
        pin: element.pin,
        onTime: element.onTime,
        offTime: element.offTime,
      ),
    ];
  }

  Uint8List _encodeTextBytes(String text, PrinterProfile profile) {
    return Uint8List.fromList(_encodeString(text, profile));
  }

  List<int> _encodeString(String text, PrinterProfile profile) {
    final value = profile.asciiSafeText ? asciiSafe(text) : text;
    // After asciiSafe, Latin-1 / ASCII bytes are sufficient for POS fonts.
    return value.codeUnits;
  }

  int _alignmentValue(ReceiptAlignment alignment) {
    return switch (alignment) {
      ReceiptAlignment.left => 0,
      ReceiptAlignment.center => 1,
      ReceiptAlignment.right => 2,
    };
  }

  int _qrErrorCorrectionValue(QrErrorCorrection level) {
    return switch (level) {
      QrErrorCorrection.low => 48,
      QrErrorCorrection.medium => 49,
      QrErrorCorrection.quartile => 50,
      QrErrorCorrection.high => 51,
    };
  }

  String _fitText(String text, int width, ReceiptAlignment alignment) {
    if (width <= 0) {
      return '';
    }
    final value = text.length > width ? text.substring(0, width) : text;
    final padding = width - value.length;
    return switch (alignment) {
      ReceiptAlignment.left => value.padRight(width),
      ReceiptAlignment.right => value.padLeft(width),
      ReceiptAlignment.center => '${' ' * (padding ~/ 2)}$value'
          .padRight(width),
    };
  }

  static Uint8List _concat(List<Uint8List> parts) {
    final total = parts.fold<int>(0, (sum, p) => sum + p.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final part in parts) {
      out.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return out;
  }
}
