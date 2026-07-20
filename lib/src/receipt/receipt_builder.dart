/// Composes structured receipt content into a [Receipt].
library;

import 'dart:typed_data';

import '../image/image_converter.dart';
import '../models/paper_size.dart';
import 'receipt.dart';
import 'receipt_element.dart';

/// Fluent builder for ESC/POS receipt jobs.
class ReceiptBuilder {
  ReceiptBuilder({
    this.paperSize = PaperSize.mm80,
  });

  final PaperSize paperSize;
  final List<ReceiptElement> _elements = [];

  /// Adds left-aligned text.
  ReceiptBuilder text(
    String text, {
    ReceiptAlignment alignment = ReceiptAlignment.left,
    bool bold = false,
    int widthScale = 1,
    int heightScale = 1,
  }) {
    _elements.add(
      TextElement(
        text,
        alignment: alignment,
        bold: bold,
        widthScale: widthScale,
        heightScale: heightScale,
      ),
    );
    return this;
  }

  /// Adds centered text.
  ReceiptBuilder centerText(
    String text, {
    bool bold = false,
    int widthScale = 1,
    int heightScale = 1,
  }) {
    return this.text(
      text,
      alignment: ReceiptAlignment.center,
      bold: bold,
      widthScale: widthScale,
      heightScale: heightScale,
    );
  }

  /// Adds a pre-converted raster image.
  ReceiptBuilder imageRaster(EscPosRasterImage raster, {bool center = true}) {
    _elements.add(
      RasterImageElement(
        raster,
        alignment: center ? ReceiptAlignment.center : ReceiptAlignment.left,
      ),
    );
    return this;
  }

  /// Adds an encoded image from PNG/JPEG bytes.
  ReceiptBuilder image(
    Uint8List imageBytes, {
    int? maxWidthDots,
    bool dither = true,
    int threshold = 128,
    bool center = true,
  }) {
    _elements.add(
      ImageElement(
        imageBytes,
        maxWidthDots: maxWidthDots ?? paperSize.widthDots,
        dither: dither,
        threshold: threshold,
        alignment: center ? ReceiptAlignment.center : ReceiptAlignment.left,
      ),
    );
    return this;
  }

  /// Adds a fixed-width logical row.
  ReceiptBuilder row(List<RowColumn> columns) {
    _elements.add(RowElement(List<RowColumn>.unmodifiable(columns)));
    return this;
  }

  /// Adds a divider line.
  ReceiptBuilder divider({String character = '-'}) {
    _elements.add(DividerElement(character: character));
    return this;
  }

  /// Feeds [lines] blank lines.
  ReceiptBuilder feed(int lines) {
    _elements.add(FeedElement(lines));
    return this;
  }

  /// Adds a QR code element.
  ReceiptBuilder qr(
    String data, {
    int size = 6,
    QrErrorCorrection errorCorrection = QrErrorCorrection.medium,
    bool? asRaster,
  }) {
    _elements.add(
      QrElement(
        data,
        size: size,
        errorCorrection: errorCorrection,
        asRaster: asRaster,
      ),
    );
    return this;
  }

  /// Adds a barcode element.
  ReceiptBuilder barcode(String data, {BarcodeType type = BarcodeType.code128}) {
    _elements.add(BarcodeElement(data, type: type));
    return this;
  }

  /// Adds a cash drawer pulse element.
  ReceiptBuilder drawer({int pin = 0, int onTime = 25, int offTime = 250}) {
    _elements.add(DrawerElement(pin: pin, onTime: onTime, offTime: offTime));
    return this;
  }

  /// Appends a partial cut command.
  ReceiptBuilder cut({CutMode mode = CutMode.partial}) {
    _elements.add(CutElement(mode: mode));
    return this;
  }

  /// Builds the immutable [Receipt].
  Receipt build() => Receipt(List<ReceiptElement>.from(_elements));
}
