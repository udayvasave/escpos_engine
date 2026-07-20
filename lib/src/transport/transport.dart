/// Transport contracts for sending already-encoded printer bytes.
library;

import 'dart:typed_data';

import '../printer/printer_info.dart';

/// Sends opaque bytes to a physical or virtual printer destination.
///
/// Transports do not encode ESC/POS and do not inspect receipt content.
/// Swap [UsbTransport], [BluetoothTransport], or (later) [TcpTransport]
/// without changing the receipt pipeline.
abstract interface class Transport {
  /// Lists destinations available to this transport.
  Future<List<PrinterInfo>> listPrinters();

  /// Sends already-encoded bytes to [destination]
  /// (spooler name, COM port, or later host:ip).
  Future<void> send(String destination, Uint8List data);

  /// Returns whether [destination] appears ready for printing.
  Future<bool> isPrinterReady(String destination);
}
