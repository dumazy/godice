import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../bluetooth_backend.dart';
import '../../exceptions.dart';
import '../../models.dart';
import '../../scan.dart';

/// The default native backend on platforms with `dart:ffi`.
BluetoothBackend? createNativeBackend() => FfiBackend();

// --- C ABI signatures, mirroring native/bluetooth_core/src/lib.rs ------------

typedef _IntVoidNative = Int32 Function();
typedef _IntVoid = int Function();
typedef _SessionNewNative = Pointer<Void> Function();
typedef _SessionFreeNative = Void Function(Pointer<Void>);
typedef _SessionFree = void Function(Pointer<Void>);
typedef _StartScanNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _StartScan = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _StopScanNative = Int32 Function(Pointer<Void>);
typedef _StopScan = int Function(Pointer<Void>);
typedef _PollEventNative = IntPtr Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _PollEvent = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _IdOpNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _IdOp = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _DiscoverNative =
    IntPtr Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Size);
typedef _Discover =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, int);
typedef _ReadNative =
    IntPtr Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      Size,
    );
typedef _Read =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      int,
    );
typedef _WriteNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      Size,
      Int32,
    );
typedef _Write =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      int,
      int,
    );
typedef _SubOpNative =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SubOp = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastError = Pointer<Utf8> Function();

/// Locates and opens the `bluetooth_core` shared library.
class NativeLibrary {
  /// Explicit path override, highest priority. Set before first use.
  static String? overridePath;

  static DynamicLibrary? _opened;
  static bool _attempted = false;

  static String get _fileName => switch (Platform.operatingSystem) {
    'windows' => 'bluetooth_core.dll',
    'macos' || 'ios' => 'libbluetooth_core.dylib',
    _ => 'libbluetooth_core.so',
  };

  /// Opens the library, caching the result. Returns `null` if it cannot be
  /// found/loaded - never throws.
  static DynamicLibrary? open() {
    if (_attempted) return _opened;
    _attempted = true;
    for (final candidate in _candidates()) {
      try {
        _opened = DynamicLibrary.open(candidate);
        return _opened;
      } on Object {
        // Try the next candidate.
      }
    }
    // On Apple platforms the symbols are -force_load'd into the plugin's
    // framework, which is loaded into the host process for us - so process()
    // resolves them even when DynamicLibrary.open cannot find the framework
    // path directly.
    if (Platform.isMacOS || Platform.isIOS) {
      try {
        final p = DynamicLibrary.process();
        // Probe one expected symbol so we know FFI can actually find it.
        p.lookup<NativeFunction<_SessionNewNative>>('bt_session_new');
        _opened = p;
      } on Object {
        // Fall through.
      }
    }
    return _opened;
  }

