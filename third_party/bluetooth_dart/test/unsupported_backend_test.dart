import 'dart:typed_data';

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

void main() {
  late UnsupportedBackend backend;

  setUp(() => backend = UnsupportedBackend());

  test('is always available at the lowest priority', () {
    expect(backend.isAvailable, isTrue);
    expect(backend.priority, lessThan(0));
  });

  test('reports permission as unsupported (usable)', () async {
    expect(await backend.permissionStatus(), PermissionStatus.unsupported);
    expect((await backend.requestPermission()).isUsable, isTrue);
  });

  test('scan yields no devices', () async {
    final scan = await backend.startScan();
    expect(scan.isScanning, isTrue);
    expect(await scan.devices.isEmpty, isTrue);
    await scan.stop();
    expect(scan.isScanning, isFalse);
  });

  test('connection and adapter state streams are empty by default', () async {
    expect(await backend.connectionStates.isEmpty, isTrue);
    expect(await backend.adapterStates.isEmpty, isTrue);
  });

  test('subscribe emits a NoBackendAvailableException error', () async {
    final stream = backend.subscribe('x', 'y');
    expect(
      stream,
      emitsError(isA<NoBackendAvailableException>()),
    );
  });

  test('operations report Bluetooth unavailable', () async {
    expect(
      () => backend.connect('x'),
      throwsA(isA<NoBackendAvailableException>()),
    );
    expect(
      () => backend.discoverServices('x'),
      throwsA(isA<NoBackendAvailableException>()),
    );
    expect(
      () => backend.readCharacteristic('x', 'y'),
      throwsA(isA<NoBackendAvailableException>()),
    );
    expect(
      () => backend.writeCharacteristic('x', 'y', Uint8List(0)),
      throwsA(isA<NoBackendAvailableException>()),
    );
  });
}
