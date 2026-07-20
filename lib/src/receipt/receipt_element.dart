/// Immutable receipt element model used by the ESC/POS encoder.
library;

import 'dart:typed_data';

import '../image/image_converter.dart';

/// Horizontal alignment for printable receipt content.
enum ReceiptAlignment {
  /// Align content to the left edge.
  left,

  /// Center content within the printable width.
  center,

  /// Align content to the right edge.
  right,
}

/// Paper cut mode requested by a receipt.
enum CutMode {
  /// Partial cut, leaving a small tab attached when supported.
  partial,

  /// Full cut when supported by the printer.
  full,
}

/// Base class for all printable receipt content.
///
/// Elements are declarative. They do not contain ESC/POS bytes, printer names,
/// transports, or platform-channel details.
abstract class ReceiptElement {
  /// Creates an immutable receipt element.
  const ReceiptElement();
}

/// Text content in a receipt.
class TextElement extends ReceiptElement {
  /// Creates a text element.
  const TextElement(
    this.text, {
    this.alignment = ReceiptAlignment.left,
    this.bold = false,
    this.widthScale = 1,
    this.heightScale = 1,
  });

  /// Text to encode for the target printer profile.
  final String text;

  /// Horizontal alignment.
  final ReceiptAlignment alignment;

  /// Whether text should be emphasized.
  final bool bold;

  /// Character width multiplier, clamped by the encoder.
  final int widthScale;

  /// Character height multiplier, clamped by the encoder.
  final int heightScale;
}

/// Image content represented by encoded PNG/JPEG/etc. bytes.
class ImageElement extends ReceiptElement {
  /// Creates an image element from encoded image bytes.
  const ImageElement(
    this.bytes, {
    this.alignment = ReceiptAlignment.center,
    this.maxWidthDots,
    this.dither = true,
    this.threshold = 128,
  });

  /// Encoded image bytes.
  final Uint8List bytes;

  /// Horizontal alignment.
  final ReceiptAlignment alignment;

  /// Optional raster width override.
  final int? maxWidthDots;

  /// Whether Floyd-Steinberg dithering should be applied.
  final bool dither;

  /// Threshold used when [dither] is false.
  final int threshold;
}

/// Image content that has already been converted into ESC/POS raster pixels.
class RasterImageElement extends ReceiptElement {
  /// Creates an already-converted raster image element.
  const RasterImageElement(
    this.raster, {
    this.alignment = ReceiptAlignment.center,
  });

  /// Packed monochrome raster.
  final EscPosRasterImage raster;

  /// Horizontal alignment.
  final ReceiptAlignment alignment;
}

/// A logical row, usually used for receipt tables.
class RowElement extends ReceiptElement {
  /// Creates a row element with fixed-width columns.
  const RowElement(this.columns);

  /// Row columns. The encoder is responsible for fitting them to the profile.
  final List<RowColumn> columns;
}

/// A single column inside a [RowElement].
class RowColumn {
  /// Creates a row column.
  const RowColumn(
    this.text, {
    this.width = 1,
    this.alignment = ReceiptAlignment.left,
  });

  /// Column text.
  final String text;

  /// Relative width. Encoders may map this to profile-specific character cells.
  final int width;

  /// Column alignment.
  final ReceiptAlignment alignment;
}

/// A horizontal divider line.
class DividerElement extends ReceiptElement {
  /// Creates a divider element.
  const DividerElement({this.character = '-'});

  /// Character used to draw the divider.
  final String character;
}

/// Blank paper feed.
class FeedElement extends ReceiptElement {
  /// Creates a feed element.
  const FeedElement(this.lines);

  /// Number of lines to feed.
  final int lines;
}

/// Paper cut command.
class CutElement extends ReceiptElement {
  /// Creates a cut element.
  const CutElement({this.mode = CutMode.partial});

  /// Requested cut mode.
  final CutMode mode;
}

/// Barcode content.
class BarcodeElement extends ReceiptElement {
  /// Creates a barcode element.
  const BarcodeElement(
    this.data, {
    this.type = BarcodeType.code128,
    this.alignment = ReceiptAlignment.center,
  });

  /// Barcode payload.
  final String data;

  /// Barcode symbology.
  final BarcodeType type;

  /// Horizontal alignment.
  final ReceiptAlignment alignment;
}

/// Supported barcode symbologies.
enum BarcodeType {
  /// Code 128 barcode.
  code128,
}

/// QR code content.
class QrElement extends ReceiptElement {
  /// Creates a QR element.
  const QrElement(
    this.data, {
    this.alignment = ReceiptAlignment.center,
    this.size = 6,
    this.errorCorrection = QrErrorCorrection.medium,
    this.asRaster,
  });

  /// QR payload.
  final String data;

  /// Horizontal alignment.
  final ReceiptAlignment alignment;

  /// ESC/POS module size, normally 1..16.
  final int size;

  /// Error correction level.
  final QrErrorCorrection errorCorrection;

  /// When non-null, overrides [PrinterProfile.qrAsRaster].
  final bool? asRaster;
}

/// QR error correction level.
enum QrErrorCorrection {
  /// Low error correction.
  low,

  /// Medium error correction.
  medium,

  /// Quartile error correction.
  quartile,

  /// High error correction.
  high,
}

/// Cash drawer pulse command.
class DrawerElement extends ReceiptElement {
  /// Creates a drawer kick element.
  const DrawerElement({
    this.pin = 0,
    this.onTime = 25,
    this.offTime = 250,
  });

  /// Drawer connector pin.
  final int pin;

  /// Pulse on time.
  final int onTime;

  /// Pulse off time.
  final int offTime;
}
