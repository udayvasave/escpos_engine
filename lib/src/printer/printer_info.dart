/// Printer discovery and capability information.
library;

/// Describes a printer destination for a transport.
class PrinterInfo {
  const PrinterInfo({
    required this.name,
    this.address,
  });

  /// Display name (COM port, spooler queue, BLE device name, etc.).
  final String name;

  /// Optional connection address (BLE MAC, classic BT MAC).
  /// When set, use [destination] for [Transport.send].
  final String? address;

  /// Value passed to [Transport.send] and [Transport.isPrinterReady].
  String get destination => address ?? name;

  @override
  String toString() => 'PrinterInfo($name${address != null ? ', $address' : ''})';

  @override
  bool operator ==(Object other) =>
      other is PrinterInfo && other.name == name && other.address == address;

  @override
  int get hashCode => Object.hash(name, address);
}
