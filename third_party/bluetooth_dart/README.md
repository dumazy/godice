# bluetooth_dart

Cross-platform Bluetooth Low Energy for Dart, wrapping the Rust
[`btleplug`](https://github.com/deviceplug/btleplug) library over `dart:ffi`.
Pure Dart, with no Flutter dependency, so it works in CLI tools as well as
Flutter apps (via [`bluetooth_flutter`](../bluetooth_flutter), which builds the
native library for you).

## Usage

```dart
import 'package:bluetooth_dart/bluetooth_dart.dart';

final bt = Bluetooth.instance;

// Request Bluetooth permission (prompts on macOS/iOS; no-op elsewhere).
if ((await bt.requestPermission()).isUsable) {
  // Scan; the stream emits a device on each discovery/advertisement update.
  final scan = await bt.startScan();
  scan.devices.listen((d) => print('${d.id}  ${d.name}  ${d.rssi} dBm'));
  await Future<void>.delayed(const Duration(seconds: 5));
  await scan.stop();

  // Connect and read a characteristic.
  final p = bt.peripheral(someDeviceId);
  await p.connect();
  final services = await p.discoverServices();
  final value = await p.read('00002a37-0000-1000-8000-00805f9b34fb');
  p.subscribe('00002a37-0000-1000-8000-00805f9b34fb').listen(print);
}
```

## The native library

`bluetooth_dart` loads `bluetooth_core` (the Rust crate) over FFI. It does not
build it: build it first, or use `bluetooth_flutter` which builds it
automatically via cargokit. Search order:

1. `NativeLibrary.overridePath` (set in Dart), then `$BLUETOOTH_CORE_LIB`.
2. The OS loader path / Flutter app bundle.
3. In-repo developer builds under `native/bluetooth_core/target/{release,debug}/`.

Build it with:

```sh
cargo build --manifest-path native/bluetooth_core/Cargo.toml
```

## Pluggable backends

The active `BluetoothBackend` is chosen from a registry by availability and
priority. The FFI backend is the default on native platforms; the web currently
falls through to an `UnsupportedBackend` floor (a Web Bluetooth backend is
planned). Register your own with `Bluetooth.instance.registerBackend(...)`.

## Status

| Host | Status |
|---|---|
| Android | Tested |
| Android Emulator | Tested |
| macOS | Tested |
| iOS | Tested |
| iOS Simulator | Tested |
| Ubuntu 24.04 | Tested |
| Web | Tested |
| Windows 11 | Tested |

Android, iOS, Ubuntu 24.04, Linux macOS, Web (on Chrome on macOS, on Chrome on 
Ubuntu 24.04, and on Chrome and Edge on Windows 11), and Windows 11 are tested.
