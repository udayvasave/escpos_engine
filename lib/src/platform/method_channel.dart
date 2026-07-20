/// Platform-channel backed transports for Windows.
library;

import 'dart:typed_data';

import 'package:escpos_engine/escpos_engine_platform_interface.dart';

import '../printer/printer_info.dart';
import '../transport/transport.dart';

/// USB / Windows spooler RAW transport (`WritePrinter`).
class UsbTransport implements Transport {
  UsbTransport({EscposEnginePlatform? platform})
      : _platform = platform ?? EscposEnginePlatform.instance;

  final EscposEnginePlatform _platform;

  @override
  Future<List<PrinterInfo>> listPrinters() async {
    final names = await _platform.listPrinters();
    return names.map((name) => PrinterInfo(name: name)).toList(growable: false);
  }

  @override
  Future<void> send(String printerName, Uint8List data) {
    return _platform.printRaw(printerName, data);
  }

  @override
  Future<bool> isPrinterReady(String printerName) {
    return _platform.isPrinterReady(printerName);
  }
}

/// Bluetooth POS printers on Windows usually expose a virtual COM port (SPP).
///
/// Pair the printer in Windows Settings first, then use the COM port name
/// (e.g. `COM3`) as the destination for [send].
class BluetoothTransport implements Transport {
  BluetoothTransport({
    EscposEnginePlatform? platform,
    this.baudRate = 9600,
  }) : _platform = platform ?? EscposEnginePlatform.instance;

  final EscposEnginePlatform _platform;

  /// Serial baud rate. Many ESC/POS BT printers use 9600 or 115200.
  final int baudRate;

  @override
  Future<List<PrinterInfo>> listPrinters() async {
    final ports = await _platform.listSerialPorts();
    return ports.map((name) => PrinterInfo(name: name)).toList(growable: false);
  }

  @override
  Future<void> send(String portName, Uint8List data) {
    return _platform.writeSerial(portName, data, baudRate: baudRate);
  }

  @override
  Future<bool> isPrinterReady(String portName) async {
    final ports = await _platform.listSerialPorts();
    return ports.any((p) => p.toUpperCase() == portName.toUpperCase());
  }
}

/// LAN / network raw TCP transport (port 9100).
///
/// Not implemented yet — will be added after Bluetooth testing.
class TcpTransport implements Transport {
  TcpTransport({this.port = 9100});

  final int port;

  @override
  Future<List<PrinterInfo>> listPrinters() async {
    throw UnsupportedError(
      'TcpTransport (LAN) is not implemented yet. Use BluetoothTransport or UsbTransport.',
    );
  }

  @override
  Future<void> send(String host, Uint8List data) async {
    throw UnsupportedError(
      'TcpTransport (LAN) is not implemented yet. Use BluetoothTransport or UsbTransport.',
    );
  }

  @override
  Future<bool> isPrinterReady(String host) async {
    throw UnsupportedError(
      'TcpTransport (LAN) is not implemented yet. Use BluetoothTransport or UsbTransport.',
    );
  }
}
