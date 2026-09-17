import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../../bluetooth_backend.dart';
import '../../exceptions.dart';
import '../../models.dart';
import '../../scan.dart';

/// On the web the native backend is Web Bluetooth (`navigator.bluetooth`).
///
/// Returns the backend unconditionally; [WebBluetoothBackend.isAvailable]
/// feature-detects `navigator.bluetooth` and reports `false` when the browser
/// has no Web Bluetooth (e.g. Firefox, or Chromium on Linux without the flag),
/// so the registry falls through to the unsupported floor there. This mirrors
/// the FFI backend, which is always returned but reports unavailable when the
/// native library cannot load.
BluetoothBackend? createNativeBackend() => WebBluetoothBackend();

// --- Web Bluetooth js_interop bindings ---------------------------------------
//
// `package:web` ships no Bluetooth bindings, so the slice of the spec this
// backend uses is bound here. See
// https://developer.mozilla.org/docs/Web/API/Web_Bluetooth_API.

@JS('navigator.bluetooth')
external _Bluetooth? get _navigatorBluetooth;

extension type _Bluetooth._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> getAvailability();
  external JSPromise<_BluetoothDevice> requestDevice(JSObject options);
  external JSPromise<_BluetoothLEScan> requestLEScan(JSObject options);
  external void addEventListener(JSString type, JSFunction listener);
  external void removeEventListener(JSString type, JSFunction listener);
}

extension type _BluetoothDevice._(JSObject _) implements JSObject {
  external String get id;
  external String? get name;
  external _BluetoothRemoteGATTServer? get gatt;
  external void addEventListener(JSString type, JSFunction listener);
  external void removeEventListener(JSString type, JSFunction listener);
}

extension type _BluetoothRemoteGATTServer._(JSObject _) implements JSObject {
  external bool get connected;
  external JSPromise<_BluetoothRemoteGATTServer> connect();
  external void disconnect();
  external JSPromise<JSArray<_BluetoothRemoteGATTService>> getPrimaryServices();
}

extension type _BluetoothRemoteGATTService._(JSObject _) implements JSObject {
  external String get uuid;
  external bool get isPrimary;
  external JSPromise<JSArray<_BluetoothRemoteGATTCharacteristic>>
  getCharacteristics();
}

extension type _BluetoothRemoteGATTCharacteristic._(JSObject _)
    implements JSObject {
  external String get uuid;
  external _BluetoothRemoteGATTService get service;
  external _BluetoothCharacteristicProperties get properties;
  external _DataView? get value;
  external JSPromise<_DataView> readValue();
  external JSPromise<JSAny?> writeValueWithResponse(JSAny value);
  external JSPromise<JSAny?> writeValueWithoutResponse(JSAny value);
  external JSPromise<_BluetoothRemoteGATTCharacteristic> startNotifications();
  external JSPromise<_BluetoothRemoteGATTCharacteristic> stopNotifications();
  external void addEventListener(JSString type, JSFunction listener);
  external void removeEventListener(JSString type, JSFunction listener);
}

extension type _BluetoothCharacteristicProperties._(JSObject _)
    implements JSObject {
  external bool get read;
  external bool get write;
  external bool get writeWithoutResponse;
  external bool get notify;
  external bool get indicate;
}

extension type _BluetoothLEScan._(JSObject _) implements JSObject {
  external void stop();
}

extension type _BluetoothAdvertisingEvent._(JSObject _) implements JSObject {
  external _BluetoothDevice get device;
  external JSNumber? get rssi;
  external JSNumber? get txPower;
  external String? get name;
  external JSArray<JSAny?> get uuids;
  external _JSMap get manufacturerData;
  external _JSMap get serviceData;
}

extension type _CharacteristicValueChangedEvent._(JSObject _)
    implements JSObject {
  external _BluetoothRemoteGATTCharacteristic get target;
}

/// `availabilitychanged` on `navigator.bluetooth`; `value` is the new adapter
/// availability.
extension type _AvailabilityChangedEvent._(JSObject _) implements JSObject {
  external bool get value;
}

extension type _DataView._(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
  external int get byteOffset;
  external int get byteLength;
}

