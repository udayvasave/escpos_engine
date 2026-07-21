import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'escpos_engine_method_channel.dart';

abstract class EscposEnginePlatform extends PlatformInterface {
  EscposEnginePlatform() : super(token: _token);

  static final Object _token = Object();

  static EscposEnginePlatform _instance = MethodChannelEscposEngine();

  static EscposEnginePlatform get instance => _instance;

  static set instance(EscposEnginePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Lists Windows spooler printer queue names (USB / installed printers).
  Future<List<String>> listPrinters() {
    throw UnimplementedError('listPrinters() has not been implemented.');
  }

  /// Sends RAW bytes via Windows WritePrinter (USB / spooler).
  Future<void> printRaw(String printerName, Uint8List data) {
    throw UnimplementedError('printRaw() has not been implemented.');
  }

  Future<bool> isPrinterReady(String printerName) {
    throw UnimplementedError('isPrinterReady() has not been implemented.');
  }

  /// Lists serial/COM ports (typical path for paired Bluetooth POS printers).
  Future<List<String>> listSerialPorts() {
    throw UnimplementedError('listSerialPorts() has not been implemented.');
  }

  /// Writes raw bytes to a serial/COM port (Bluetooth SPP printers on Windows).
  Future<void> writeSerial(
    String portName,
    Uint8List data, {
    int baudRate = 9600,
  }) {
    throw UnimplementedError('writeSerial() has not been implemented.');
  }

  /// Scans for BLE devices. Each map has `address`, `name`, and `rssi`.
  Future<List<Map<String, dynamic>>> scanBleDevices({
    Duration timeout = const Duration(seconds: 5),
  }) {
    throw UnimplementedError('scanBleDevices() has not been implemented.');
  }

  /// Writes raw bytes to a BLE GATT characteristic.
  Future<void> writeBle(
    String address,
    Uint8List data, {
    String? serviceUuid,
    String? characteristicUuid,
  }) {
    throw UnimplementedError('writeBle() has not been implemented.');
  }

  /// Returns whether a BLE device at [address] responds to GATT.
  Future<bool> isBleReady(String address) {
    throw UnimplementedError('isBleReady() has not been implemented.');
  }

  /// Lists paired/bonded classic Bluetooth devices (Android).
  /// On Windows this falls back to [listSerialPorts].
  Future<List<Map<String, dynamic>>> listBluetoothDevices() {
    throw UnimplementedError('listBluetoothDevices() has not been implemented.');
  }

  /// Writes raw bytes over classic Bluetooth RFCOMM/SPP (Android).
  Future<void> writeBluetooth(
    String address,
    Uint8List data,
  ) {
    throw UnimplementedError('writeBluetooth() has not been implemented.');
  }
}
