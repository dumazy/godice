import 'dart:typed_data';

import '../bluetooth_backend.dart';
import '../exceptions.dart';
import '../models.dart';
import '../scan.dart';

/// A backend that does nothing, present as the lowest-priority floor so the
/// registry never fails to select *something* (CI, headless, unsupported
/// platforms). Every operation reports that Bluetooth is unavailable rather
/// than crashing; scans yield no devices.
class UnsupportedBackend extends BluetoothBackend {
  @override
  String get name => 'unsupported';

  @override
  bool get isAvailable => true;

  @override
  int get priority => -1000;

  @override
  Future<void> initialize() async {}

  @override
  Future<PermissionStatus> permissionStatus() async =>
      PermissionStatus.unsupported;

  @override
  Future<PermissionStatus> requestPermission() async =>
      PermissionStatus.unsupported;

  @override
  Future<ScanSession> startScan({List<String> serviceUuids = const []}) async =>
      _EmptyScan();

  @override
  Future<void> connect(String deviceId) async => _unavailable();

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<List<BleService>> discoverServices(String deviceId) async =>
      _unavailable();

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async => _unavailable();

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
  }) async => _unavailable();

  @override
  Stream<BleNotification> subscribe(
    String deviceId,
    String characteristicUuid,
  ) => Stream.error(
    const NoBackendAvailableException('Bluetooth is unavailable here.'),
  );

  @override
  Future<void> dispose() async {}

  Never _unavailable() =>
      throw const NoBackendAvailableException('Bluetooth is unavailable here.');
}

class _EmptyScan implements ScanSession {
  bool _scanning = true;

  @override
  Stream<BleDevice> get devices => const Stream.empty();

  @override
  bool get isScanning => _scanning;

  @override
  Future<void> stop() async => _scanning = false;
}