  static Iterable<String> _candidates() sync* {
    if (overridePath != null) yield overridePath!;
    final fromEnv = Platform.environment['BLUETOOTH_CORE_LIB'];
    if (fromEnv != null && fromEnv.isNotEmpty) yield fromEnv;
    // Resolved via the OS loader path / Flutter app bundle.
    yield _fileName;
    // On macOS/iOS the symbols are -force_load'd into the plugin's framework,
    // so the lib name lookup above fails. The Flutter loader resolves the
    // framework binary by its short path.
    if (Platform.isMacOS || Platform.isIOS) {
      yield 'bluetooth_flutter.framework/bluetooth_flutter';
    }
    // Developer builds of the in-repo crate, searched from the cwd upward.
    var dir = Directory.current.absolute;
    for (var i = 0; i < 6; i++) {
      for (final profile in ['release', 'debug']) {
        yield '${dir.path}/native/bluetooth_core/target/$profile/$_fileName';
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
}

/// Bound entry points into the native library.
class _Bindings {
  _Bindings(DynamicLibrary lib)
    : permissionStatus = lib.lookupFunction<_IntVoidNative, _IntVoid>(
        'bt_permission_status',
      ),
      requestPermission = lib.lookupFunction<_IntVoidNative, _IntVoid>(
        'bt_request_permission',
      ),
      sessionNew = lib.lookupFunction<_SessionNewNative, _SessionNewNative>(
        'bt_session_new',
      ),
      sessionFree = lib.lookupFunction<_SessionFreeNative, _SessionFree>(
        'bt_session_free',
      ),
      startScan = lib.lookupFunction<_StartScanNative, _StartScan>(
        'bt_start_scan',
      ),
      stopScan = lib.lookupFunction<_StopScanNative, _StopScan>('bt_stop_scan'),
      pollEvent = lib.lookupFunction<_PollEventNative, _PollEvent>(
        'bt_session_poll_event',
      ),
      connect = lib.lookupFunction<_IdOpNative, _IdOp>('bt_connect'),
      disconnect = lib.lookupFunction<_IdOpNative, _IdOp>('bt_disconnect'),
      discoverServices = lib.lookupFunction<_DiscoverNative, _Discover>(
        'bt_discover_services',
      ),
      read = lib.lookupFunction<_ReadNative, _Read>('bt_read'),
      write = lib.lookupFunction<_WriteNative, _Write>('bt_write'),
      subscribe = lib.lookupFunction<_SubOpNative, _SubOp>('bt_subscribe'),
      unsubscribe = lib.lookupFunction<_SubOpNative, _SubOp>('bt_unsubscribe'),
      lastError = lib.lookupFunction<_LastErrorNative, _LastError>(
        'bt_last_error',
      );

  final _IntVoid permissionStatus;
  final _IntVoid requestPermission;
  final Pointer<Void> Function() sessionNew;
  final _SessionFree sessionFree;
  final _StartScan startScan;
  final _StopScan stopScan;
  final _PollEvent pollEvent;
  final _IdOp connect;
  final _IdOp disconnect;
  final _Discover discoverServices;
  final _Read read;
  final _Write write;
  final _SubOp subscribe;
  final _SubOp unsubscribe;
  final _LastError lastError;
}

/// Reaches native BLE by calling the `bluetooth_core` library over FFI.
///
/// A single session is created on [initialize]; scans and peripheral ops all
/// run against it. The native event queue (discoveries + notifications) is
/// drained by a single polling [Timer] and fanned out to the active scan and to
/// notification streams, mirroring the sibling `microphone` backend.
class FfiBackend extends BluetoothBackend {
  _Bindings? _bindings;
  Pointer<Void> _session = nullptr;
  bool _available = false;
  bool _probed = false;

  // Output buffer for poll/read/discover. 64 KiB comfortably holds a poll event
  // or a services blob; reads of larger payloads reallocate as needed.
  static const int _bufCap = 64 * 1024;
  Pointer<Uint8> _buf = nullptr;

  Timer? _poll;
  _FfiScan? _scan;
  // Notification fan-out keyed by "deviceId|characteristicUuid".
  final Map<String, StreamController<BleNotification>> _notifs = {};

  // Connection- and adapter-state fan-out. Listening to either keeps the event
  // drain running (via onListen) so unexpected disconnects/power changes are
  // delivered even when not scanning or subscribed.
  late final StreamController<BleConnectionState> _connStates =
      StreamController<BleConnectionState>.broadcast(
        onListen: _ensurePolling,
        onCancel: _maybeStopPolling,
      );
  late final StreamController<AdapterState> _adapterStates =
      StreamController<AdapterState>.broadcast(
        onListen: _ensurePolling,
        onCancel: _maybeStopPolling,
      );

  @override
  String get name => 'ffi';

  @override
  int get priority => 100;

  @override
  Stream<BleConnectionState> get connectionStates => _connStates.stream;

  @override
  Stream<AdapterState> get adapterStates => _adapterStates.stream;

  @override
  bool get isAvailable {
    if (_probed) return _available;
    _probed = true;
    final lib = NativeLibrary.open();
    if (lib == null) return _available = false;
    try {
      _bindings = _Bindings(lib);
      _available = true;
    } on Object {
      _available = false;
    }
    return _available;
  }

  String _lastError() {
    final ptr = _bindings!.lastError();
    return ptr == nullptr ? 'unknown error' : ptr.toDartString();
  }

  @override
  Future<void> initialize() async {
    if (!isAvailable) {
      throw const NoBackendAvailableException(
        'The bluetooth_core library could not be loaded.',
      );
    }
    if (_session != nullptr) return;
    _session = _bindings!.sessionNew();
    if (_session == nullptr) {
      throw BleException('bt_session_new failed: ${_lastError()}');
    }
    _buf = malloc<Uint8>(_bufCap);
  }

  @override
  Future<PermissionStatus> permissionStatus() async {
    if (!isAvailable) return PermissionStatus.unsupported;
    return PermissionStatus.fromCode(_bindings!.permissionStatus());
  }

  @override
  Future<PermissionStatus> requestPermission() async {
    if (!isAvailable) return PermissionStatus.unsupported;
    return PermissionStatus.fromCode(_bindings!.requestPermission());
  }

  @override
  Future<ScanSession> startScan({List<String> serviceUuids = const []}) async {
    if (_session == nullptr) await initialize();
    final status = await permissionStatus();
    if (!status.isUsable && status == PermissionStatus.denied) {
      throw const PermissionDeniedException();
    }
    // One scan at a time; replace any prior one.
    await _scan?.stop();
    final filter = serviceUuids.isEmpty
        ? nullptr
        : jsonEncode(serviceUuids).toNativeUtf8();
    try {
      final rc = _bindings!.startScan(_session, filter.cast());
      if (rc != 0) {
        throw BleException('start scan failed: ${_lastError()}');
      }
    } finally {
      if (filter != nullptr) malloc.free(filter);
    }
    final scan = _FfiScan(this);
    _scan = scan;
    _ensurePolling();
    return scan;
  }

  /// Starts the single drain timer if it is not already running.
  void _ensurePolling() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 50), (_) => _drain());
  }