/// Minimal view of a JS `Map` (e.g. `BluetoothManufacturerDataMap`).
extension type _JSMap._(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
}

/// Reaches BLE through the browser's Web Bluetooth API.
///
/// [startScan] has two possible strategies. By default it uses the chooser
/// (`requestDevice`): the browser shows its own device picker, which scans
/// internally, and the single device the user selects is emitted on
/// [ScanSession.devices]. This is the path Chromium supports best; it works with
/// just the `WebBluetooth` feature enabled and needs a user gesture, so call
/// [startScan] from a tap or click handler. Scan again per device to collect
/// several.
///
/// Setting `preferLeScan: true` switches to the streaming `requestLEScan` API,
/// where advertisements arrive continuously like the native backends. That API
/// is experimental: it needs Chromium's Experimental Web Platform features flag,
/// and on some platforms (Linux/BlueZ in particular) the scan reports active but
/// never delivers advertisements, which is why it stays off by default.
///
/// Either way, peripheral operations only work on devices obtained this session:
/// Web Bluetooth hands out opaque, origin-scoped device handles, so this backend
/// caches the live JS objects keyed by [BleDevice.id]. Pass the services you
/// intend to use as `serviceUuids` so they are added to the device's
/// `optionalServices` allowlist; otherwise GATT access to them is blocked by the
/// browser.
class WebBluetoothBackend extends BluetoothBackend {
  WebBluetoothBackend({this.preferLeScan = false});

  /// Use the experimental `requestLEScan` streaming API instead of the chooser
  /// when the browser exposes it. Off by default; see the class docs for the
  /// caveats.
  final bool preferLeScan;

  /// Live device handles keyed by [BleDevice.id].
  final Map<String, _BluetoothDevice> _devices = {};

  /// Live characteristic handles keyed by `deviceId|lowercaseUuid`.
  final Map<String, _BluetoothRemoteGATTCharacteristic> _chars = {};

  /// Notification controllers keyed by `deviceId|lowercaseUuid`.
  final Map<String, StreamController<BleNotification>> _notifs = {};

  /// `characteristicvaluechanged` listeners, same key as [_notifs], kept so they
  /// can be detached on cancel.
  final Map<String, JSFunction> _notifListeners = {};

  _WebScan? _scan;
  _BluetoothLEScan? _leScan;
  JSFunction? _advListener;

  /// Connection- and adapter-state fan-out.
  final StreamController<BleConnectionState> _connStates =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<AdapterState> _adapterStates =
      StreamController<AdapterState>.broadcast();

  /// `gattserverdisconnected` listeners, one per cached device id.
  final Map<String, JSFunction> _disconnectListeners = {};

  /// `availabilitychanged` listener on `navigator.bluetooth`, attached lazily.
  JSFunction? _availabilityListener;

  @override
  String get name => 'web';

  @override
  int get priority => 100;

  @override
  bool get isAvailable => _navigatorBluetooth != null;

  @override
  Stream<BleConnectionState> get connectionStates => _connStates.stream;

  @override
  Stream<AdapterState> get adapterStates {
    _ensureAvailabilityListener();
    return _adapterStates.stream;
  }

  bool get _supportsLeScan =>
      _navigatorBluetooth?.has('requestLEScan') ?? false;

  @override
  Future<void> initialize() async {
    if (!isAvailable) {
      throw const NoBackendAvailableException(
        'Web Bluetooth is not available in this browser. Chromium browsers '
        '(Chrome/Edge/Brave) support it in a secure context; on Linux it is '
        'behind a flag. Firefox and Safari do not support it.',
      );
    }
  }

  @override
  Future<PermissionStatus> permissionStatus() async {
    if (!isAvailable) return PermissionStatus.unsupported;
    // Web Bluetooth has no global permission gate (access is granted per device
    // by the chooser). Treat an available adapter as usable, and a missing or
    // disabled one as denied so the UI can prompt the user to enable it.
    try {
      final available =
          (await _navigatorBluetooth!.getAvailability().toDart).toDart;
      return available ? PermissionStatus.granted : PermissionStatus.denied;
    } on Object {
      // Older browsers may lack getAvailability; assume usable.
      return PermissionStatus.granted;
    }
  }

