/// Builds ESC/POS-ready rasters for QR payloads without native QR commands.
library;

import 'package:qr/qr.dart';

import '../image/dither.dart';
import '../image/image_converter.dart';
import '../receipt/receipt_element.dart';

/// Renders a QR code into a packed monochrome raster.
class QrRasterEncoder {
  const QrRasterEncoder();

  /// Creates a QR raster from [data].
  EscPosRasterImage encode(
    String data, {
    QrErrorCorrection errorCorrection = QrErrorCorrection.medium,
    int moduleSize = 4,
    int quietZoneModules = 2,
  }) {
    final level = switch (errorCorrection) {
      QrErrorCorrection.low => QrErrorCorrectLevel.L,
      QrErrorCorrection.medium => QrErrorCorrectLevel.M,
      QrErrorCorrection.quartile => QrErrorCorrectLevel.Q,
      QrErrorCorrection.high => QrErrorCorrectLevel.H,
    };

    final qrCode = QrCode.fromData(data: data, errorCorrectLevel: level);
    final qrImage = QrImage(qrCode);

    final module = moduleSize.clamp(1, 16);
    final quiet = quietZoneModules.clamp(0, 8);
    final modules = qrImage.moduleCount;
    final size = (modules + quiet * 2) * module;
    final pixels = List<int>.filled(size * size, 255);

    for (var y = 0; y < modules; y++) {
      for (var x = 0; x < modules; x++) {
        if (!qrImage.isDark(y, x)) continue;
        final startX = (x + quiet) * module;
        final startY = (y + quiet) * module;
        for (var dy = 0; dy < module; dy++) {
          for (var dx = 0; dx < module; dx++) {
            pixels[(startY + dy) * size + (startX + dx)] = 0;
          }
        }
      }
    }

    final gray = Uint8Gray(width: size, height: size, pixels: pixels);
    return ImageConverter(maxWidthDots: size, dither: false).convertGray(gray);
  }
}
