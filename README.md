# escpos_engine

Cross-platform ESC/POS receipt engine for Flutter.

**ReceiptBuilder → Receipt → EscPosEncoder → Transport → printer**

Encoding stays in Dart. Transports only send opaque bytes.

## Package name

`escpos_engine` is intentional: not locked to Windows. Same core can grow USB, Bluetooth, LAN, Android, and iOS.

## Status

| Transport | Windows | Android / iOS |
|-----------|---------|---------------|
| USB (spooler RAW) | Done | Later |
| Bluetooth (COM / SPP) | Done | Later |
| LAN (TCP 9100) | Done (`dart:io` Socket) | Same Dart path later |

## Install (path / git for now)

```yaml
dependencies:
  escpos_engine:
    path: ../escpos_engine
```

## Bluetooth (Windows)

1. Pair the thermal printer in **Windows Settings → Bluetooth**.
2. Note the virtual **COM port** (Device Manager → Ports), e.g. `COM3`.
3. Run the example and select that COM port.

```dart
final engine = EscposEngine(
  transport: BluetoothTransport(baudRate: 9600), // try 115200 if needed
);

final ports = await engine.listPrinters(); // COM ports
await engine.print(
  ReceiptBuilder(paperSize: PaperSize.mm58)
      .centerText('BT TEST', bold: true)
      .feed(3)
      .build(),
  destination: 'COM3',
);
```

## LAN (TCP 9100)

Raw network printing — printer and PC on the same LAN. Destination is the printer IP/hostname. No auto-discovery; enter the IP in the example app (LAN tab).

```dart
final engine = EscposEngine(
  transport: TcpTransport(port: 9100),
);

final ready = await engine.isPrinterReady('192.168.1.50');
await engine.print(
  ReceiptBuilder(paperSize: PaperSize.mm58)
      .centerText('LAN TEST', bold: true)
      .feed(3)
      .build(),
  destination: '192.168.1.50',
);
```

## USB (Windows)

```dart
final engine = EscposEngine(transport: UsbTransport());
await engine.print(receipt, destination: 'POS58 Printer');
```

## Platforms

- **Windows**: USB + Bluetooth + LAN implemented
- **Android / iOS**: plugin stubs present; native USB/BT not implemented yet (LAN can use the same `TcpTransport` later)
