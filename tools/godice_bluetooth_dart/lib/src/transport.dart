import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:godice/godice.dart';

/// A [GoDiceTransport] backed by `bluetooth_dart`.
class BluetoothDartTransport implements GoDiceTransport {
  /// Creates a transport for the peripheral with [deviceId] (a scanned
  /// `BleDevice.id`). Uses [Bluetooth.instance] unless [bluetooth] is given.
  BluetoothDartTransport(this.deviceId, {Bluetooth? bluetooth})
    : _bluetooth = bluetooth ?? Bluetooth.instance;

  /// The peripheral id this transport talks to.
  final String deviceId;

  final Bluetooth _bluetooth;
  late final BlePeripheral _peripheral = _bluetooth.peripheral(deviceId);

  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _connectionState =
      StreamController<bool>.broadcast();

  StreamSubscription<BleNotification>? _notifySub;
  StreamSubscription<bool>? _linkSub;
  bool _connected = false;
  bool _disposed = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Stream<bool> get connectionState => _connectionState.stream;

  @override
  Future<void> connect() async {
    _checkNotDisposed();
    if (_connected) return;

    // Watch for unexpected drops before connecting so none are missed.
    _linkSub ??= _peripheral.connectionState().listen(_onLinkChange);

    try {
      await _peripheral.connect();
      final services = await _peripheral.discoverServices();
      _ensureGoDiceService(services);
      _notifySub = _peripheral
          .subscribe(GoDiceProtocol.notifyCharacteristicUuid)
          .listen(
            (n) => _notifications.add(n.value),
            onError: (Object e, StackTrace s) => _notifications.addError(
              GoDiceTransportException('Notification stream failed', e),
            ),
          );
    } on BluetoothException catch (e) {
      await _teardown();
      throw GoDiceTransportException('Failed to connect to $deviceId', e);
    }

    _setConnected(true);
  }

  @override
  Future<void> disconnect() async {
    if (!_connected && _notifySub == null) return;
    await _teardown();
    try {
      await _peripheral.disconnect();
    } on BluetoothException {
      // Already gone; nothing to do.
    }
    _setConnected(false);
  }

  @override
  Future<void> write(Uint8List data) async {
    _checkNotDisposed();
    if (!_connected) {
      throw const GoDiceTransportException('Not connected');
    }
    try {
      await _peripheral.write(
        GoDiceProtocol.writeCharacteristicUuid,
        data,
        withResponse: true,
      );
    } on BluetoothException catch (e) {
      throw GoDiceTransportException('Write failed', e);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _linkSub?.cancel();
    _linkSub = null;
    await _notifications.close();
    await _connectionState.close();
  }

  void _onLinkChange(bool up) {
    if (!up && _connected) {
      // Unexpected drop: the OS closed the link for us.
      _notifySub?.cancel();
      _notifySub = null;
      _setConnected(false);
    }
  }

  Future<void> _teardown() async {
    await _notifySub?.cancel();
    _notifySub = null;
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectionState.isClosed) _connectionState.add(value);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('BluetoothDartTransport is disposed');
  }

  static void _ensureGoDiceService(List<BleService> services) {
    final hasService = services.any(
      (s) => s.uuid.toLowerCase() == GoDiceProtocol.serviceUuid,
    );
    if (!hasService) {
      throw const GoDiceTransportException(
        'Peripheral does not expose the GoDice service '
        '(${GoDiceProtocol.serviceUuid}); is this really a GoDice?',
      );
    }
  }
}

/// Convenience constructors that wire a [GoDice] to [BluetoothDartTransport].
extension GoDiceBluetoothDart on GoDice {
  /// Creates a (not yet connected) [GoDice] for a scanned [device].
  static GoDice fromBleDevice(
    BleDevice device, {
    DieType dieType = DieType.d6,
    Bluetooth? bluetooth,
  }) => GoDice(
    BluetoothDartTransport(device.id, bluetooth: bluetooth),
    dieType: dieType,
    name: device.name,
  );

  /// Creates a (not yet connected) [GoDice] for a known peripheral [deviceId].
  static GoDice fromDeviceId(
    String deviceId, {
    DieType dieType = DieType.d6,
    String? name,
    Bluetooth? bluetooth,
  }) => GoDice(
    BluetoothDartTransport(deviceId, bluetooth: bluetooth),
    dieType: dieType,
    name: name,
  );
}
