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

enum _Mode { bluetooth, lan, usb }

class _MyAppState extends State<MyApp> {
  _Mode _mode = _Mode.bluetooth;
  int _baudRate = 9600;
  int _tcpPort = 9100;
  PaperSize _paperSize = PaperSize.mm58;

  final _lanHostController = TextEditingController();

  List<PrinterInfo> _destinations = const [];
  String? _selected;
  String _status =
      'Pair your BT printer or enter a LAN IP, then print a test receipt.';
  bool _busy = false;

  EscposEngine get _engine {
    final profile = _paperSize == PaperSize.mm58
        ? PrinterProfile.generic58
        : PrinterProfile.generic80;

    switch (_mode) {
      case _Mode.bluetooth:
        return EscposEngine(
          transport: BluetoothTransport(baudRate: _baudRate),
          profile: profile,
        );
      case _Mode.lan:
        return EscposEngine(
          transport: TcpTransport(
            port: _tcpPort,
            knownHosts: _lanHostController.text.trim().isEmpty
                ? const []
                : [_lanHostController.text.trim()],
          ),
          profile: profile,
        );
      case _Mode.usb:
        return EscposEngine(transport: UsbTransport(), profile: profile);
    }
  }

  String get _destination {
    if (_mode == _Mode.lan) {
      return _lanHostController.text.trim();
    }
    return _selected ?? '';
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _lanHostController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_mode == _Mode.lan) {
      setState(() {
        _status = _lanHostController.text.trim().isEmpty
            ? 'Enter printer IP (same LAN). Default port 9100.'
            : 'LAN host: ${_lanHostController.text.trim()}:$_tcpPort';
        _busy = false;
      });
      return;
    }

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

  Future<void> _checkLanReady() async {
    final host = _lanHostController.text.trim();
    if (host.isEmpty) {
      setState(() => _status = 'Enter a LAN IP / host first');
      return;
    }
    setState(() => _busy = true);
    try {
      final ready = await _engine.isPrinterReady(host);
      setState(() {
        _status = ready
            ? 'LAN ready → $host:$_tcpPort'
            : 'LAN not reachable → $host:$_tcpPort';
      });
    } catch (e) {
      setState(() => _status = 'LAN check error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _printTest() async {
    final dest = _destination;
    if (dest.isEmpty) {
      setState(() {
        _status = _mode == _Mode.lan
            ? 'Enter a LAN IP / host first'
            : 'Select a destination first';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final modeLabel = switch (_mode) {
        _Mode.bluetooth => 'Bluetooth / $dest',
        _Mode.lan => 'LAN / $dest:$_tcpPort',
        _Mode.usb => 'USB / $dest',
      };
      final receipt = ReceiptBuilder(paperSize: _paperSize)
          .centerText('ESCPOS ENGINE', bold: true, widthScale: 2, heightScale: 2)
          .feed(1)
          .centerText(modeLabel)
          .text(switch (_mode) {
            _Mode.bluetooth => 'Baud: $_baudRate',
            _Mode.lan => 'TCP: $_tcpPort',
            _Mode.usb => 'USB RAW',
          })
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
        appBar: AppBar(title: const Text('escpos_engine — BT / LAN')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_status),
            const SizedBox(height: 12),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.bluetooth, label: Text('Bluetooth')),
                ButtonSegment(value: _Mode.lan, label: Text('LAN')),
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
            if (_mode == _Mode.lan) ...[
              TextField(
                controller: _lanHostController,
                decoration: const InputDecoration(
                  labelText: 'Printer IP / host',
                  hintText: '192.168.1.50',
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: '$_tcpPort',
                decoration: const InputDecoration(labelText: 'TCP port'),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final parsed = int.tryParse(v.trim());
                  if (parsed != null && parsed > 0 && parsed < 65536) {
                    setState(() => _tcpPort = parsed);
                  }
                },
              ),
            ],
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
            if (_mode != _Mode.lan)
              DropdownButtonFormField<String>(
                value: _selected,
                decoration: InputDecoration(
                  labelText:
                      _mode == _Mode.bluetooth ? 'COM port' : 'Printer',
                ),
                items: _destinations
                    .map(
                      (p) =>
                          DropdownMenuItem(value: p.name, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
            const SizedBox(height: 16),
            if (_mode == _Mode.lan)
              FilledButton(
                onPressed: _busy ? null : _checkLanReady,
                child: const Text('Check LAN ready'),
              )
            else
              FilledButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh destinations'),
              ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _printTest,
              child: Text(
                switch (_mode) {
                  _Mode.bluetooth => 'Print Bluetooth test',
                  _Mode.lan => 'Print LAN test',
                  _Mode.usb => 'Print USB test',
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(
              switch (_mode) {
                _Mode.bluetooth =>
                  'Bluetooth tip: pair the printer in Windows first. '
                      'It should appear as COMx in Device Manager → Ports.',
                _Mode.lan =>
                  'LAN tip: printer and PC must be on the same network. '
                      'Most ESC/POS printers listen on TCP 9100 (raw).',
                _Mode.usb =>
                  'USB tip: install the printer in Windows, then pick its '
                      'spooler queue name.',
              },
            ),
          ],
        ),
      ),
    );
  }
}
