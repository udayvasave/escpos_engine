import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escpos_engine/escpos_engine_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelEscposEngine();
  const channel = MethodChannel('escpos_engine');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getPlatformVersion':
          return '42';
        case 'listPrinters':
          return <String>['USB'];
        case 'listSerialPorts':
          return <String>['COM3'];
        case 'printRaw':
        case 'writeSerial':
          return true;
        case 'isPrinterReady':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('listSerialPorts', () async {
    expect(await platform.listSerialPorts(), ['COM3']);
  });

  test('writeSerial', () async {
    await platform.writeSerial(
      'COM3',
      Uint8List.fromList(const [0x1B, 0x40]),
      baudRate: 9600,
    );
  });
}
