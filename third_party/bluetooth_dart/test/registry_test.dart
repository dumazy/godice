import 'dart:typed_data';

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

/// A fake backend for exercising registry selection without hardware.
class _FakeBackend extends BluetoothBackend {
  _FakeBackend(this.name, this.priority, {this.isAvailable = true});

  @override
  final String name;
  @override
  final int priority;
  @override
  final bool isAvailable;

  @override
  Future<void> initialize() async {}
  @override
  Future<PermissionStatus> permissionStatus() async => PermissionStatus.granted;
  @override
  Future<PermissionStatus> requestPermission() async =>
      PermissionStatus.granted;
  @override
  Future<ScanSession> startScan({List<String> serviceUuids = const []}) =>
      throw UnimplementedError();
  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> disconnect(String deviceId) async {}
  @override
  Future<List<BleService>> discoverServices(String deviceId) async => const [];
  @override
  Future<Uint8List> readCharacteristic(String d, String c) async =>
      Uint8List(0);
  @override
  Future<void> writeCharacteristic(
    String d,
    String c,
    Uint8List v, {
    bool withResponse = true,
  }) async {}
  @override
  Stream<BleNotification> subscribe(String d, String c) => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  final bt = Bluetooth.instance;

  tearDown(() async => bt.reset());

  // Priorities are set above any real (e.g. ffi=100) backend that the registry
  // auto-registers on this host, so these assertions hold regardless of
  // platform.
  test('selects the highest-priority available backend', () {
    bt.registerBackend(_FakeBackend('low', 500));
    bt.registerBackend(_FakeBackend('high', 1000));
    expect(bt.backend.name, 'high');
  });

  test('skips unavailable backends', () {
    bt.registerBackend(_FakeBackend('off', 9999, isAvailable: false));
    bt.registerBackend(_FakeBackend('on', 1000));
    expect(bt.backend.name, 'on');
  });

  test('falls back to whatever real backend this host provides', () {
    // With no fake backends registered, selection must still succeed with the
    // host's real floor: `ffi` on a native host with the library, `web` in a
    // browser (Web Bluetooth), or `unsupported` when neither applies.
    expect(bt.backend.name, anyOf('ffi', 'web', 'unsupported'));
  });

  test('makeActive pins a backend regardless of priority', () {
    bt.registerBackend(_FakeBackend('high', 100));
    final pinned = _FakeBackend('pinned', 1);
    bt.registerBackend(pinned, makeActive: true);
    expect(bt.backend.name, 'pinned');
  });

  test('useBackend pins by name and throws for unknown names', () {
    bt.registerBackend(_FakeBackend('a', 5));
    bt.useBackend('a');
    expect(bt.backend.name, 'a');
    expect(
      () => bt.useBackend('nope'),
      throwsA(isA<NoBackendAvailableException>()),
    );
  });
}