  @override
  Future<PermissionStatus> requestPermission() => permissionStatus();

  @override
  Future<ScanSession> startScan({List<String> serviceUuids = const []}) async {
    await initialize();
    await _scan?.stop();
    final scan = _WebScan(this);
    _scan = scan;
    try {
      if (preferLeScan && _supportsLeScan) {
        await _startLeScan(serviceUuids);
      } else {
        await _startChooserScan(serviceUuids, scan);
      }
    } on Object catch (e) {
      _scan = null;
      throw BleException('start scan failed: $e');
    }
    return scan;
  }

  Future<void> _startLeScan(List<String> serviceUuids) async {
    final options = serviceUuids.isEmpty
        ? {'acceptAllAdvertisements': true, 'keepRepeatedDevices': true}
        : {
            'filters': [
              for (final s in serviceUuids)
                {
                  'services': [s],
                },
            ],
            'keepRepeatedDevices': true,
          };
    _leScan = await _navigatorBluetooth!
        .requestLEScan(options.jsify() as JSObject)
        .toDart;
    final listener = ((_BluetoothAdvertisingEvent event) {
      _onAdvertisement(event);
    }).toJS;
    _advListener = listener;
    _navigatorBluetooth!.addEventListener(
      'advertisementreceived'.toJS,
      listener,
    );
  }

  Future<void> _startChooserScan(
    List<String> serviceUuids,
    _WebScan scan,
  ) async {
    final options = serviceUuids.isEmpty
        ? {'acceptAllDevices': true}
        : {
            'filters': [
              for (final s in serviceUuids)
                {
                  'services': [s],
                },
            ],
            'optionalServices': serviceUuids,
          };
    final _BluetoothDevice device;
    try {
      device = await _navigatorBluetooth!
          .requestDevice(options.jsify() as JSObject)
          .toDart;
    } on Object catch (e) {
      // Dismissing the chooser rejects with a NotFoundError; that is a normal
      // "no device picked", not a failure. Leave the scan empty.
      if (_isChooserCancelled(e)) return;
      rethrow;
    }
    _cacheDevice(device);
    scan.add(_toBleDevice(device));
  }

