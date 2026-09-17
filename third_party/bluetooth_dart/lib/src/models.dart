import 'dart:typed_data';

/// The OS-level Bluetooth authorization state.
///
/// Only Apple platforms have an app-level Bluetooth permission with a real
/// status; on Linux/Windows there is no per-app gate ([unsupported], treated as
/// granted) and Android's runtime permission is handled by the Flutter layer.
enum PermissionStatus {
  /// Not yet requested.
  notDetermined,

  /// Granted.
  granted,

  /// Denied by the user; re-requesting will not re-prompt (send them to
  /// Settings).
  denied,

  /// Restricted (e.g. parental controls / MDM).
  restricted,

  /// This platform has no app-level Bluetooth permission; treat as granted.
  unsupported;

  /// Whether BLE operations are allowed to proceed.
  bool get isUsable => this == granted || this == unsupported;

  /// Maps a native status code (see `bluetooth_core`'s `permission` module).
  static PermissionStatus fromCode(int code) => switch (code) {
    0 => notDetermined,
    1 => granted,
    2 => denied,
    3 => restricted,
    4 => unsupported,
    _ => notDetermined,
  };
}

/// A discovered/updated BLE peripheral.
class BleDevice {
  const BleDevice({
    required this.id,
    required this.address,
    this.name,
    this.rssi,
    this.txPower,
    this.manufacturerData = const {},
    this.serviceData = const {},
    this.services = const [],
    this.connected = false,
  });

  /// Stable per-session identity. On Apple this is a CoreBluetooth UUID;
  /// elsewhere typically the MAC address. Use this for all peripheral ops.
  final String id;

  /// Best-effort hardware address (may be empty on Apple, which hides it).
  final String address;

  /// Advertised local name, when present.
  final String? name;

  /// Received signal strength in dBm, when known.
  final int? rssi;

  /// Advertised transmit power in dBm, when known.
  final int? txPower;

  /// Manufacturer-specific advertisement data, keyed by company id (decimal
  /// string).
  final Map<String, Uint8List> manufacturerData;

  /// Service advertisement data, keyed by service UUID string.
  final Map<String, Uint8List> serviceData;

  /// Advertised service UUIDs.
  final List<String> services;

  /// Whether the host currently holds a connection to this peripheral.
  final bool connected;

  /// Decodes the JSON object emitted by the native `device` event.
  factory BleDevice.fromJson(Map<String, dynamic> json) => BleDevice(
    id: json['id'] as String,
    address: json['address'] as String? ?? '',
    name: json['name'] as String?,
    rssi: (json['rssi'] as num?)?.toInt(),
    txPower: (json['tx_power'] as num?)?.toInt(),
    manufacturerData: _decodeByteMap(json['manufacturer_data']),
    serviceData: _decodeByteMap(json['service_data']),
    services:
        (json['services'] as List?)?.map((e) => e as String).toList() ??
        const [],
    connected: json['connected'] as bool? ?? false,
  );

  @override
  String toString() =>
      'BleDevice($id, ${name ?? '(unknown)'}, ${rssi ?? '?'} dBm)';
}

/// A GATT service with its characteristics.
class BleService {
  const BleService({
    required this.uuid,
    required this.primary,
    required this.characteristics,
  });

  final String uuid;
  final bool primary;
  final List<BleCharacteristic> characteristics;

  factory BleService.fromJson(Map<String, dynamic> json) => BleService(
    uuid: json['uuid'] as String,
    primary: json['primary'] as bool? ?? false,
    characteristics: (json['characteristics'] as List? ?? const [])
        .map((e) => BleCharacteristic.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// A GATT characteristic and the operations it advertises.
class BleCharacteristic {
  const BleCharacteristic({
    required this.uuid,
    required this.serviceUuid,
    required this.properties,
  });

  final String uuid;
  final String serviceUuid;

  /// Lowercase property flags (e.g. `read`, `write`, `notify`, `indicate`).
  final List<String> properties;

  bool get canRead => properties.contains('read');
  bool get canWrite =>
      properties.contains('write') ||
      properties.contains('write-without-response');
  bool get canNotify =>
      properties.contains('notify') || properties.contains('indicate');

  factory BleCharacteristic.fromJson(Map<String, dynamic> json) =>
      BleCharacteristic(
        uuid: json['uuid'] as String,
        serviceUuid: json['service_uuid'] as String,
        properties:
            (json['properties'] as List?)?.map((e) => e as String).toList() ??
            const [],
      );
}

/// A notification/indication delivered for a subscribed characteristic.
class BleNotification {
  const BleNotification({
    required this.deviceId,
    required this.characteristic,
    required this.value,
  });

  final String deviceId;
  final String characteristic;
  final Uint8List value;
}

/// A change in the host's connection to a peripheral.
///
/// Delivered on `Bluetooth.connectionStates`, this lets apps react to connects
/// and, importantly, *unexpected* disconnects (device out of range, powered
/// off, GATT dropped), which a one-shot `connect()` future cannot report.
class BleConnectionState {
  const BleConnectionState({required this.deviceId, required this.connected});

  /// The peripheral whose connection changed (a [BleDevice.id]).
  final String deviceId;

  /// Whether the host is now connected to it.
  final bool connected;

  @override
  String toString() =>
      'BleConnectionState($deviceId, '
      '${connected ? 'connected' : 'disconnected'})';
}

/// The Bluetooth adapter's power state, delivered on `Bluetooth.adapterStates`.
///
/// This is the radio/adapter state (is Bluetooth on?), distinct from
/// [PermissionStatus] (is the app authorized?).
enum AdapterState {
  /// State not yet known.
  unknown,

  /// The adapter is on and usable.
  poweredOn,

  /// The adapter is off (the user or system turned Bluetooth off).
  poweredOff,

  /// No usable Bluetooth adapter on this host.
  unsupported;

  /// Parses the lowercase state string the native layer emits (btleplug's
  /// `CentralState`): `poweredon`, `poweredoff`, or `unknown`.
  static AdapterState fromNative(String state) => switch (state.toLowerCase()) {
    'poweredon' => poweredOn,
    'poweredoff' => poweredOff,
    _ => unknown,
  };
}

/// Decodes a JSON object whose values are arrays of byte integers into a map of
/// [Uint8List].
Map<String, Uint8List> _decodeByteMap(Object? raw) {
  if (raw is! Map) return const {};
  return raw.map(
    (key, value) => MapEntry(
      key as String,
      Uint8List.fromList(
        (value as List).map((e) => (e as num).toInt()).toList(),
      ),
    ),
  );
}
