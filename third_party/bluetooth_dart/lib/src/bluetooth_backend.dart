import 'dart:typed_data';

import 'models.dart';
import 'scan.dart';

/// A pluggable provider of Bluetooth LE capability for a platform/technique.
///
/// `bluetooth_dart` is deliberately backend-agnostic: native platforms and CLI
/// tools reach BLE over FFI (btleplug), the web can layer a Web Bluetooth
/// backend, and Flutter platforms may add channel-based backends. Several
/// backends can be registered at once; the active one is chosen by
/// [isAvailable] and [priority] (see `Bluetooth`).
abstract class BluetoothBackend {
  /// A short, stable identifier (e.g. `ffi`, `web`, `unsupported`).
  String get name;

  /// Whether this backend can run in the current environment.
  ///
  /// Should be cheap and side-effect free; consulted during selection. The FFI
  /// backend reports `false` when the native library cannot be loaded. This is
  /// independent of permission - access may still be denied at scan time.
  bool get isAvailable;

  /// Selection weight when multiple backends are available; higher wins.
  int get priority;

  /// Prepares the backend for use. Called once before the first operation.
  /// Must be idempotent.
  Future<void> initialize();

  /// The current Bluetooth authorization status.
  Future<PermissionStatus> permissionStatus();

  /// Requests Bluetooth authorization (prompting if not yet determined) and
  /// returns the resulting status. Re-requesting after a denial is safe but may
  /// not re-prompt; detect [PermissionStatus.denied] and direct the user to
  /// system settings.
  Future<PermissionStatus> requestPermission();

  /// Starts scanning for peripherals, returning a controllable [ScanSession]
  /// whose [ScanSession.devices] stream emits discovered/updated devices.
  ///
  /// [serviceUuids], when non-empty, filters advertisements to those services.
  Future<ScanSession> startScan({List<String> serviceUuids});

  /// Connects to a peripheral by [deviceId] (from a scanned [BleDevice.id]).
  Future<void> connect(String deviceId);

  /// Disconnects from a peripheral.
  Future<void> disconnect(String deviceId);

  /// Discovers and returns a peripheral's GATT services and characteristics.
  Future<List<BleService>> discoverServices(String deviceId);

  /// Reads a characteristic's current value.
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  );

  /// Writes [value] to a characteristic. [withResponse] selects an
  /// acknowledged (write-with-response) vs unacknowledged write.
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse,
  });

  /// Subscribes to a characteristic's notifications/indications, returned as a
  /// stream. Cancel the subscription to unsubscribe.
  Stream<BleNotification> subscribe(String deviceId, String characteristicUuid);

  /// A broadcast stream of connection-state changes for peripherals: connects
  /// and, importantly, unexpected disconnects.
  ///
  /// Defaults to an empty stream so backends that cannot observe connection
  /// changes need not implement it.
  Stream<BleConnectionState> get connectionStates => const Stream.empty();

  /// A broadcast stream of Bluetooth adapter power-state changes (is the radio
  /// on?), distinct from permission state.
  ///
  /// Defaults to an empty stream so backends that cannot observe adapter changes
  /// need not implement it.
  Stream<AdapterState> get adapterStates => const Stream.empty();

  /// Releases any global resources held by the backend.
  Future<void> dispose();
}
