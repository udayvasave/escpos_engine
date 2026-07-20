/// Immutable representation of printable receipt content.
library;

import 'receipt_element.dart';

/// A receipt as an ordered sequence of declarative [ReceiptElement] objects.
///
/// This type does not contain ESC/POS bytes, printer names, platform channels,
/// or transport details. It is pure printable content.
class Receipt {
  /// Creates an immutable receipt.
  Receipt(List<ReceiptElement> elements)
      : elements = List<ReceiptElement>.unmodifiable(elements);

  /// Declarative receipt content.
  final List<ReceiptElement> elements;
}
