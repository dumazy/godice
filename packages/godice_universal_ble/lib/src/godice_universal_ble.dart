import 'package:godice/godice.dart';
import 'package:universal_ble/universal_ble.dart';

import 'transport.dart';

/// Constructors that wire a [GoDice] to a [UniversalBleTransport].
abstract final class GoDiceUniversalBle {
  /// Creates a (not yet connected) [GoDice] for a scanned [device].
  ///
  /// Set [ownsConnection] to `false` when the app connects and disconnects
  /// the device itself; see [UniversalBleTransport].
  static GoDice fromDevice(
    BleDevice device, {
    DieType dieType = DieType.d6,
    bool ownsConnection = true,
  }) => GoDice(
    UniversalBleTransport(device.deviceId, ownsConnection: ownsConnection),
    dieType: dieType,
    name: device.name,
  );

  /// Creates a (not yet connected) [GoDice] for a known [deviceId].
  static GoDice fromDeviceId(
    String deviceId, {
    DieType dieType = DieType.d6,
    String? name,
    bool ownsConnection = true,
  }) => GoDice(
    UniversalBleTransport(deviceId, ownsConnection: ownsConnection),
    dieType: dieType,
    name: name,
  );
}
