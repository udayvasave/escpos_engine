import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:escpos_engine/escpos_engine.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

enum _Mode { bluetooth, usb }

class _MyAppState extends State<MyApp> {
  _Mode _mode = _Mode.bluetooth;
  int _baudRate = 9600;
  PaperSize _paperSize = PaperSize.mm58;

  List<PrinterInfo> _destinations = const [];
  String? _selected;
  String _status = 'Pair your BT printer, then refresh COM ports.';
  bool _busy = false;

  EscposEngine get _engine {
    if (_mode == _Mode.bluetooth) {
      return EscposEngine(
        transport: BluetoothTransport(baudRate: _baudRate),
        profile: _paperSize == PaperSize.mm58
            ? PrinterProfile.generic58
            : PrinterProfile.generic80,
      );
    }
    return EscposEngine(
      transport: UsbTransport(),
      profile: _paperSize == PaperSize.mm58
          ? PrinterProfile.generic58
          : PrinterProfile.generic80,
    );
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final list = await _engine.listPrinters();
      setState(() {
        _destinations = list;
        _selected = list.isEmpty
            ? null
            : (list.any((p) => p.name == _selected)
                ? _selected
                : list.first.name);
        _status = list.isEmpty
            ? (_mode == _Mode.bluetooth
                ? 'No COM ports. Pair BT printer in Windows Settings.'
                : 'No USB printers found.')
            : 'Found ${list.length} destination(s)';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Refresh failed: ${e.message}');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _printTest() async {
    final dest = _selected;
    if (dest == null) {
      setState(() => _status = 'Select a destination first');
      return;
    }
    setState(() => _busy = true);
    try {
      final receipt = ReceiptBuilder(paperSize: _paperSize)
          .centerText('ESCPOS ENGINE', bold: true, widthScale: 2, heightScale: 2)
          .feed(1)
          .centerText(_mode == _Mode.bluetooth ? 'Bluetooth / $dest' : 'USB / $dest')
          .text('Baud: $_baudRate')
          .feed(3)
          .build();
      await _engine.print(receipt, destination: dest, debugLogBytes: true);
      setState(() => _status = 'Print OK → $dest');
    } on PlatformException catch (e) {
      setState(() => _status = 'Print failed: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Print error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('escpos_engine — BT first')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_status),
            const SizedBox(height: 12),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.bluetooth, label: Text('Bluetooth')),
                ButtonSegment(value: _Mode.usb, label: Text('USB')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() => _mode = s.first);
                _refresh();
              },
            ),
            const SizedBox(height: 12),
            if (_mode == _Mode.bluetooth)
              DropdownButtonFormField<int>(
                value: _baudRate,
                decoration: const InputDecoration(labelText: 'Baud rate'),
                items: const [
                  DropdownMenuItem(value: 9600, child: Text('9600')),
                  DropdownMenuItem(value: 19200, child: Text('19200')),
                  DropdownMenuItem(value: 115200, child: Text('115200')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _baudRate = v);
                },
              ),
            DropdownButtonFormField<PaperSize>(
              value: _paperSize,
              decoration: const InputDecoration(labelText: 'Paper'),
              items: const [
                DropdownMenuItem(value: PaperSize.mm58, child: Text('58mm')),
                DropdownMenuItem(value: PaperSize.mm80, child: Text('80mm')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _paperSize = v);
              },
            ),
            DropdownButtonFormField<String>(
              value: _selected,
              decoration: InputDecoration(
                labelText: _mode == _Mode.bluetooth ? 'COM port' : 'Printer',
              ),
              items: _destinations
                  .map(
                    (p) => DropdownMenuItem(value: p.name, child: Text(p.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selected = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _refresh,
              child: const Text('Refresh destinations'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _printTest,
              child: const Text('Print Bluetooth/USB test'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Bluetooth tip: pair the printer in Windows first. '
              'It should appear as COMx in Device Manager → Ports.',
            ),
          ],
        ),
      ),
    );
  }
}
