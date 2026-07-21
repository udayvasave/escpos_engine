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
/// On Android, uses paired classic Bluetooth (RFCOMM/SPP) devices instead.
/// Pair the printer in system settings first.
class BluetoothTransport implements Transport {
  BluetoothTransport({
    EscposEnginePlatform? platform,
    this.baudRate = 9600,
  }) : _platform = platform ?? EscposEnginePlatform.instance;

  final EscposEnginePlatform _platform;

  /// Serial baud rate for Windows COM ports. Ignored on Android RFCOMM.
  final int baudRate;

  @override
  Future<List<PrinterInfo>> listPrinters() async {
    try {
      final devices = await _platform.listBluetoothDevices();
      if (devices.isNotEmpty) {
        return devices
            .map(
              (d) => PrinterInfo(
                name: d['name']?.toString() ?? d['address']?.toString() ?? '',
                address: d['address']?.toString(),
              ),
            )
            .where((p) => p.destination.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // Fall through to Windows COM port listing.
    }

    final ports = await _platform.listSerialPorts();
    return ports.map((name) => PrinterInfo(name: name)).toList(growable: false);
  }

  @override
  Future<void> send(String destination, Uint8List data) async {
    if (_looksLikeMacAddress(destination)) {
      await _platform.writeBluetooth(destination, data);
      return;
    }
    return _platform.writeSerial(destination, data, baudRate: baudRate);
  }

  @override
  Future<bool> isPrinterReady(String destination) async {
    if (_looksLikeMacAddress(destination)) {
      final devices = await _platform.listBluetoothDevices();
      return devices.any(
        (d) =>
            d['address']?.toString().toUpperCase() ==
            destination.toUpperCase(),
      );
    }
    final ports = await _platform.listSerialPorts();
    return ports.any((p) => p.toUpperCase() == destination.toUpperCase());
  }

  static bool _looksLikeMacAddress(String value) {
    return RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(value);
  }
}

/// BLE (Bluetooth Low Energy) transport for ESC/POS thermal printers.
///
/// Scan for devices, then send raw bytes to a GATT write characteristic.
/// Auto-discovers common printer UUIDs (Nordic UART, FFF0/FFF1).
class BleTransport implements Transport {
  BleTransport({
    EscposEnginePlatform? platform,
    this.scanTimeout = const Duration(seconds: 5),
    this.serviceUuid,
    this.characteristicUuid,
    List<PrinterInfo>? knownDevices,
  })  : _platform = platform ?? EscposEnginePlatform.instance,
        _knownDevices = List<PrinterInfo>.from(knownDevices ?? const []);

  final EscposEnginePlatform _platform;
  final Duration scanTimeout;
  final String? serviceUuid;
  final String? characteristicUuid;
  final List<PrinterInfo> _knownDevices;

  /// Scans for nearby BLE devices and updates the internal device list.
  Future<List<PrinterInfo>> scan() async {
    final found = await _platform.scanBleDevices(timeout: scanTimeout);
    _knownDevices
      ..clear()
      ..addAll(
        found.map(
          (d) => PrinterInfo(
            name: d['name']?.toString() ?? d['address']?.toString() ?? '',
            address: d['address']?.toString(),
          ),
        ),
      );
    return listPrinters();
  }

  @override
  Future<List<PrinterInfo>> listPrinters() async {
    return List<PrinterInfo>.from(_knownDevices, growable: false);
  }

  @override
  Future<void> send(String destination, Uint8List data) {
    return _platform.writeBle(
      destination,
      data,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  @override
  Future<bool> isPrinterReady(String destination) {
    return _platform.isBleReady(destination);
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
