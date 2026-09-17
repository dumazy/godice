/// Cross-platform Bluetooth Low Energy for Dart and Flutter.
///
/// `bluetooth_dart` is pure Dart and has no Flutter dependency, so it works in
/// CLI tools as well as Flutter apps. Native BLE is reached over FFI (the Rust
/// `bluetooth_core` / btleplug library); see [BluetoothBackend] for the
/// pluggable backend contract and [Bluetooth] for the entry point.
library;

export 'src/backends/unsupported_backend.dart';
export 'src/bluetooth.dart';
export 'src/bluetooth_backend.dart';
export 'src/exceptions.dart';
export 'src/models.dart';
export 'src/peripheral.dart';
export 'src/scan.dart';
export 'src/web/web_browser.dart';
