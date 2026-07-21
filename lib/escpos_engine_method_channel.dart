import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'escpos_engine_platform_interface.dart';

class MethodChannelEscposEngine extends EscposEnginePlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('escpos_engine');

  @override
  Future<String?> getPlatformVersion() async {
    return methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<List<String>> listPrinters() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'listPrinters',
    );
    if (result == null) return const [];
    return result.map((e) => e.toString()).toList(growable: false);
  }

  @override
  Future<void> printRaw(String printerName, Uint8List data) async {
    await methodChannel.invokeMethod<void>('printRaw', <String, dynamic>{
      'printerName': printerName,
      'data': data,
    });
  }

  @override
  Future<bool> isPrinterReady(String printerName) async {
    final result = await methodChannel.invokeMethod<bool>(
      'isPrinterReady',
      <String, dynamic>{'printerName': printerName},
    );
    return result ?? false;
  }

  @override
  Future<List<String>> listSerialPorts() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'listSerialPorts',
    );
    if (result == null) return const [];
    return result.map((e) => e.toString()).toList(growable: false);
  }

  @override
  Future<void> writeSerial(
    String portName,
    Uint8List data, {
    int baudRate = 9600,
  }) async {
    await methodChannel.invokeMethod<void>('writeSerial', <String, dynamic>{
      'portName': portName,
      'data': data,
      'baudRate': baudRate,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> scanBleDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'scanBleDevices',
      <String, dynamic>{'timeoutMs': timeout.inMilliseconds},
    );
    if (result == null) return const [];
    return result
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<void> writeBle(
    String address,
    Uint8List data, {
    String? serviceUuid,
    String? characteristicUuid,
  }) async {
    await methodChannel.invokeMethod<void>('writeBle', <String, dynamic>{
      'address': address,
      'data': data,
      if (serviceUuid != null) 'serviceUuid': serviceUuid,
      if (characteristicUuid != null) 'characteristicUuid': characteristicUuid,
    });
  }

  @override
  Future<bool> isBleReady(String address) async {
    final result = await methodChannel.invokeMethod<bool>(
      'isBleReady',
      <String, dynamic>{'address': address},
    );
    return result ?? false;
  }

  @override
  Future<List<Map<String, dynamic>>> listBluetoothDevices() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'listBluetoothDevices',
    );
    if (result == null) return const [];
    return result
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<void> writeBluetooth(String address, Uint8List data) async {
    await methodChannel.invokeMethod<void>('writeBluetooth', <String, dynamic>{
      'address': address,
      'data': data,
    });
  }
}
