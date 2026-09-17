@TestOn('vm')
@Timeout(Duration(seconds: 120))
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

/// Hardware integration test for the full GATT loop against a real reference
/// peripheral: scan -> connect -> discover -> (subscribe -> write -> notify).
///
/// `bluetooth_dart` is a BLE *central*; it cannot be its own peripheral, so this
/// needs a second device acting as a GATT server. It is skipped unless
/// `BLE_TEST_DEVICE` is set, so `dart test` / CI stay green without hardware.
///
/// Build the native library first, then run with the target's advertised name:
///
/// ```sh
/// cargo build --manifest-path native/bluetooth_core/Cargo.toml
/// BLE_TEST_DEVICE="MyDevice" BLE_TEST_ECHO=1 \
///   dart test packages/bluetooth_dart/test/integration/nus_echo_test.dart
/// ```
///
/// See `test/integration/README.md` for peripheral setup and all env vars.

// Nordic UART Service (NUS) defaults, a common simple bidirectional profile.
const _nusService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _nusWrite =
    '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // RX: central -> server
const _nusNotify =
    '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // TX: server -> central

String? _env(String key) {
  final value = Platform.environment[key];
  return (value == null || value.isEmpty) ? null : value;
}

void main() {
  final target = _env('BLE_TEST_DEVICE');
  if (target == null) {
    test('GATT hardware integration', () {}, skip: _skipReason);
    return;
  }

  final serviceUuid = _env('BLE_TEST_SERVICE') ?? _nusService;
  final writeChar = _env('BLE_TEST_WRITE_CHAR') ?? _nusWrite;
  final notifyChar = _env('BLE_TEST_NOTIFY_CHAR') ?? _nusNotify;
  final expectEcho = const {
    '1',
    'true',
    'yes',
  }.contains((_env('BLE_TEST_ECHO') ?? '').toLowerCase());

  final bt = Bluetooth.instance;
  tearDown(() async => bt.reset());

  test(
    'scan -> connect -> discover${expectEcho ? ' -> echo round-trip' : ''}',
    () async {
      // The real FFI backend must be active (native lib built + adapter present).
      expect(
        bt.backend.name,
        'ffi',
        reason:
            'Native backend not active (got "${bt.backend.name}"). Build the lib '
            'first: cargo build --manifest-path native/bluetooth_core/Cargo.toml',
      );

      final permission = await bt.requestPermission();
      expect(
        permission.isUsable,
        isTrue,
        reason: 'Bluetooth permission not usable: $permission',
      );

      // 1. Scan (unfiltered) and match the target by name substring or id.
      print('Scanning for "$target" (up to 20s)...');
      final device = await _findDevice(bt, target);
      expect(
        device,
        isNotNull,
        reason: 'No device matching "$target" was seen while scanning.',
      );
      print(
        'Found ${device!.name ?? '(unknown)'}  ${device.id}  ${device.rssi} dBm',
      );

      final peripheral = bt.peripheral(device.id);
      final connectionStates = <bool>[];
      final connSub = peripheral.connectionState().listen(connectionStates.add);

      try {
        // 2. Connect.
        print('Connecting...');
        await peripheral.connect();

        // 3. Discover services and print the GATT table.
        final services = await peripheral.discoverServices();
        expect(services, isNotEmpty, reason: 'No GATT services discovered.');
        print('Discovered ${services.length} service(s):');
        for (final s in services) {
          print('  service ${s.uuid}');
          for (final c in s.characteristics) {
            print('    char ${c.uuid}  [${c.properties.join(', ')}]');
          }
        }

        // The connect event should have been observed.
        expect(
          connectionStates,
          contains(true),
          reason: 'connectionState() never reported connected.',
        );

        if (!expectEcho) {
          print(
            'Discovery OK. Set BLE_TEST_ECHO=1 with an echo peripheral to also '
            'test the write/notify round-trip.',
          );
          return;
        }

        // 4. Locate the NUS (or configured) characteristics.
        final service = services.firstWhere(
          (s) => s.uuid.toLowerCase() == serviceUuid.toLowerCase(),
          orElse: () => throw TestFailure(
            'Service $serviceUuid not found among: '
            '${services.map((s) => s.uuid).join(', ')}',
          ),
        );
        final write = service.characteristics.firstWhere(
          (c) => c.uuid.toLowerCase() == writeChar.toLowerCase(),
          orElse: () =>
              throw TestFailure('Write characteristic $writeChar not found.'),
        );
        final notify = service.characteristics.firstWhere(
          (c) => c.uuid.toLowerCase() == notifyChar.toLowerCase(),
          orElse: () =>
              throw TestFailure('Notify characteristic $notifyChar not found.'),
        );
        expect(write.canWrite, isTrue, reason: '$writeChar is not writable.');
        expect(
          notify.canNotify,
          isTrue,
          reason: '$notifyChar does not notify/indicate.',
        );

        // 5. Subscribe before writing, then write a payload.
        final firstNotification = Completer<Uint8List>();
        final notifSub = peripheral
            .subscribe(notify.uuid)
            .listen(
              (n) {
                if (!firstNotification.isCompleted) {
                  firstNotification.complete(n.value);
                }
              },
              onError: (Object e) {
                if (!firstNotification.isCompleted) {
                  firstNotification.completeError(e);
                }
              },
            );
        // Let the subscription register on the peripheral before writing.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final payload = Uint8List.fromList('echo-test'.codeUnits);
        print('Writing ${_hex(payload)} to $writeChar...');
        await peripheral.write(
          write.uuid,
          payload,
          withResponse: write.properties.contains('write'),
        );

        // 6. Await the echoed notification and assert it round-tripped.
        final received = await firstNotification.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TestFailure(
            'No notification on $notifyChar within 10s of writing. Is the '
            'peripheral echoing writes back as notifications?',
          ),
        );
        print('Received ${_hex(received)}');
        expect(
          received,
          orderedEquals(payload),
          reason:
              'Echo mismatch: wrote ${_hex(payload)}, got ${_hex(received)}.',
        );

        await notifSub.cancel();
      } finally {
        await connSub.cancel();
        await peripheral.disconnect();
      }
    },
  );
}

/// Scans (unfiltered) until a device whose id equals, or name contains,
/// [target] (case-insensitive) appears, or 20s elapse.
Future<BleDevice?> _findDevice(Bluetooth bt, String target) async {
  final lower = target.toLowerCase();
  bool matches(BleDevice d) =>
      d.id.toLowerCase() == lower ||
      (d.name?.toLowerCase().contains(lower) ?? false);

  final scan = await bt.startScan();
  final found = Completer<BleDevice?>();
  final sub = scan.devices.listen((d) {
    if (matches(d) && !found.isCompleted) found.complete(d);
  });
  final device = await found.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => null,
  );
  await sub.cancel();
  await scan.stop();
  return device;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

const _skipReason =
    'Hardware integration test. Set BLE_TEST_DEVICE to a reference '
    "peripheral's advertised name (or id) to run; see "
    'test/integration/README.md.';
