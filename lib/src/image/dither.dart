/// Image dithering for monochrome thermal receipt output.
library;

/// Applies Floyd–Steinberg error-diffusion dithering to an 8-bit grayscale
/// buffer in place and returns a packed boolean-friendly 0/255 buffer.
///
/// Input and output are row-major grayscale values (0 = black, 255 = white),
/// length must equal [width] * [height].
class Dither {
  const Dither();

  /// Floyd–Steinberg dithering. Returns a new buffer with values 0 or 255.
  Uint8Gray ditherFloydSteinberg(Uint8Gray input) {
    final width = input.width;
    final height = input.height;
    final pixels = List<double>.generate(
      input.pixels.length,
      (i) => input.pixels[i].toDouble(),
      growable: false,
    );

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final oldPixel = pixels[index].clamp(0.0, 255.0);
        final newPixel = oldPixel < 128.0 ? 0.0 : 255.0;
        pixels[index] = newPixel;
        final error = oldPixel - newPixel;

        if (x + 1 < width) {
          pixels[index + 1] += error * 7 / 16;
        }
        if (y + 1 < height) {
          if (x > 0) {
            pixels[(y + 1) * width + (x - 1)] += error * 3 / 16;
          }
          pixels[(y + 1) * width + x] += error * 5 / 16;
          if (x + 1 < width) {
            pixels[(y + 1) * width + (x + 1)] += error * 1 / 16;
          }
        }
      }
    }

    final out = List<int>.filled(pixels.length, 0);
    for (var i = 0; i < pixels.length; i++) {
      out[i] = pixels[i] < 128.0 ? 0 : 255;
    }
    return Uint8Gray(width: width, height: height, pixels: out);
  }

  /// Simple threshold: values below [threshold] become black (0).
  Uint8Gray threshold(Uint8Gray input, {int threshold = 128}) {
    final t = threshold.clamp(0, 255);
    final out = List<int>.generate(
      input.pixels.length,
      (i) => input.pixels[i] < t ? 0 : 255,
      growable: false,
    );
    return Uint8Gray(width: input.width, height: input.height, pixels: out);
  }
}

/// Row-major 8-bit grayscale image.
class Uint8Gray {
  const Uint8Gray({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;

  /// 0 = black, 255 = white.
  final List<int> pixels;
}