  bool _isChooserCancelled(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('cancel') ||
        s.contains('notfound') ||
        s.contains('chooser')) {
      return true;
    }
    // The rejection is usually a JS DOMException; read its `name` if we can.
    try {
      final name = (e as JSObject).getProperty<JSString?>('name'.toJS)?.toDart;
      return name == 'NotFoundError';
    } on Object {
      return false;
    }
  }

  void _onAdvertisement(_BluetoothAdvertisingEvent event) {
    final device = event.device;
    _cacheDevice(device);
    _scan?.add(
      BleDevice(
        id: device.id,
        address: '',
        name: event.name ?? device.name,
        rssi: event.rssi?.toDartInt,
        txPower: event.txPower?.toDartInt,
        manufacturerData: _decodeDataMap(event.manufacturerData),
        serviceData: _decodeDataMap(event.serviceData),
        services: [
          for (final u in event.uuids.toDart)
            if (u != null) u.dartify().toString(),
        ],
        connected: device.gatt?.connected ?? false,
      ),
    );
  }

  BleDevice _toBleDevice(_BluetoothDevice device) => BleDevice(
    id: device.id,
    address: '',
    name: device.name,
    connected: device.gatt?.connected ?? false,
  );

  /// Caches a live device handle and attaches a one-time `gattserverdisconnected`
  /// listener so unexpected disconnects surface on [connectionStates].
  void _cacheDevice(_BluetoothDevice device) {
    _devices[device.id] = device;
    if (_disconnectListeners.containsKey(device.id)) return;
    final id = device.id;
    final listener = ((JSObject _) {
      if (!_connStates.isClosed) {
        _connStates.add(BleConnectionState(deviceId: id, connected: false));
      }
    }).toJS;
    _disconnectListeners[id] = listener;
    device.addEventListener('gattserverdisconnected'.toJS, listener);
  }

  /// Attaches the `availabilitychanged` listener once, mapping adapter
  /// availability to [AdapterState] on [adapterStates].
  void _ensureAvailabilityListener() {
    if (_availabilityListener != null) return;
    final nav = _navigatorBluetooth;
    if (nav == null) return;
    final listener = ((_AvailabilityChangedEvent event) {
      if (!_adapterStates.isClosed) {
        _adapterStates.add(
          event.value ? AdapterState.poweredOn : AdapterState.poweredOff,
        );
      }
    }).toJS;
    _availabilityListener = listener;
    nav.addEventListener('availabilitychanged'.toJS, listener);
  }

  Future<void> stopScanInternal(ScanSession scan) async {
    if (!identical(_scan, scan)) return;
    _scan = null;
    try {
      _leScan?.stop();
    } on Object {
      // Already stopped.
    }
    _leScan = null;
    final listener = _advListener;
    if (listener != null) {
      _navigatorBluetooth?.removeEventListener(
        'advertisementreceived'.toJS,
        listener,
      );
      _advListener = null;
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    final gatt = _gatt(deviceId);
    if (!gatt.connected) await gatt.connect().toDart;
    if (!_connStates.isClosed) {
      _connStates.add(BleConnectionState(deviceId: deviceId, connected: true));
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final gatt = _devices[deviceId]?.gatt;
    if (gatt != null && gatt.connected) gatt.disconnect();
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    final gatt = _gatt(deviceId);
    if (!gatt.connected) await gatt.connect().toDart;
    final services = (await gatt.getPrimaryServices().toDart).toDart;
    final result = <BleService>[];
    for (final svc in services) {
      final chars = (await svc.getCharacteristics().toDart).toDart;
      final bleChars = <BleCharacteristic>[];
      for (final ch in chars) {
        _chars['$deviceId|${ch.uuid.toLowerCase()}'] = ch;
        bleChars.add(
          BleCharacteristic(
            uuid: ch.uuid,
            serviceUuid: svc.uuid,
            properties: _decodeProperties(ch.properties),
          ),
        );
      }
      result.add(
        BleService(
          uuid: svc.uuid,
          primary: svc.isPrimary,
          characteristics: bleChars,
        ),
      );
    }
    return result;
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    final ch = await _characteristic(deviceId, characteristicUuid);
    final view = await ch.readValue().toDart;
    return _dataViewBytes(view);
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
  }) async {
    final ch = await _characteristic(deviceId, characteristicUuid);
    // A typed array is a valid BufferSource for writeValue*.
    final buffer = value.toJS;
    if (withResponse) {
      await ch.writeValueWithResponse(buffer).toDart;
    } else {
      await ch.writeValueWithoutResponse(buffer).toDart;
    }
  }

  @override
  Stream<BleNotification> subscribe(
    String deviceId,
    String characteristicUuid,
  ) {
    final key = '$deviceId|${characteristicUuid.toLowerCase()}';
    final existing = _notifs[key];
    if (existing != null) return existing.stream;

    late final StreamController<BleNotification> controller;
    controller = StreamController<BleNotification>.broadcast(
      onListen: () async {
        try {
          final ch = await _characteristic(deviceId, characteristicUuid);
          final listener = ((_CharacteristicValueChangedEvent event) {
            if (controller.isClosed) return;
            final view = event.target.value;
            controller.add(
              BleNotification(
                deviceId: deviceId,
                characteristic: characteristicUuid,
                value: view == null ? Uint8List(0) : _dataViewBytes(view),
              ),
            );
          }).toJS;
          _notifListeners[key] = listener;
          ch.addEventListener('characteristicvaluechanged'.toJS, listener);
          await ch.startNotifications().toDart;
        } on Object catch (e) {
          if (!controller.isClosed) {
            controller.addError(BleException('subscribe failed: $e'));
          }
        }
      },
      onCancel: () async {
        _notifs.remove(key);
        final listener = _notifListeners.remove(key);
        final ch = _chars[key];
        if (ch != null) {
          if (listener != null) {
            ch.removeEventListener('characteristicvaluechanged'.toJS, listener);
          }
          try {
            await ch.stopNotifications().toDart;
          } on Object {
            // Device may already be gone.
          }
        }
      },
    );
    _notifs[key] = controller;
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    await _scan?.stop();
    for (final c in _notifs.values) {
      await c.close();
    }
    _notifs.clear();
    _notifListeners.clear();
    _chars.clear();
    // Detach per-device disconnect listeners before dropping the handles.
    for (final entry in _disconnectListeners.entries) {
      _devices[entry.key]?.removeEventListener(
        'gattserverdisconnected'.toJS,
        entry.value,
      );
    }
    _disconnectListeners.clear();
    final availability = _availabilityListener;
    if (availability != null) {
      _navigatorBluetooth?.removeEventListener(
        'availabilitychanged'.toJS,
        availability,
      );
      _availabilityListener = null;
    }
    await _connStates.close();
    await _adapterStates.close();
    for (final device in _devices.values) {
      final gatt = device.gatt;
      if (gatt != null && gatt.connected) gatt.disconnect();
    }
    _devices.clear();
  }

  _BluetoothRemoteGATTServer _gatt(String deviceId) {
    final device = _devices[deviceId];
    if (device == null) {
      throw BleException(
        'Unknown device "$deviceId". On the web a device must be obtained from '
        'a scan/chooser this session before it can be used.',
      );
    }
    final gatt = device.gatt;
    if (gatt == null) {
      throw BleException('Device "$deviceId" exposes no GATT server.');
    }
    return gatt;
  }

  Future<_BluetoothRemoteGATTCharacteristic> _characteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    final key = '$deviceId|${characteristicUuid.toLowerCase()}';
    final cached = _chars[key];
    if (cached != null) return cached;
    // Not seen yet: connect + discover to populate the cache.
    await discoverServices(deviceId);
    final resolved = _chars[key];
    if (resolved == null) {
      throw BleException(
        'Characteristic "$characteristicUuid" was not found on "$deviceId".',
      );
    }
    return resolved;
  }
}