  /// Stops polling when nothing needs events anymore: no active scan, no
  /// subscriptions, and nobody listening for connection/adapter changes.
  void _maybeStopPolling() {
    final scanning = _scan != null && _scan!.isScanning;
    if (!scanning &&
        _notifs.isEmpty &&
        !_connStates.hasListener &&
        !_adapterStates.hasListener) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Drains all queued native events and dispatches them.
  void _drain() {
    if (_session == nullptr) return;
    while (true) {
      final n = _bindings!.pollEvent(_session, _buf, _bufCap);
      if (n <= 0) break; // 0 empty, -1 error (surfaced on the next op)
      final bytes = _buf.asTypedList(n);
      final Map<String, dynamic> event;
      try {
        event = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } on Object {
        continue; // skip a malformed event rather than tear down the timer
      }
      _dispatch(event);
    }
  }

  void _dispatch(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'device':
        final device = BleDevice.fromJson(
          event['device'] as Map<String, dynamic>,
        );
        _scan?.add(device);
      case 'notification':
        final key = '${event['id']}|${event['characteristic']}';
        final controller = _notifs[key];
        if (controller != null && !controller.isClosed) {
          controller.add(
            BleNotification(
              deviceId: event['id'] as String,
              characteristic: event['characteristic'] as String,
              value: Uint8List.fromList(
                (event['value'] as List)
                    .map((e) => (e as num).toInt())
                    .toList(),
              ),
            ),
          );
        }
      case 'connected':
        if (!_connStates.isClosed) {
          _connStates.add(
            BleConnectionState(
              deviceId: event['id'] as String,
              connected: true,
            ),
          );
        }
      case 'disconnected':
        if (!_connStates.isClosed) {
          _connStates.add(
            BleConnectionState(
              deviceId: event['id'] as String,
              connected: false,
            ),
          );
        }
      case 'state_update':
        if (!_adapterStates.isClosed) {
          _adapterStates.add(
            AdapterState.fromNative(event['state'] as String? ?? 'unknown'),
          );
        }
    }
  }

  /// Stops the native scan and clears the active scan reference. Called by the
  /// [ScanSession] this backend hands out; accepts the public type to keep the
  /// API free of private types.
  Future<void> stopScanInternal(ScanSession scan) async {
    if (identical(_scan, scan)) {
      _bindings!.stopScan(_session);
      _scan = null;
    }
    _maybeStopPolling();
  }

  // Connect/discover/read/write/(un)subscribe each `block_on` an async btleplug
  // call in the native layer, so they can take seconds (connect) or, on an
  // unresponsive peripheral, the full native timeout. Running them on the Dart
  // main isolate would freeze the UI, so they are dispatched to a short-lived
  // worker isolate via [Isolate.run]; the native session pointer travels as its
  // integer address. The native timeouts (see `session.rs`) guarantee these
  // calls, and thus the worker isolates, always return.

