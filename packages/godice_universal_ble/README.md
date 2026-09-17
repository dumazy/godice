# godice_universal_ble

[![pub package](https://img.shields.io/pub/v/godice_universal_ble.svg)](https://pub.dev/packages/godice_universal_ble) [![pub points](https://img.shields.io/pub/points/godice_universal_ble)](https://pub.dev/packages/godice_universal_ble/score) [![CI](https://github.com/dumazy/godice/actions/workflows/ci.yml/badge.svg)](https://github.com/dumazy/godice/actions/workflows/ci.yml)

`GoDiceTransport` and scanner for [`godice`](https://pub.dev/packages/godice)
built on [`universal_ble`](https://pub.dev/packages/universal_ble). Works on
Android, iOS, macOS, Windows, Linux and Web.

## Setup

Add both packages:

```yaml
dependencies:
  godice: ^0.1.0
  godice_universal_ble: ^0.1.0
```

Then do the usual `universal_ble` platform setup:

- **Android**: `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` in the manifest
  (plus `ACCESS_FINE_LOCATION` for API 30 and below).
- **iOS / macOS**: `NSBluetoothAlwaysUsageDescription` in `Info.plist`; on
  macOS also the `com.apple.security.device.bluetooth` entitlement.

The `example/` app has all of these in place.

## Usage

```dart
import 'package:godice/godice.dart';
import 'package:godice_universal_ble/godice_universal_ble.dart';

// Let the scanner start/stop the BLE scan for us.
final scanner = GoDiceScanner(manageScan: true);
final device = await scanner.find(null); // first GoDice seen

final die = GoDiceUniversalBle.fromDevice(device!, dieType: DieType.d6);
await die.connect();

die.rolls.listen((roll) => print('Rolled ${roll.value}'));
print('Battery ${await die.getBatteryLevel()}%');
await die.setLeds(die.color!.rgb);
```

Everything after `connect()` is `package:godice`; see its README for the
full API (positions, battery, colour, LEDs, die types).

## Sharing `universal_ble` with your own code

This package is built to coexist with an app that already drives
`universal_ble`:

- It only uses the broadcast streams (`scanStream`, `connectionStream`,
  `characteristicValueStream`), never the single-owner `onScanResult` /
  `onValueChange` callbacks, so it cannot steal events from you.
- `GoDiceScanner` does **not** start or stop scanning unless you pass
  `manageScan: true`. By default it just filters `UniversalBle.scanStream`
  for `GoDice_` names while your app controls the scan.
- `UniversalBleTransport(deviceId, ownsConnection: false)` attaches to a
  connection your app manages: it checks the link is up, subscribes to the
  notify characteristic only if nobody has yet, and never disconnects or
  unsubscribes on dispose.

```dart
// App already connected the device itself:
final die = GoDiceUniversalBle.fromDeviceId(id, ownsConnection: false);
await die.connect(); // just attaches
```

If your app has its own BLE layer, you can also skip this package and
implement `GoDiceTransport` from `package:godice` directly in about 50 lines:
write to characteristic `6e400002-…`, forward `characteristicValueStream` of
`6e400003-…` into `notifications`, and forward `connectionStream` into
`connectionState`.
