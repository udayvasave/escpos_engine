import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:escpos_engine/escpos_engine.dart';
import 'package:escpos_engine/escpos_engine_method_channel.dart';
import 'package:escpos_engine/escpos_engine_platform_interface.dart';

class MockEscposEnginePlatform
    with MockPlatformInterfaceMixin
    implements EscposEnginePlatform {
  final List<Map<String, Object?>> serialWrites = [];
  final List<Map<String, Object?>> usbWrites = [];
  final List<Map<String, Object?>> bleWrites = [];

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<List<String>> listPrinters() async => const ['USB Printer'];

  @override
  Future<void> printRaw(String printerName, Uint8List data) async {
    usbWrites.add({'printerName': printerName, 'data': data});
  }

  @override
  Future<bool> isPrinterReady(String printerName) async => true;

  @override
  Future<List<String>> listSerialPorts() async => const ['COM3', 'COM5'];

  @override
  Future<void> writeSerial(
    String portName,
    Uint8List data, {
    int baudRate = 9600,
  }) async {
    serialWrites.add({
      'portName': portName,
      'data': data,
      'baudRate': baudRate,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> scanBleDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return [
      {'address': 'AA:BB:CC:DD:EE:FF', 'name': 'BLE Printer', 'rssi': -55},
    ];
  }

  @override
  Future<void> writeBle(
    String address,
    Uint8List data, {
    String? serviceUuid,
    String? characteristicUuid,
  }) async {
    bleWrites.add({
      'address': address,
      'data': data,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
    });
  }

  @override
  Future<bool> isBleReady(String address) async => true;

  @override
  Future<List<Map<String, dynamic>>> listBluetoothDevices() async => const [];

  @override
  Future<void> writeBluetooth(String address, Uint8List data) async {}
}

void main() {
  test('$MethodChannelEscposEngine is the default instance', () {
    expect(
      EscposEnginePlatform.instance,
      isInstanceOf<MethodChannelEscposEngine>(),
    );
  });

  test('BluetoothTransport lists COM ports and writes serial', () async {
    final fake = MockEscposEnginePlatform();
    EscposEnginePlatform.instance = fake;
    final engine = EscposEngine(
      transport: BluetoothTransport(baudRate: 115200),
    );

    final ports = await engine.listPrinters();
    expect(ports.map((p) => p.name), ['COM3', 'COM5']);

    final receipt = ReceiptBuilder().centerText('BT').feed(1).build();
    await engine.print(receipt, destination: 'COM3');

    expect(fake.serialWrites, hasLength(1));
    expect(fake.serialWrites.first['portName'], 'COM3');
    expect(fake.serialWrites.first['baudRate'], 115200);
    final data = fake.serialWrites.first['data']! as Uint8List;
    expect(data.take(2).toList(), [0x1B, 0x40]);
  });

  test('UsbTransport forwards to printRaw', () async {
    final fake = MockEscposEnginePlatform();
    EscposEnginePlatform.instance = fake;
    final engine = EscposEngine(transport: UsbTransport());

    await engine.printRaw('USB Printer', Uint8List.fromList([0x1B, 0x40]));
    expect(fake.usbWrites, hasLength(1));
  });

  test('BleTransport scans and writes over BLE', () async {
    final fake = MockEscposEnginePlatform();
    EscposEnginePlatform.instance = fake;
    final transport = BleTransport();
    final engine = EscposEngine(transport: transport);

    final devices = await transport.scan();
    expect(devices, hasLength(1));
    expect(devices.first.address, 'AA:BB:CC:DD:EE:FF');

    await engine.printRaw('AA:BB:CC:DD:EE:FF', Uint8List.fromList([0x1B, 0x40]));
    expect(fake.bleWrites, hasLength(1));
    expect(fake.bleWrites.first['address'], 'AA:BB:CC:DD:EE:FF');
  });

  test('TcpTransport lists known hosts and sends over TCP', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <int>[];
    final sub = server.listen((client) {
      client.listen(
        received.addAll,
        onDone: client.destroy,
      );
    });

    addTearDown(() async {
      await sub.cancel();
      await server.close();
    });

    final transport = TcpTransport(
      port: server.port,
      knownHosts: const ['127.0.0.1'],
      timeout: const Duration(seconds: 2),
    );
    final engine = EscposEngine(transport: transport);

    final listed = await engine.listPrinters();
    expect(listed.map((p) => p.name), ['127.0.0.1']);
    expect(await engine.isPrinterReady('127.0.0.1'), isTrue);

    await engine.printRaw('127.0.0.1', Uint8List.fromList([0x1B, 0x40]));

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, [0x1B, 0x40]);
  });

  test('asciiSafe transliterates currency', () {
    expect(asciiSafe('Total ₹10'), 'Total Rs.10');
  });

  test('styled text uses ESC !', () async {
    final bytes = await const EscPosEncoder().encode(
      ReceiptBuilder()
          .centerText('BIG', bold: true, widthScale: 2, heightScale: 2)
          .build(),
      profile: PrinterProfile.generic58,
    );
    expect(bytes, containsAllInOrder([0x1B, 0x21, 0x38]));
  });
}
