/// Platform-channel backed transports for Windows, plus Dart TCP for LAN.
library;

import 'dart:async';
import 'dart:io';
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

/// LAN / network raw TCP transport (JetDirect-style port 9100).
///
/// Uses Dart [Socket] — no native plugin calls. Works on Windows (and any
/// Flutter target with `dart:io`). Destination for [send] is a host name or IP
/// (e.g. `192.168.1.50`). There is no auto-discovery; pass [knownHosts] or
/// enter the IP in the app UI.
class TcpTransport implements Transport {
  TcpTransport({
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
    List<String>? knownHosts,
  }) : knownHosts = List<String>.from(knownHosts ?? const []);

  /// TCP port. Almost all ESC/POS network printers use **9100**.
  final int port;

  /// Connect / write timeout.
  final Duration timeout;

  /// Optional remembered hosts returned by [listPrinters].
  final List<String> knownHosts;

  @override
  Future<List<PrinterInfo>> listPrinters() async {
    return knownHosts
        .map((name) => PrinterInfo(name: name))
        .toList(growable: false);
  }

  @override
  Future<void> send(String host, Uint8List data) async {
    final target = host.trim();
    if (target.isEmpty) {
      throw ArgumentError('host is required for TcpTransport.send');
    }

    Socket? socket;
    try {
      socket = await Socket.connect(target, port, timeout: timeout);
      socket.add(data);
      await socket.flush().timeout(timeout);
    } on SocketException catch (e) {
      throw StateError('LAN print failed ($target:$port): ${e.message}');
    } on TimeoutException {
      throw StateError('LAN print timed out ($target:$port)');
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<bool> isPrinterReady(String host) async {
    final target = host.trim();
    if (target.isEmpty) return false;

    Socket? socket;
    try {
      socket = await Socket.connect(target, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
