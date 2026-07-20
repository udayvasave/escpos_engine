/// Printer discovery and capability information.
library;

/// Describes a printer visible to the Windows spooler.
class PrinterInfo {
  const PrinterInfo({required this.name});

  /// Windows printer queue name used with [OpenPrinter] / RAW jobs.
  final String name;

  @override
  String toString() => 'PrinterInfo($name)';

  @override
  bool operator ==(Object other) =>
      other is PrinterInfo && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
