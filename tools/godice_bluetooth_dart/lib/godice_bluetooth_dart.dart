/// GoDice over `package:bluetooth_dart`.
///
/// Provides [BluetoothDartTransport], a `GoDiceTransport` implementation, and
/// [GoDiceScanner] to find nearby dice. `bluetooth_dart` loads the
/// `bluetooth_core` native library over FFI; see the package README for how
/// to build or locate it.
library;

export 'package:bluetooth_dart/bluetooth_dart.dart' show BleDevice, Bluetooth;

export 'src/scanner.dart';
export 'src/transport.dart';
