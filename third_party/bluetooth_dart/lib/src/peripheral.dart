import 'dart:typed_data';

import 'bluetooth_backend.dart';
import 'models.dart';

/// A convenience handle to a single peripheral, wrapping the id-keyed backend
/// operations in an object-oriented surface.
///
/// Obtain one from `Bluetooth.peripheral(id)`. Methods delegate to the active
/// [BluetoothBackend]; the handle holds no native state of its own, so it stays
/// valid as long as the device id does.
class BlePeripheral {
  BlePeripheral(this._backend, this.id);

  final BluetoothBackend _backend;

  /// The peripheral id (a scanned [BleDevice.id]).
  final String id;

  /// Connects to the peripheral.
  Future<void> connect() => _backend.connect(id);

  /// Disconnects from the peripheral.
  Future<void> disconnect() => _backend.disconnect(id);

  /// Discovers and returns the peripheral's services and characteristics.
  Future<List<BleService>> discoverServices() => _backend.discoverServices(id);

  /// Reads a characteristic's current value.
  Future<Uint8List> read(String characteristicUuid) =>
      _backend.readCharacteristic(id, characteristicUuid);

  /// Writes [value] to a characteristic.
  Future<void> write(
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
  }) => _backend.writeCharacteristic(
    id,
    characteristicUuid,
    value,
    withResponse: withResponse,
  );

  /// Subscribes to a characteristic's notifications/indications.
  Stream<BleNotification> subscribe(String characteristicUuid) =>
      _backend.subscribe(id, characteristicUuid);

  /// This peripheral's connection-state changes: `true` on connect, `false` on
  /// disconnect (including unexpected ones). A filtered view of
  /// `Bluetooth.connectionStates`.
  Stream<bool> connectionState() => _backend.connectionStates
      .where((s) => s.deviceId == id)
      .map((s) => s.connected);
}
