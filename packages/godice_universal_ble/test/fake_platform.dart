import 'dart:async';
import 'dart:typed_data';

import 'package:godice/godice.dart';
import 'package:universal_ble/universal_ble.dart';

/// Minimal in-memory `universal_ble` platform for tests.
///
/// Implements just what the transport and scanner touch; everything else
/// throws through [noSuchMethod].
class FakeUniversalBlePlatform extends UniversalBlePlatform {
  final List<String> log = <String>[];
  final Map<String, BleConnectionState> states = <String, BleConnectionState>{};
  final Map<String, Set<String>> subscribed = <String, Set<String>>{};
  final List<Uint8List> writes = <Uint8List>[];
  bool scanning = false;
  bool exposeGoDiceService = true;
  AvailabilityState availability = AvailabilityState.poweredOn;

  /// Invoked after each write so tests can auto-reply.
  void Function(Uint8List data)? onWrite;

  void notify(String deviceId, List<int> data) => updateCharacteristicValue(
    deviceId,
    GoDiceProtocol.notifyCharacteristicUuid,
    Uint8List.fromList(data),
    null,
  );

  void dropLink(String deviceId) {
    states[deviceId] = BleConnectionState.disconnected;
    updateConnection(deviceId, false);
  }

  void advertise(String deviceId, String? name, {int rssi = -60}) =>
      updateScanResult(BleDevice(deviceId: deviceId, name: name, rssi: rssi));

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      availability;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    log.add('startScan');
    scanning = true;
  }

  @override
  Future<void> stopScan() async {
    log.add('stopScan');
    scanning = false;
  }

  @override
  Future<bool> isScanning() async => scanning;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    log.add('connect $deviceId');
    states[deviceId] = BleConnectionState.connected;
    // Deliver asynchronously like a real platform.
    scheduleMicrotask(() => updateConnection(deviceId, true));
  }

  @override
  Future<void> disconnect(String deviceId) async {
    log.add('disconnect $deviceId');
    states[deviceId] = BleConnectionState.disconnected;
    scheduleMicrotask(() => updateConnection(deviceId, false));
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      states[deviceId] ?? BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async {
    log.add('discover $deviceId');
    if (!exposeGoDiceService) return <BleService>[];
    return <BleService>[
      BleService(GoDiceProtocol.serviceUuid, <BleCharacteristic>[
        BleCharacteristic(
          GoDiceProtocol.writeCharacteristicUuid,
          <CharacteristicProperty>[CharacteristicProperty.write],
          <BleDescriptor>[],
        ),
        BleCharacteristic(
          GoDiceProtocol.notifyCharacteristicUuid,
          <CharacteristicProperty>[CharacteristicProperty.notify],
          <BleDescriptor>[],
        ),
      ]),
    ];
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    log.add('setNotifiable ${bleInputProperty.name}');
    final set = subscribed.putIfAbsent(deviceId, () => <String>{});
    if (bleInputProperty == BleInputProperty.disabled) {
      set.remove(characteristic);
    } else {
      set.add(characteristic);
    }
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    log.add('write $characteristic ${value.toList()}');
    writes.add(value);
    onWrite?.call(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
