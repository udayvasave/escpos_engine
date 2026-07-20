/// Supported receipt paper dimensions in printable dots.
library;

/// Common thermal paper widths expressed as max printable dots.
enum PaperSize {
  /// ~58mm paper, typically 384 dots wide.
  mm58(384),

  /// ~80mm paper, typically 576 dots wide.
  mm80(576);

  const PaperSize(this.widthDots);

  /// Maximum printable width in dots for this paper size.
  final int widthDots;
}
