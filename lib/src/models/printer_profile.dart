/// Printer-specific capabilities and configuration profile.
library;

import 'paper_size.dart';

/// How images should be encoded for the target printer.
enum ImageEncodingMode {
  /// ESC/POS GS v 0 raster (preferred on modern printers).
  gsV0,

  /// ESC * column bit-image (fallback for some budget USB POS printers).
  escStar,
}

/// Describes how a physical printer should encode and size output.
class PrinterProfile {
  const PrinterProfile({
    this.name = 'generic',
    this.paperSize = PaperSize.mm80,
    this.maxRasterWidthDots = 576,
    this.charactersPerLine = 48,
    this.codePage = 'cp437',
    this.characterSet = 'usa',
    this.asciiSafeText = true,
    this.imageEncoding = ImageEncodingMode.gsV0,
    this.qrAsRaster = false,
    this.supportsRasterGsV0 = true,
    this.supportsQr = true,
    this.supportsBarcode = true,
    this.supportsCashDrawer = true,
  });

  /// Human-readable profile name (e.g. epson_tm_t82).
  final String name;

  /// Default paper width for raster sizing.
  final PaperSize paperSize;

  /// Maximum printable raster width in dots.
  final int maxRasterWidthDots;

  /// Approximate normal-font characters per line.
  final int charactersPerLine;

  /// Logical code page used by text encoding.
  final String codePage;

  /// Logical character set name.
  final String characterSet;

  /// When true, text is transliterated to printable ASCII before encoding.
  final bool asciiSafeText;

  /// Preferred image command family.
  final ImageEncodingMode imageEncoding;

  /// When true, QR codes are drawn as raster images instead of GS ( k.
  final bool qrAsRaster;

  /// Whether GS v 0 raster bit-images are supported.
  final bool supportsRasterGsV0;

  /// Whether native ESC/POS QR commands are supported.
  final bool supportsQr;

  /// Whether native ESC/POS barcode commands are supported.
  final bool supportsBarcode;

  /// Whether the cash drawer pulse command is supported.
  final bool supportsCashDrawer;

  /// Returns a copy with selected values changed.
  PrinterProfile copyWith({
    String? name,
    PaperSize? paperSize,
    int? maxRasterWidthDots,
    int? charactersPerLine,
    String? codePage,
    String? characterSet,
    bool? asciiSafeText,
    ImageEncodingMode? imageEncoding,
    bool? qrAsRaster,
    bool? supportsRasterGsV0,
    bool? supportsQr,
    bool? supportsBarcode,
    bool? supportsCashDrawer,
  }) {
    final resolvedPaperSize = paperSize ?? this.paperSize;
    return PrinterProfile(
      name: name ?? this.name,
      paperSize: resolvedPaperSize,
      maxRasterWidthDots: maxRasterWidthDots ?? this.maxRasterWidthDots,
      charactersPerLine: charactersPerLine ?? this.charactersPerLine,
      codePage: codePage ?? this.codePage,
      characterSet: characterSet ?? this.characterSet,
      asciiSafeText: asciiSafeText ?? this.asciiSafeText,
      imageEncoding: imageEncoding ?? this.imageEncoding,
      qrAsRaster: qrAsRaster ?? this.qrAsRaster,
      supportsRasterGsV0: supportsRasterGsV0 ?? this.supportsRasterGsV0,
      supportsQr: supportsQr ?? this.supportsQr,
      supportsBarcode: supportsBarcode ?? this.supportsBarcode,
      supportsCashDrawer: supportsCashDrawer ?? this.supportsCashDrawer,
    );
  }

  /// Generic 80mm ESC/POS profile.
  static const PrinterProfile generic80 = PrinterProfile(
    name: 'generic_80mm',
    paperSize: PaperSize.mm80,
    maxRasterWidthDots: 576,
    charactersPerLine: 48,
  );

  /// Generic 58mm ESC/POS profile.
  static const PrinterProfile generic58 = PrinterProfile(
    name: 'generic_58mm',
    paperSize: PaperSize.mm58,
    maxRasterWidthDots: 384,
    charactersPerLine: 32,
  );

  /// Compatibility-focused 58mm profile for budget Windows USB printers.
  static const PrinterProfile usbCompatible58 = PrinterProfile(
    name: 'usb_compatible_58mm',
    paperSize: PaperSize.mm58,
    maxRasterWidthDots: 384,
    charactersPerLine: 32,
    asciiSafeText: true,
    imageEncoding: ImageEncodingMode.escStar,
    qrAsRaster: true,
  );

  /// Compatibility-focused 80mm profile for budget Windows USB printers.
  static const PrinterProfile usbCompatible80 = PrinterProfile(
    name: 'usb_compatible_80mm',
    paperSize: PaperSize.mm80,
    maxRasterWidthDots: 576,
    charactersPerLine: 48,
    asciiSafeText: true,
    imageEncoding: ImageEncodingMode.escStar,
    qrAsRaster: true,
  );
}
