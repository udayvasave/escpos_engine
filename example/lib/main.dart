import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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

enum _Mode { bluetoothClassic, ble, lan, usb }

class _MyAppState extends State<MyApp> {
  _Mode _mode = _Mode.ble;
  int _baudRate = 9600;
  int _tcpPort = 9100;
  PaperSize _paperSize = PaperSize.mm58;
  bool _imageDither = true;

  final _lanHostController = TextEditingController();
  BleTransport? _bleTransport;

  List<PrinterInfo> _destinations = const [];
  String? _selected;
  String _status = 'Scan for BLE printers or refresh classic Bluetooth.';
  bool _busy = false;

  Uint8List? _pickedImageBytes;
  String? _pickedImageName;

  bool get _isWindows => Platform.isWindows;
  bool get _isAndroid => Platform.isAndroid;

  List<_Mode> get _availableModes {
    final modes = <_Mode>[_Mode.ble, _Mode.bluetoothClassic, _Mode.lan];
    if (_isWindows) modes.add(_Mode.usb);
    return modes;
  }

  EscposEngine get _engine {
    final profile = _paperSize == PaperSize.mm58
        ? PrinterProfile.generic58
        : PrinterProfile.generic80;

    switch (_mode) {
      case _Mode.bluetoothClassic:
        return EscposEngine(
          transport: BluetoothTransport(baudRate: _baudRate),
          profile: profile,
        );
      case _Mode.ble:
        _bleTransport ??= BleTransport();
        return EscposEngine(transport: _bleTransport, profile: profile);
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
    if (_mode == _Mode.ble) {
      final match = _destinations.where((p) => p.destination == _selected);
      return match.isNotEmpty ? match.first.destination : (_selected ?? '');
    }
    return _selected ?? '';
  }

  @override
  void initState() {
    super.initState();
    if (!_availableModes.contains(_mode)) {
      _mode = _availableModes.first;
    }
    _refresh();
  }

  @override
  void dispose() {
    _lanHostController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _status = 'No image selected');
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageName = file.name;
        _status = 'Image loaded: ${file.name} (${bytes.length} bytes)';
      });
    } catch (e) {
      setState(() => _status = 'Pick image error: $e');
    } finally {
      setState(() => _busy = false);
    }
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
      List<PrinterInfo> list;
      if (_mode == _Mode.ble) {
        _bleTransport ??= BleTransport();
        list = await _bleTransport!.scan();
      } else {
        list = await _engine.listPrinters();
      }

      setState(() {
        _destinations = list;
        _selected = list.isEmpty
            ? null
            : (list.any((p) => p.destination == _selected)
                ? _selected
                : list.first.destination);
        _status = list.isEmpty
            ? switch (_mode) {
                _Mode.bluetoothClassic => _isAndroid
                    ? 'No paired BT printers. Pair in Android Settings first.'
                    : 'No COM ports. Pair classic BT printer in Windows Settings.',
                _Mode.ble =>
                  'No BLE devices found. Turn printer on and scan again.',
                _Mode.usb => 'No USB printers found.',
                _Mode.lan => '',
              }
            : 'Found ${list.length} device(s)';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Refresh failed: ${e.message}');
    } on MissingPluginException {
      setState(() {
        _status =
            'Native plugin out of date. Stop the app (q), then run:\n'
            'flutter clean && flutter run -d windows';
      });
    } catch (e) {
      setState(() => _status = 'Refresh error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _checkReady() async {
    final dest = _destination;
    if (dest.isEmpty) {
      setState(() => _status = 'Select or scan for a device first');
      return;
    }
    setState(() => _busy = true);
    try {
      final ready = await _engine.isPrinterReady(dest);
      setState(() {
        _status = ready ? 'Ready → $dest' : 'Not reachable → $dest';
      });
    } catch (e) {
      setState(() => _status = 'Ready check error: $e');
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
            : 'Select a device first';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final modeLabel = switch (_mode) {
        _Mode.bluetoothClassic => 'Classic BT / $dest',
        _Mode.ble => 'BLE / $dest',
        _Mode.lan => 'LAN / $dest:$_tcpPort',
        _Mode.usb => 'USB / $dest',
      };
      final receipt = ReceiptBuilder(paperSize: _paperSize)
          .centerText('ESCPOS ENGINE', bold: true, widthScale: 2, heightScale: 2)
          .feed(1)
          .centerText(modeLabel)
          .text(switch (_mode) {
            _Mode.bluetoothClassic => 'Baud: $_baudRate',
            _Mode.ble => 'BLE GATT',
            _Mode.lan => 'TCP: $_tcpPort',
            _Mode.usb => 'USB RAW',
          })
          .feed(3)
          .build();
      await _engine.print(receipt, destination: dest, debugLogBytes: true);
      setState(() => _status = 'Print OK → $dest');
    } on PlatformException catch (e) {
      setState(() => _status = 'Print failed: ${e.message ?? e.code}');
    } catch (e) {
      setState(() => _status = 'Print error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _printImage({required bool withReceipt}) async {
    final dest = _destination;
    if (dest.isEmpty) {
      setState(() {
        _status = _mode == _Mode.lan
            ? 'Enter a LAN IP / host first'
            : 'Select a device first';
      });
      return;
    }
    final imageBytes = _pickedImageBytes;
    if (imageBytes == null) {
      setState(() => _status = 'Pick a PNG or JPG image first');
      return;
    }

    setState(() => _busy = true);
    try {
      if (withReceipt) {
        final receipt = ReceiptBuilder(paperSize: _paperSize)
            .image(
              imageBytes,
              maxWidthDots: _paperSize.widthDots,
              dither: _imageDither,
              center: true,
            )
            .feed(1)
            .centerText('LOGO TEST', bold: true)
            .text('Paper: ${_paperSize.name}')
            .text('Dither: $_imageDither')
            .feed(3)
            .build();
        await _engine.print(receipt, destination: dest, debugLogBytes: true);
      } else {
        await _engine.printImage(
          dest,
          imageBytes,
          paperSize: _paperSize,
          maxWidthDots: _paperSize.widthDots,
          dither: _imageDither,
          feedAfter: 3,
        );
      }
      setState(() {
        _status = withReceipt
            ? 'Logo + receipt printed → $dest'
            : 'Image printed → $dest';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Image print failed: ${e.message ?? e.code}');
    } catch (e) {
      setState(() => _status = 'Image print error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  String _modeLabel(_Mode mode) => switch (mode) {
        _Mode.bluetoothClassic => 'Classic BT',
        _Mode.ble => 'BLE',
        _Mode.lan => 'LAN',
        _Mode.usb => 'USB',
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('escpos_engine')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_status),
            const SizedBox(height: 12),
            SegmentedButton<_Mode>(
              segments: _availableModes
                  .map(
                    (m) => ButtonSegment(
                      value: m,
                      label: Text(_modeLabel(m)),
                    ),
                  )
                  .toList(),
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() => _mode = s.first);
                _refresh();
              },
            ),
            const SizedBox(height: 12),
            if (_mode == _Mode.bluetoothClassic && _isWindows)
              DropdownButtonFormField<int>(
                value: _baudRate,
                decoration: const InputDecoration(labelText: 'Baud rate (Windows COM)'),
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
              decoration: InputDecoration(
                labelText: 'Paper (${_paperSize.widthDots} dots wide)',
              ),
              items: const [
                DropdownMenuItem(value: PaperSize.mm58, child: Text('58mm (384 dots)')),
                DropdownMenuItem(value: PaperSize.mm80, child: Text('80mm (576 dots)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _paperSize = v);
              },
            ),
            if (_mode != _Mode.lan)
              DropdownButtonFormField<String>(
                value: _selected,
                decoration: InputDecoration(
                  labelText: switch (_mode) {
                    _Mode.bluetoothClassic =>
                      _isAndroid ? 'Paired printer' : 'COM port',
                    _Mode.ble => 'BLE device',
                    _Mode.usb => 'Printer',
                    _Mode.lan => '',
                  },
                ),
                items: _destinations
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.destination,
                        child: Text(
                          p.address != null && p.name != p.address
                              ? '${p.name} (${p.address})'
                              : p.name,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
            const SizedBox(height: 16),
            if (_mode == _Mode.lan)
              FilledButton(
                onPressed: _busy ? null : _checkReady,
                child: const Text('Check LAN ready'),
              )
            else if (_mode == _Mode.ble)
              FilledButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Scan BLE devices'),
              )
            else
              FilledButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh devices'),
              ),
            if (_mode == _Mode.ble) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _checkReady,
                child: const Text('Check BLE ready'),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _printTest,
              child: Text(
                switch (_mode) {
                  _Mode.bluetoothClassic => 'Print Classic BT test',
                  _Mode.ble => 'Print BLE test',
                  _Mode.lan => 'Print LAN test',
                  _Mode.usb => 'Print USB test',
                },
              ),
            ),
            const Divider(height: 32),
            Text(
              'Image / logo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dither (better for photos)'),
              subtitle: const Text('Off = sharp threshold for simple logos'),
              value: _imageDither,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _imageDither = v),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _pickedImageName ?? 'Pick PNG / JPG logo',
              ),
            ),
            if (_pickedImageBytes != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.grey.shade200,
                  padding: const EdgeInsets.all(8),
                  child: Image.memory(
                    _pickedImageBytes!,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _busy ? null : () => _printImage(withReceipt: false),
                child: const Text('Print image only'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : () => _printImage(withReceipt: true),
                child: const Text('Print logo + receipt'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              switch (_mode) {
                _Mode.bluetoothClassic => _isAndroid
                    ? 'Classic BT: pair the printer in Android Settings, then '
                        'Refresh. Uses RFCOMM/SPP (not BLE).'
                    : 'Classic BT: pair in Windows Settings. Printer appears as '
                        'COMx in Device Manager → Ports.',
                _Mode.ble => 'BLE: image uses same greyscale + dither pipeline as '
                    'USB. Pick paper size to auto-fit width.',
                _Mode.lan =>
                  'LAN: printer and PC/phone on same network, port 9100.',
                _Mode.usb =>
                  'USB: install printer in Windows, pick spooler queue name.',
              },
            ),
          ],
        ),
      ),
    );
  }
}
