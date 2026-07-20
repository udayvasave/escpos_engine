/// High-level interface for sending ESC/POS jobs to a printer destination.
library;

import 'dart:typed_data';

import '../models/printer_profile.dart';
import '../platform/method_channel.dart';
import '../transport/transport.dart';
import 'printer_info.dart';

/// Represents a target printer destination (USB queue, COM port, etc.).
class Printer {
  Printer({
    required this.info,
    this.profile = PrinterProfile.generic80,
    Transport? transport,
  }) : _transport = transport ?? UsbTransport();

  final PrinterInfo info;
  final PrinterProfile profile;
  final Transport _transport;

  String get name => info.name;

  Future<void> send(Uint8List data) => _transport.send(name, data);

  Future<void> printRaw(Uint8List data) => send(data);
}
