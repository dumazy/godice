// Scans for nearby BLE devices from the command line using `bluetooth_dart`
// (pure Dart, no Flutter).
//
// Build the native library first:
//   cargo build --manifest-path native/bluetooth_core/Cargo.toml
// then, from the repo root:
//   dart run packages/bluetooth_dart/example/bluetooth_example.dart [seconds]
//
// If the library is elsewhere, point to it with BLUETOOTH_CORE_LIB, e.g.
// libbluetooth_core.so (Linux), libbluetooth_core.dylib (macOS), or
// bluetooth_core.dll (Windows).

import 'package:bluetooth_dart/bluetooth_dart.dart';

Future<void> main(List<String> args) async {
  final seconds = int.tryParse(args.isEmpty ? '' : args.first) ?? 5;
  final bt = Bluetooth.instance;

  print('Active backend: ${bt.backend.name}');

  final status = await bt.requestPermission();
  print('Permission: ${status.name}');
  if (!status.isUsable) {
    print('Bluetooth is not usable (${status.name}); exiting.');
    return;
  }

  print('Scanning for ${seconds}s...');
  final seen = <String, BleDevice>{};
  final scan = await bt.startScan();
  final sub = scan.devices.listen((d) => seen[d.id] = d);

  await Future<void>.delayed(Duration(seconds: seconds));
  await sub.cancel();
  await scan.stop();

  final devices = seen.values.toList()
    ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
  print('\nFound ${devices.length} device(s):');
  for (final d in devices) {
    print(
      '  ${(d.rssi?.toString() ?? '?').padLeft(4)} dBm  '
      '${d.id}  ${d.name ?? '(unknown)'}',
    );
  }
}
