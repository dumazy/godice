import 'dart:typed_data';

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

/// Minimal fake backend that records calls for verification.
class _RecordingBackend extends BluetoothBackend {
  final List<String> calls = [];

  @override
  String get name => 'recording';
  @override
  bool get isAvailable => true;
  @override
  int get priority => 0;

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
  Future<void> connect(String deviceId) async {
    calls.add('connect:$deviceId');
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect:$deviceId');
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    calls.add('discoverServices:$deviceId');
    return const [];
  }

  @override
  Future<Uint8List> readCharacteristic(String d, String c) async {
    calls.add('read:$d:$c');
    return Uint8List.fromList([0x42]);
  }

  @override
  Future<void> writeCharacteristic(
    String d,
    String c,
    Uint8List v, {
    bool withResponse = true,
  }) async {
    calls.add('write:$d:$c:resp=$withResponse');
  }

  @override
  Stream<BleNotification> subscribe(String d, String c) {
    calls.add('subscribe:$d:$c');
    return const Stream.empty();
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late _RecordingBackend backend;
  late BlePeripheral peripheral;

  setUp(() {
    backend = _RecordingBackend();
    peripheral = BlePeripheral(backend, 'dev-1');
  });

  test('exposes the device id', () {
    expect(peripheral.id, 'dev-1');
  });

  test('connect delegates to the backend', () async {
    await peripheral.connect();
    expect(backend.calls, ['connect:dev-1']);
  });

  test('disconnect delegates to the backend', () async {
    await peripheral.disconnect();
    expect(backend.calls, ['disconnect:dev-1']);
  });

  test('discoverServices delegates to the backend', () async {
    final services = await peripheral.discoverServices();
    expect(services, isEmpty);
    expect(backend.calls, ['discoverServices:dev-1']);
  });

  test('read delegates to the backend', () async {
    final data = await peripheral.read('char-uuid');
    expect(data, [0x42]);
    expect(backend.calls, ['read:dev-1:char-uuid']);
  });

  test('write delegates to the backend with default withResponse', () async {
    await peripheral.write('char-uuid', Uint8List.fromList([1, 2]));
    expect(backend.calls, ['write:dev-1:char-uuid:resp=true']);
  });

  test('write passes withResponse=false when requested', () async {
    await peripheral.write(
      'char-uuid',
      Uint8List.fromList([1]),
      withResponse: false,
    );
    expect(backend.calls, ['write:dev-1:char-uuid:resp=false']);
  });

  test('subscribe delegates to the backend', () {
    final stream = peripheral.subscribe('char-uuid');
    expect(stream, isNotNull);
    expect(backend.calls, ['subscribe:dev-1:char-uuid']);
  });
}
