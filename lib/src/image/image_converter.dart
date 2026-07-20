/// Converts images into ESC/POS-ready monochrome raster bitmaps.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dither.dart';

/// Packed monochrome raster suitable for GS v 0.
class EscPosRasterImage {
  const EscPosRasterImage({
    required this.widthPixels,
    required this.height,
    required this.widthBytes,
    required this.bytes,
  });

  /// Image width in pixels (may be padded to a multiple of 8).
  final int widthPixels;

  /// Image height in pixels.
  final int height;

  /// Bytes per row (= widthPixels / 8).
  final int widthBytes;

  /// Packed MSB-first rows: 1 = black (print), 0 = white.
  final Uint8List bytes;
}

/// Decodes image bytes, optionally resizes, dithers, and packs ESC/POS bits.
class ImageConverter {
  ImageConverter({
    this.maxWidthDots = 576,
    this.dither = true,
    this.threshold = 128,
    Dither? ditherEngine,
  }) : _dither = ditherEngine ?? const Dither();

  /// Maximum printed width in dots. Typical: 384 (58mm) or 576 (80mm).
  final int maxWidthDots;

  /// When true, applies Floyd–Steinberg dithering; otherwise thresholding.
  final bool dither;

  /// Threshold used when [dither] is false.
  final int threshold;

  final Dither _dither;

  /// Converts encoded image bytes (PNG/JPEG/etc.) into an ESC/POS raster.
  Future<EscPosRasterImage> convert(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError('imageBytes must not be empty');
    }
    if (maxWidthDots <= 0) {
      throw ArgumentError('maxWidthDots must be positive');
    }

    final codec = await ui.instantiateImageCodec(
      imageBytes,
      targetWidth: maxWidthDots,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    try {
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw StateError('Failed to read RGBA pixels from image');
      }

      final width = image.width;
      final height = image.height;
      final rgba = byteData.buffer.asUint8List();
      final gray = _rgbaToGray(rgba, width, height);

      final mono = dither
          ? _dither.ditherFloydSteinberg(gray)
          : _dither.threshold(gray, threshold: threshold);

      return _packBits(mono);
    } finally {
      image.dispose();
    }
  }

  /// Converts an already-decoded grayscale buffer into a packed raster.
  EscPosRasterImage convertGray(Uint8Gray gray) {
    final mono = dither
        ? _dither.ditherFloydSteinberg(gray)
        : _dither.threshold(gray, threshold: threshold);
    return _packBits(mono);
  }

  static Uint8Gray _rgbaToGray(Uint8List rgba, int width, int height) {
    final pixels = List<int>.filled(width * height, 0);
    for (var i = 0, p = 0; i < pixels.length; i++, p += 4) {
      final r = rgba[p];
      final g = rgba[p + 1];
      final b = rgba[p + 2];
      final a = rgba[p + 3];
      // Premultiply-style blend onto white for transparent logos.
      final luminance = (0.299 * r + 0.587 * g + 0.114 * b);
      final blended = ((luminance * a) + (255.0 * (255 - a))) / 255.0;
      pixels[i] = blended.round().clamp(0, 255);
    }
    return Uint8Gray(width: width, height: height, pixels: pixels);
  }

  static EscPosRasterImage _packBits(Uint8Gray mono) {
    final width = mono.width;
    final height = mono.height;
    // ESC/POS raster width must be a whole number of bytes.
    final widthBytes = (width + 7) ~/ 8;
    final widthPixels = widthBytes * 8;
    final out = Uint8List(widthBytes * height);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < widthPixels; x++) {
        final isBlack = x < width && mono.pixels[y * width + x] < 128;
        if (!isBlack) continue;
        final byteIndex = y * widthBytes + (x >> 3);
        final bit = 7 - (x & 7); // MSB leftmost
        out[byteIndex] |= 1 << bit;
      }
    }

    return EscPosRasterImage(
      widthPixels: widthPixels,
      height: height,
      widthBytes: widthBytes,
      bytes: out,
    );
  }
}
