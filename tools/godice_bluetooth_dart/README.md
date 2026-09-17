# godice_bluetooth_dart

`GoDiceTransport` and scanner for `package:godice` built on
[`bluetooth_dart`](https://pub.dev/packages/bluetooth_dart), a pure Dart BLE
stack (Rust btleplug over FFI) that works in terminal programs and Flutter
apps on macOS, Linux, Windows, iOS and Android.

## Native library

`bluetooth_dart` loads `libbluetooth_core` at runtime. Build it once with a
Rust toolchain (see `tool/build_native.sh` in this repository, or the
`bluetooth_dart` README) and either run from inside this repo or set
`BLUETOOTH_CORE_LIB=/path/to/libbluetooth_core.dylib`.

This package is **not published**: it exists as a pure Dart hardware smoke
test for the core package. Flutter apps should use `godice_universal_ble`.

Note: `bluetooth_dart` 0.0.1 on pub.dev crashes when subscribing to
notifications on the Dart VM; this repository uses a vendored copy with a
fix (`third_party/bluetooth_dart`). Outside this workspace, apply the same
patch or wait for a fixed release.

## Usage

```dart
import 'package:godice/godice.dart';
import 'package:godice_bluetooth_dart/godice_bluetooth_dart.dart';

final scanner = GoDiceScanner();
final dice = await scanner.scan(timeout: const Duration(seconds: 5));
final die = GoDiceBluetoothDart.fromBleDevice(dice.first, dieType: DieType.d6);
await die.connect();
die.rolls.listen(print);
```

`GoDiceScanner.discover()` streams dice as they advertise, `find()` waits for
a die whose name or id matches, and `scan()` collects everything seen for a
fixed period.
