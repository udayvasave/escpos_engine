import 'package:flutter/foundation.dart';

import 'src/escpos/encoder.dart';
import 'src/models/paper_size.dart';
import 'src/models/printer_profile.dart';
import 'src/platform/method_channel.dart';
import 'src/printer/printer.dart';
import 'src/printer/printer_info.dart';
import 'src/receipt/receipt.dart';
import 'src/receipt/receipt_builder.dart';
import 'src/text/ascii_safe.dart';
import 'src/transport/transport.dart';
import 'escpos_engine_platform_interface.dart';

export 'src/escpos/commands.dart';
export 'src/escpos/encoder.dart';
export 'src/image/dither.dart';
export 'src/image/image_converter.dart';
export 'src/models/paper_size.dart';
export 'src/models/printer_profile.dart';
export 'src/platform/method_channel.dart'
    show UsbTransport, BluetoothTransport, TcpTransport;
export 'src/printer/printer.dart';
export 'src/printer/printer_info.dart';
export 'src/receipt/receipt.dart';
export 'src/receipt/receipt_element.dart';
export 'src/receipt/receipt_builder.dart';
export 'src/text/ascii_safe.dart';
export 'src/transport/transport.dart';

/// Cross-platform ESC/POS printing engine.
///
/// Encode once with [ReceiptBuilder] / [EscPosEncoder], then send via a
/// [Transport]:
/// - [UsbTransport] — Windows spooler RAW (USB)
/// - [BluetoothTransport] — Windows COM/serial (paired BT SPP printers)
/// - [TcpTransport] — LAN raw TCP (port 9100)
class EscposEngine {
  EscposEngine({
    String? destination,
    PrinterProfile profile = PrinterProfile.generic80,
    Transport? transport,
    EscPosEncoder? encoder,
  })  : _destination = destination,
        _profile = profile,
        _transport = transport ?? UsbTransport(),
        _encoder = encoder ?? const EscPosEncoder();

  final String? _destination;
  final PrinterProfile _profile;
  final Transport _transport;
  final EscPosEncoder _encoder;

  Future<String?> getPlatformVersion() {
    return EscposEnginePlatform.instance.getPlatformVersion();
  }

  /// Lists destinations for the configured [Transport].
  Future<List<PrinterInfo>> listPrinters() => _transport.listPrinters();

  Future<bool> isPrinterReady(String destination) {
    return _transport.isPrinterReady(destination);
  }

  Printer printer(
    String destination, {
    PrinterProfile profile = PrinterProfile.generic80,
  }) {
    return Printer(
      info: PrinterInfo(name: destination),
      profile: profile,
      transport: _transport,
    );
  }

  Future<void> printRaw(String destination, Uint8List data) {
    return _transport.send(destination, data);
  }

  Future<Uint8List> encode(
    Receipt receipt, {
    PrinterProfile? profile,
  }) {
    return _encoder.encode(
      receipt,
      profile: profile ?? _profile,
    );
  }

  /// Encodes and prints a receipt to [destination]
  /// (USB queue name, COM port, etc.).
  Future<void> print(
    Receipt receipt, {
    String? destination,
    PrinterProfile? profile,
    int copies = 1,
    bool requireReady = false,
    bool debugLogBytes = false,
  }) async {
    final target = destination ?? _destination;
    if (target == null || target.isEmpty) {
      throw ArgumentError('destination is required to print a receipt');
    }
    if (copies < 1) {
      throw ArgumentError('copies must be >= 1');
    }
    if (requireReady && !await isPrinterReady(target)) {
      throw StateError('Printer "$target" is not ready');
    }

    final bytes = await encode(receipt, profile: profile);
    if (debugLogBytes) {
      debugPrint(
        '[escpos_engine] ${bytes.length} bytes: ${bytesToHexPreview(bytes)}',
      );
    }

    for (var i = 0; i < copies; i++) {
      await _transport.send(target, bytes);
    }
  }

  Future<void> printImage(
    String destination,
    Uint8List imageBytes, {
    PaperSize paperSize = PaperSize.mm80,
    int? maxWidthDots,
    bool dither = true,
    int threshold = 128,
    bool cut = false,
    int feedAfter = 2,
    int copies = 1,
  }) async {
    final builder = ReceiptBuilder(paperSize: paperSize)
      ..image(
        imageBytes,
        maxWidthDots: maxWidthDots,
        dither: dither,
        threshold: threshold,
      );
    if (feedAfter > 0) {
      builder.feed(feedAfter);
    }
    if (cut) {
      builder.cut();
    }
    await print(
      builder.build(),
      destination: destination,
      copies: copies,
      profile: _profile.copyWith(
        paperSize: paperSize,
        maxRasterWidthDots: maxWidthDots ?? paperSize.widthDots,
      ),
    );
  }

  ReceiptBuilder receiptBuilder({PaperSize paperSize = PaperSize.mm80}) {
    return ReceiptBuilder(paperSize: paperSize);
  }
}