List<String> _decodeProperties(_BluetoothCharacteristicProperties p) => [
  if (p.read) 'read',
  if (p.write) 'write',
  if (p.writeWithoutResponse) 'write-without-response',
  if (p.notify) 'notify',
  if (p.indicate) 'indicate',
];

Uint8List _dataViewBytes(_DataView view) =>
    view.buffer.toDart.asUint8List(view.byteOffset, view.byteLength);

Map<String, Uint8List> _decodeDataMap(_JSMap map) {
  final result = <String, Uint8List>{};
  try {
    map.forEach(
      ((JSAny value, JSAny key) {
        result[key.dartify().toString()] = _dataViewBytes(value as _DataView);
      }).toJS,
    );
  } on Object {
    // Best effort: advertisement data decoding never blocks a discovery.
  }
  return result;
}

/// The [ScanSession] handed out by [WebBluetoothBackend].
///
/// The chooser path emits its one device synchronously inside `startScan`,
/// before the caller has had a chance to `listen`. A broadcast stream would drop
/// those, so devices added before the first listener are buffered and flushed on
/// subscription.
class _WebScan implements ScanSession {
  _WebScan(this._backend) {
    _controller = StreamController<BleDevice>.broadcast(onListen: _flush);
  }

  final WebBluetoothBackend _backend;
  late final StreamController<BleDevice> _controller;
  final List<BleDevice> _pending = [];
  bool _scanning = true;

  @override
  Stream<BleDevice> get devices => _controller.stream;

  @override
  bool get isScanning => _scanning;

  void add(BleDevice device) {
    if (_controller.isClosed) return;
    if (_controller.hasListener) {
      _controller.add(device);
    } else {
      _pending.add(device);
    }
  }

  void _flush() {
    for (final device in _pending) {
      if (!_controller.isClosed) _controller.add(device);
    }
    _pending.clear();
  }

  @override
  Future<void> stop() async {
    if (!_scanning) return;
    _scanning = false;
    await _backend.stopScanInternal(this);
    await _controller.close();
  }
}
