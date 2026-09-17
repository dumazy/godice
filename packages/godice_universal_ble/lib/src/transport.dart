import 'dart:async';
import 'dart:typed_data';

import 'package:godice/godice.dart';
import 'package:universal_ble/universal_ble.dart';

/// A [GoDiceTransport] backed by `universal_ble`.
///
/// With [ownsConnection] `true` (the default) the transport connects,
/// subscribes to notifications and tears everything down again on
/// [disconnect] / [dispose]. With `false` it attaches to a connection the app
/// manages itself: [connect] only verifies the link is up and subscribes if
/// nobody has yet, and [disconnect] never touches the BLE link or the
/// notification subscription.
class UniversalBleTransport implements GoDiceTransport {
  /// Creates a transport for the peripheral with [deviceId] (a
  /// `BleDevice.deviceId`).
  UniversalBleTransport(
    this.deviceId, {
    this.ownsConnection = true,
    this.connectTimeout = const Duration(seconds: 15),
  });

  /// The `universal_ble` device id.
  final String deviceId;

  /// Whether this transport manages the BLE connection (see class docs).
  final bool ownsConnection;

  /// How long [connect] waits for the link when [ownsConnection] is `true`.
  final Duration connectTimeout;

  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _connectionState =
      StreamController<bool>.broadcast();

  StreamSubscription<Uint8List>? _valueSub;
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

    // Listen before connecting so an early drop is not missed.
    _linkSub ??= UniversalBle.connectionStream(deviceId).listen(_onLinkChange);

    try {
      final state = await UniversalBle.getConnectionState(deviceId);
      if (state != BleConnectionState.connected) {
        if (!ownsConnection) {
          throw const GoDiceTransportException(
            'Device is not connected and this transport does not own the '
            'connection; connect it first or use ownsConnection: true',
          );
        }
        await UniversalBle.connect(deviceId, timeout: connectTimeout);
      }

      if (ownsConnection) {
        final services = await UniversalBle.discoverServices(deviceId);
        _ensureGoDiceService(services);
      }

      // Attach to the value stream first so nothing is lost between the
      // subscribe landing and our listener being in place.
      _valueSub = UniversalBle.characteristicValueStream(
        deviceId,
        GoDiceProtocol.notifyCharacteristicUuid,
      ).listen(_notifications.add);

      if (!UniversalBle.isSubscribed(
        deviceId,
        GoDiceProtocol.notifyCharacteristicUuid,
      )) {
        await UniversalBle.subscribeNotifications(
          deviceId,
          GoDiceProtocol.serviceUuid,
          GoDiceProtocol.notifyCharacteristicUuid,
        );
      }
    } on GoDiceTransportException {
      await _teardown();
      rethrow;
    } on Object catch (e) {
      await _teardown();
      throw GoDiceTransportException('Failed to connect to $deviceId', e);
    }

    _setConnected(true);
  }

  @override
  Future<void> disconnect() async {
    final wasUp = _connected || _valueSub != null;
    await _teardown();
    if (wasUp && ownsConnection) {
      try {
        await UniversalBle.unsubscribe(
          deviceId,
          GoDiceProtocol.serviceUuid,
          GoDiceProtocol.notifyCharacteristicUuid,
        );
      } on Object {
        // Link may already be gone.
      }
      try {
        await UniversalBle.disconnect(deviceId);
      } on Object {
        // Already disconnected.
      }
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
      await UniversalBle.write(
        deviceId,
        GoDiceProtocol.serviceUuid,
        GoDiceProtocol.writeCharacteristicUuid,
        data,
      );
    } on Object catch (e) {
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
      // The OS (or the app, in shared mode) dropped the link.
      _valueSub?.cancel();
      _valueSub = null;
      _setConnected(false);
    }
  }

  Future<void> _teardown() async {
    await _valueSub?.cancel();
    _valueSub = null;
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectionState.isClosed) _connectionState.add(value);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('UniversalBleTransport is disposed');
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
