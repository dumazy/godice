/// GoDice over `package:universal_ble`.
///
/// Provides [UniversalBleTransport], a `GoDiceTransport` for `package:godice`,
/// and [GoDiceScanner] to find nearby dice. Both are designed to coexist with
/// an app that already uses `universal_ble`: they only use its broadcast
/// streams (never the single-owner `onXxx` callbacks), scanning is left to
/// the app unless asked for, and a transport can attach to a connection the
/// app manages itself.
library;

export 'package:universal_ble/universal_ble.dart' show BleDevice;

export 'src/godice_universal_ble.dart';
export 'src/scanner.dart';
export 'src/transport.dart';
