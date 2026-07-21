## 0.0.2

* Implement `TcpTransport` for LAN raw TCP (default port 9100) via `dart:io` Socket.
* Example app: LAN tab with IP/host, port, ready check, and test print (alongside Bluetooth).
* Unit test covers TCP send against a local `ServerSocket`.

## 0.0.1

* Initial `escpos_engine` package (shared ESC/POS core from windows_escpos_engine).
* Windows USB RAW transport (`UsbTransport` / WritePrinter).
* Windows Bluetooth via serial COM ports (`BluetoothTransport` / WriteFile).
* `TcpTransport` stub for future LAN (TCP 9100).
* Android / iOS plugin shells reserved for later native transports.
* Receipt pipeline: builder, encoder, profiles, asciiSafe, images, QR raster.
