/// Pure Dart support for [GoDice](https://particula-tech.com/godice) smart dice.
///
/// The library is transport-agnostic: it knows the GoDice BLE protocol
/// (service and characteristic UUIDs, command bytes and notification format),
/// how to turn accelerometer vectors into rolled values for every shell type,
/// and exposes a [GoDice] client that drives any [GoDiceTransport].
///
/// Use `package:godice_bluetooth_dart` for a ready-made transport on desktop
/// and mobile, or implement [GoDiceTransport] on top of the BLE plugin of your
/// choice (flutter_blue_plus, universal_ble, bluez, ...).
library;

export 'src/colors.dart';
export 'src/commands.dart';
export 'src/device_name.dart';
export 'src/die_type.dart';
export 'src/godice.dart';
export 'src/messages.dart';
export 'src/protocol.dart';
export 'src/shell.dart';
export 'src/transport.dart';
export 'src/vector3.dart';
