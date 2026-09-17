# godice

[![pub package](https://img.shields.io/pub/v/godice.svg)](https://pub.dev/packages/godice) [![pub points](https://img.shields.io/pub/points/godice)](https://pub.dev/packages/godice/score) [![CI](https://github.com/dumazy/godice/actions/workflows/ci.yml/badge.svg)](https://github.com/dumazy/godice/actions/workflows/ci.yml)

Pure Dart library for [GoDice](https://particula-tech.com/godice) smart dice.
It implements the GoDice BLE protocol and leaves the Bluetooth stack up to you
through a small `GoDiceTransport` interface, so it works with any BLE package
(and in plain `dart run` programs).

For a ready-made Flutter transport see
[`godice_universal_ble`](https://pub.dev/packages/godice_universal_ble).

## Protocol

GoDice use the Nordic UART Service:

| | UUID |
|---|---|
| Service | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` |
| Write (commands) | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |
| Notify (events) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |

Dice advertise as `GoDice_<id>_<colour>_<firmware>`, e.g. `GoDice_1A2B3C_R_v03`.

Commands (`GoDiceCommands`):

| Command | Bytes |
|---|---|
| Battery level | `[3]` → reply `Bat` + level |
| Dot colour | `[23]` → reply `Col` + code |
| Set LEDs | `[8, r1, g1, b1, r2, g2, b2]` |
| Pulse LEDs | `[16, count, on, off, r, g, b, 1, 0]` (times in 10 ms units) |

Notifications (`GoDiceMessage.parse`):

| Header | Message |
|---|---|
| `R` | `RollStartMessage` |
| `S` xyz | `PositionMessage` (stable, a real roll) |
| `FS` xyz | `PositionMessage` (fakeStable) |
| `TS` xyz | `PositionMessage` (tiltStable) |
| `MS` xyz | `PositionMessage` (moveStable) |
| `Bat` n | `BatteryLevelMessage` |
| `Col` n | `DiceColorMessage` |

The xyz bytes are a signed accelerometer vector. `GoDiceShells` holds the
reference vector for every face of the D6, D20 and D24 shells plus the
transforms for D10, D10X, D4, D8 and D12, and picks the nearest face.

## Usage

```dart
import 'package:godice/godice.dart';

final die = GoDice(myTransport, dieType: DieType.d20, name: 'GoDice_1A2B3C_R_v03');
await die.connect();

die.rollStarts.listen((_) => print('rolling...'));
die.rolls.listen((roll) => print('rolled ${roll.value}'));
die.positions.listen((p) => print('${p.kind.name}: ${p.value} ${p.xyz}'));

print(await die.getBatteryLevel());   // 0-100
print(await die.getColor());          // DiceColor.red
await die.setLeds(RgbColor.blue);
await die.pulseLed(color: RgbColor.red, pulseCount: 3, onTime: 20, offTime: 20);
die.dieType = DieType.d10x;           // moved the die to a D10X shell
```

## Writing a transport

```dart
class MyTransport implements GoDiceTransport {
  // connect(): connect, discover services, subscribe to
  //   GoDiceProtocol.notifyCharacteristicUuid and push every value on
  //   `notifications` (a broadcast stream).
  // write(data): write to GoDiceProtocol.writeCharacteristicUuid.
  // connectionState: broadcast stream, true on connect / false on drop.
  // disconnect() / dispose() / isConnected.
}
```
