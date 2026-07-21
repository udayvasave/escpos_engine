# escpos_engine

Cross-platform ESC/POS receipt engine for Flutter.

**ReceiptBuilder → Receipt → EscPosEncoder → Transport → printer**

Encoding stays in Dart. Transports only send opaque bytes.

## Status

| Transport | Windows | Android |
|-----------|---------|---------|
| USB (spooler RAW) | Done | — |
| Classic Bluetooth (SPP / COM) | Done (COM port) | Done (RFCOMM) |
| BLE (GATT write) | Done | Done |
| LAN (TCP 9100) | Done | Done |

## Install

```yaml
dependencies:
  escpos_engine:
    path: ../escpos_engine
```

## BLE printing (recommended for BLE thermal printers)

No COM port. Scan, pick device by MAC address, print via GATT.

```dart
final transport = BleTransport();
await transport.scan(timeout: Duration(seconds: 5));

final engine = EscposEngine(transport: transport);
await engine.print(
  ReceiptBuilder(paperSize: PaperSize.mm58)
      .centerText('BLE TEST', bold: true)
      .feed(3)
      .build(),
  destination: 'AA:BB:CC:DD:EE:FF', // MAC from scan
);
```

## Classic Bluetooth

**Windows:** pair printer → appears as `COM3` → use [BluetoothTransport].

**Android:** pair printer in Settings → use [BluetoothTransport] (RFCOMM/SPP).

```dart
final engine = EscposEngine(
  transport: BluetoothTransport(baudRate: 9600), // baud: Windows only
);
final devices = await engine.listPrinters();
await engine.print(receipt, destination: devices.first.destination);
```

## LAN (TCP 9100)

```dart
final engine = EscposEngine(transport: TcpTransport(port: 9100));
await engine.print(receipt, destination: '192.168.1.50');
```

## Example app

```bash
cd example
flutter run -d windows   # BLE scan + Classic BT + LAN + USB
flutter run              # Android: BLE + Classic BT + LAN
```

On Android, grant **Bluetooth** (and **Nearby devices** / scan) permissions when prompted.

## Notes

- BLE auto-discovers common write characteristics (Nordic UART, FFF0/FFF1, or first writable char).
- Optional UUID override: `BleTransport(serviceUuid: '...', characteristicUuid: '...')`.
- iOS plugin shell exists; native BT/BLE not implemented yet.
