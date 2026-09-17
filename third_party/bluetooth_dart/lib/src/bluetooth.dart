import 'backends/native/native_backend.dart';
import 'backends/unsupported_backend.dart';
import 'bluetooth_backend.dart';
import 'exceptions.dart';
import 'models.dart';
import 'peripheral.dart';
import 'scan.dart';

/// Entry point for Bluetooth LE.
///
/// `bluetooth_dart` keeps a registry of [BluetoothBackend]s and picks the best
/// available one for the current environment (highest [BluetoothBackend.priority]
/// among those whose [BluetoothBackend.isAvailable] is true). Apps can register
/// extra backends (e.g. a Web Bluetooth or platform-channel backend) or pin a
/// specific one.
///
/// ```dart
/// final bt = Bluetooth.instance;
/// if ((await bt.requestPermission()).isUsable) {
///   final scan = await bt.startScan();
///   scan.devices.listen((d) => print(d));
/// }
/// ```
class Bluetooth {
  Bluetooth._();

  /// The process-wide instance.
  static final Bluetooth instance = Bluetooth._();

  final List<BluetoothBackend> _backends = [];
  final Set<BluetoothBackend> _initialized = Set.identity();
  BluetoothBackend? _active;
  bool _defaultsRegistered = false;

  /// Registers the backends that ship with `bluetooth_dart`.
  ///
  /// Backends from outside packages (e.g. bluetooth_flutter, a Web Bluetooth
  /// backend) call [registerBackend] themselves; this seeds the always-present
  /// floor plus the platform's native (FFI) backend.
  void _ensureDefaults() {
    if (_defaultsRegistered) return;
    _defaultsRegistered = true;
    final native = createNativeBackend();
    if (native != null) registerBackend(native);
    registerBackend(UnsupportedBackend());
  }

  /// All registered backends, in registration order.
  List<BluetoothBackend> get backends {
    _ensureDefaults();
    return List.unmodifiable(_backends);
  }

  /// Adds [backend] to the registry.
  ///
  /// Pass [makeActive] to select it immediately regardless of priority.
  /// Re-registering an instance is a no-op.
  void registerBackend(BluetoothBackend backend, {bool makeActive = false}) {
    _ensureDefaults();
    if (!_backends.contains(backend)) _backends.add(backend);
    if (makeActive) {
      _active = backend;
    } else {
      // Force re-selection so a newly added, higher-priority backend wins.
      _active = null;
    }
  }

  /// The backend currently in use, selecting one on first access.
  BluetoothBackend get backend {
    _ensureDefaults();
    return _active ??= _select();
  }

  /// Pins a specific registered backend by [name].
  void useBackend(String name) {
    _ensureDefaults();
    final match = _backends.where((b) => b.name == name);
    if (match.isEmpty) {
      throw NoBackendAvailableException(
        'No backend named "$name" is registered.',
      );
    }
    _active = match.first;
  }

  BluetoothBackend _select() {
    final available = _backends.where((b) => b.isAvailable).toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    if (available.isEmpty) throw const NoBackendAvailableException();
    return available.first;
  }

  Future<BluetoothBackend> _ready() async {
    final b = backend;
    if (!_initialized.contains(b)) {
      await b.initialize();
      _initialized.add(b);
    }
    return b;
  }

  /// The current Bluetooth authorization status.
  Future<PermissionStatus> permissionStatus() async =>
      (await _ready()).permissionStatus();

  /// Requests Bluetooth authorization, prompting if not yet determined.
  Future<PermissionStatus> requestPermission() async =>
      (await _ready()).requestPermission();

  /// Starts scanning, returning a controllable [ScanSession].
  ///
  /// [serviceUuids], when non-empty, filters advertisements to those services.
  Future<ScanSession> startScan({List<String> serviceUuids = const []}) async =>
      (await _ready()).startScan(serviceUuids: serviceUuids);

  /// Returns a handle to operate on a peripheral by id (from a scanned
  /// [BleDevice.id]). The peripheral need not be connected yet.
  BlePeripheral peripheral(String id) => BlePeripheral(backend, id);

  /// Connection-state changes for any peripheral: connects and, importantly,
  /// unexpected disconnects. Empty on backends that cannot observe them.
  Stream<BleConnectionState> get connectionStates => backend.connectionStates;

  /// Bluetooth adapter power-state changes (is the radio on?), distinct from
  /// permission state. Empty on backends that cannot observe them.
  Stream<AdapterState> get adapterStates => backend.adapterStates;

  /// Disposes the active backend and clears selection/registry.
  ///
  /// Primarily for tests; after this the defaults are re-seeded on next use.
  Future<void> reset() async {
    for (final b in _initialized) {
      await b.dispose();
    }
    _initialized.clear();
    _backends.clear();
    _active = null;
    _defaultsRegistered = false;
  }
}