  @override
  Future<void> connect(String deviceId) async {
    if (_session == nullptr) await initialize();
    final addr = _session.address;
    final err = await Isolate.run(
      () => _isoVoidOp((addr, _Op.connect, deviceId, null, null, false)),
    );
    if (err != null) throw BleException(err);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    if (_session == nullptr) await initialize();
    final addr = _session.address;
    final err = await Isolate.run(
      () => _isoVoidOp((addr, _Op.disconnect, deviceId, null, null, false)),
    );
    if (err != null) throw BleException(err);
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    if (_session == nullptr) await initialize();
    final addr = _session.address;
    final (json, err) = await Isolate.run(() => _isoDiscover((addr, deviceId)));
    if (err != null) throw BleException(err);
    final list = jsonDecode(json!) as List;
    return list
        .map((e) => BleService.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    if (_session == nullptr) await initialize();
    final addr = _session.address;
    final (bytes, err) = await Isolate.run(
      () => _isoRead((addr, deviceId, characteristicUuid)),
    );
    if (err != null) throw BleException(err);
    return bytes!;
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
  }) async {
    if (_session == nullptr) await initialize();
    final addr = _session.address;
    final err = await Isolate.run(
      () => _isoVoidOp((
        addr,
        _Op.write,
        deviceId,
        characteristicUuid,
        value,
        withResponse,
      )),
    );
    if (err != null) throw BleException(err);
  }

  @override
  Stream<BleNotification> subscribe(
    String deviceId,
    String characteristicUuid,
  ) {
    final key = '$deviceId|$characteristicUuid';
    final existing = _notifs[key];
    if (existing != null) return existing.stream;

    late final StreamController<BleNotification> controller;
    controller = StreamController<BleNotification>.broadcast(
      onListen: () async {
        if (_session == nullptr) {
          controller.addError(
            const BleException('session not initialized; scan first'),
          );
          return;
        }
        // Start draining now so notifications flow as soon as the subscribe
        // lands; the native call itself runs off the main isolate.
        _ensurePolling();
        final err = await _runVoidOp(
          _session.address,
          _Op.subscribe,
          deviceId,
          characteristicUuid,
        );
        if (err != null && !controller.isClosed) {
          controller.addError(BleException(err));
        }
      },
      onCancel: () async {
        _notifs.remove(key);
        if (_session != nullptr) {
          await _runVoidOp(
            _session.address,
            _Op.unsubscribe,
            deviceId,
            characteristicUuid,
          );
        }
        _maybeStopPolling();
      },
    );
    _notifs[key] = controller;
    return controller.stream;
  }

  /// Runs a subscribe/unsubscribe op on a worker isolate.
  ///
  /// This is a static method on purpose: an `Isolate.run` closure created
  /// inside `subscribe` would share that method's context, which captures the
  /// stream controller and `this` (and with it the `_poll` Timer), and the
  /// isolate message serialiser rejects Timers as unsendable. A static helper
  /// only captures its own parameters. (go_dice patch, see PATCHES.md)
  static Future<String?> _runVoidOp(
    int addr,
    _Op op,
    String deviceId,
    String characteristicUuid,
  ) => Isolate.run(
    () => _isoVoidOp((addr, op, deviceId, characteristicUuid, null, false)),
  );

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    _poll = null;
    await _scan?.stop();
    for (final c in _notifs.values) {
      await c.close();
    }
    _notifs.clear();
    await _connStates.close();
    await _adapterStates.close();
    if (_session != nullptr) {
      _bindings!.sessionFree(_session);
      _session = nullptr;
    }
    if (_buf != nullptr) {
      malloc.free(_buf);
      _buf = nullptr;
    }
  }
}

/// The [ScanSession] returned by [FfiBackend]; a thin view over the backend's
/// shared event drain.
class _FfiScan implements ScanSession {
  _FfiScan(this._backend);

  final FfiBackend _backend;
  final StreamController<BleDevice> _controller =
      StreamController<BleDevice>.broadcast();
  bool _scanning = true;

  @override
  Stream<BleDevice> get devices => _controller.stream;

  @override
  bool get isScanning => _scanning;

  void add(BleDevice device) {
    if (!_controller.isClosed) _controller.add(device);
  }

  @override
  Future<void> stop() async {
    if (!_scanning) return;
    _scanning = false;
    await _backend.stopScanInternal(this);
    await _controller.close();
  }
}

// --- Worker-isolate helpers --------------------------------------------------
//
// These run on a short-lived isolate spawned by [Isolate.run], so the blocking
// native call cannot freeze the Dart main isolate. The session travels as its
// integer address; the library is re-opened in the worker (fresh statics). The
// native last-error slot is thread-local, so each helper reads it on the same
// isolate that made the failing call.

/// Blocking peripheral operations dispatched to a worker isolate.
enum _Op { connect, disconnect, write, subscribe, unsubscribe }

/// Output buffer cap for read/discover in the worker isolate; matches the
/// main-isolate buffer. Payloads larger than this fail with "buffer too small".
const int _isoBufCap = 64 * 1024;

/// Opens and binds the library in the current (worker) isolate.
///
/// An explicit [NativeLibrary.overridePath] set on the main isolate is not
/// visible here (statics do not cross isolates); use the `BLUETOOTH_CORE_LIB`
/// env var to point at a custom build, which is read in every isolate.
_Bindings? _isoBindings() {
  final lib = NativeLibrary.open();
  return lib == null ? null : _Bindings(lib);
}

String _isoLastError(_Bindings b, String fallback) {
  final ptr = b.lastError();
  return ptr == nullptr ? fallback : ptr.toDartString();
}

/// Runs a void-returning peripheral op; returns an error message, or null on
/// success.
String? _isoVoidOp((int, _Op, String, String?, Uint8List?, bool) args) {
  final (sessionAddr, op, deviceId, charUuid, data, withResponse) = args;
  final b = _isoBindings();
  if (b == null) return 'bluetooth_core library unavailable';
  final session = Pointer<Void>.fromAddress(sessionAddr);
  final id = deviceId.toNativeUtf8();
  final ch = charUuid?.toNativeUtf8() ?? nullptr;
  Pointer<Uint8> dataPtr = nullptr;
  try {
    final int rc;
    switch (op) {
      case _Op.connect:
        rc = b.connect(session, id);
      case _Op.disconnect:
        rc = b.disconnect(session, id);
      case _Op.subscribe:
        rc = b.subscribe(session, id, ch);
      case _Op.unsubscribe:
        rc = b.unsubscribe(session, id, ch);
      case _Op.write:
        final bytes = data!;
        dataPtr = bytes.isEmpty ? nullptr : malloc<Uint8>(bytes.length);
        if (bytes.isNotEmpty) {
          dataPtr.asTypedList(bytes.length).setAll(0, bytes);
        }
        rc = b.write(
          session,
          id,
          ch,
          dataPtr.cast(),
          bytes.length,
          withResponse ? 1 : 0,
        );
    }
    return rc == 0 ? null : _isoLastError(b, '${op.name} failed');
  } finally {
    malloc.free(id);
    if (ch != nullptr) malloc.free(ch);
    if (dataPtr != nullptr) malloc.free(dataPtr);
  }
}

/// Reads a characteristic; returns `(bytes, null)` on success or `(null, error)`.
(Uint8List?, String?) _isoRead((int, String, String) args) {
  final (sessionAddr, deviceId, charUuid) = args;
  final b = _isoBindings();
  if (b == null) return (null, 'bluetooth_core library unavailable');
  final session = Pointer<Void>.fromAddress(sessionAddr);
  final id = deviceId.toNativeUtf8();
  final ch = charUuid.toNativeUtf8();
  final buf = malloc<Uint8>(_isoBufCap);
  try {
    final n = b.read(session, id, ch, buf, _isoBufCap);
    if (n < 0) return (null, _isoLastError(b, 'read failed'));
    return (Uint8List.fromList(buf.asTypedList(n)), null);
  } finally {
    malloc.free(id);
    malloc.free(ch);
    malloc.free(buf);
  }
}

/// Discovers services; returns `(json, null)` on success or `(null, error)`.
(String?, String?) _isoDiscover((int, String) args) {
  final (sessionAddr, deviceId) = args;
  final b = _isoBindings();
  if (b == null) return (null, 'bluetooth_core library unavailable');
  final session = Pointer<Void>.fromAddress(sessionAddr);
  final id = deviceId.toNativeUtf8();
  final buf = malloc<Uint8>(_isoBufCap);
  try {
    final n = b.discoverServices(session, id, buf, _isoBufCap);
    if (n < 0) return (null, _isoLastError(b, 'discover services failed'));
    return (utf8.decode(buf.asTypedList(n)), null);
  } finally {
    malloc.free(id);
    malloc.free(buf);
  }
}
