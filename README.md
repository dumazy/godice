# godice

[![CI](https://github.com/dumazy/godice/actions/workflows/ci.yml/badge.svg)](https://github.com/dumazy/godice/actions/workflows/ci.yml) [![godice](https://img.shields.io/pub/v/godice.svg?label=godice)](https://pub.dev/packages/godice) [![godice_universal_ble](https://img.shields.io/pub/v/godice_universal_ble.svg?label=godice_universal_ble)](https://pub.dev/packages/godice_universal_ble)

Dart support for [GoDice](https://particula-tech.com/godice) Bluetooth smart
dice. This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces)
with three packages:

| Package | What it is |
|---|---|
| [`packages/godice`](packages/godice) | **Published.** Pure Dart core: BLE protocol constants, command builders, notification parsing, shell-aware roll interpretation and a transport-agnostic `GoDice` client. No dependencies. |
| [`packages/godice_universal_ble`](packages/godice_universal_ble) | **Published.** The Flutter transport and scanner, built on [`universal_ble`](https://pub.dev/packages/universal_ble). Designed to coexist with apps that already use `universal_ble`. Comes with a Flutter example app. |
| [`tools/godice_bluetooth_dart`](tools/godice_bluetooth_dart) | Not published. Pure Dart transport on [`bluetooth_dart`](https://pub.dev/packages/bluetooth_dart), kept as a hardware smoke test that runs without Flutter. |
| [`tools/godice_cli`](tools/godice_cli) | Not published. Terminal smoke test: scans, connects, lights the LEDs and prints rolls. |
| [`third_party/bluetooth_dart`](third_party/bluetooth_dart) | Vendored copy of `bluetooth_dart` 0.0.1 with one fix to notification subscriptions (see its `PATCHES.md`). Only needed by the smoke test. |

The protocol (UUIDs, message bytes, face vectors and shell transforms) is taken
from the official GoDice
[JavaScript](https://github.com/ParticulaCode/GoDiceJavaScriptAPI) and
[Python](https://github.com/ParticulaCode/GoDicePythonAPI) APIs.

## Quick start

Requirements: [FVM](https://fvm.app) (the project pins Flutter 3.47.4 /
Dart 3.13.3 in `.fvmrc`) and, only for the terminal smoke test, a Rust
toolchain to build the native BLE library once.

```sh
fvm install                        # picks up .fvmrc
fvm dart pub global activate melos # task runner + publishing
melos bootstrap                    # resolves the whole workspace

melos run analyze
melos run test

# Flutter example (macOS shown; also runs on iOS/Android)
cd packages/godice_universal_ble/example && fvm flutter run -d macos

# Terminal smoke test (pure Dart, no Flutter). Build the native BLE library
# used by bluetooth_dart first (needs cargo).
tool/build_native.sh

# List nearby dice (shake a die to wake it up).
cd tools/godice_cli
fvm dart run godice_cli --list

# Connect to the first die found, treat it as a D20, and print rolls.
fvm dart run godice_cli --type d20

# Connect to a specific die for 30 seconds (handy for scripts).
fvm dart run godice_cli --device 5F9714 --duration 30
```

While connected: `1`-`7` switch the die type, `b` battery, `c` colour,
`l` toggle LEDs, `p` pulse, `q` quit.

On macOS the terminal application you run this from (Terminal, iTerm, VS
Code, ...) is asked for Bluetooth permission the first time.

## Library usage (Flutter)

```dart
import 'package:godice/godice.dart';
import 'package:godice_universal_ble/godice_universal_ble.dart';

final scanner = GoDiceScanner(manageScan: true);
final device = await scanner.find(null); // first GoDice seen
final die = GoDiceUniversalBle.fromDevice(device!, dieType: DieType.d6);

await die.connect();
print('Colour: ${await die.getColor()}  battery: ${await die.getBatteryLevel()}%');
await die.setLeds(die.color!.rgb);

die.rolls.listen((roll) => print('Rolled ${roll.value}'));
```

Apps that already drive `universal_ble` themselves can attach with
`ownsConnection: false`, or skip the transport package and implement
`GoDiceTransport` from `package:godice` directly. See
[`packages/godice_universal_ble/README.md`](packages/godice_universal_ble/README.md).

## Why two transports?

Flutter BLE plugins need the Flutter engine and cannot run from `dart run`.
`godice_universal_ble` is the transport meant for apps. The terminal smoke
test needs a BLE stack that runs in plain Dart, and `bluetooth_dart` is the
only one that works on macOS from the command line; it drives CoreBluetooth
through the Rust `btleplug` crate over FFI, which is why
`tool/build_native.sh` exists. Both are thin adapters over the same
`GoDiceTransport` interface from the core package.

## Layout

```
.fvmrc                         Flutter/Dart version pin (FVM)
pubspec.yaml                   workspace root + Melos configuration
.github/workflows              CI (analyze, format, test, publish dry-run) and tag-driven publishing
packages/godice                core library + tests (published)
packages/godice_universal_ble  Flutter transport + scanner + example app (published)
tools/godice_bluetooth_dart    pure Dart transport for the smoke test (not published)
tools/godice_cli               terminal smoke test (not published)
third_party/bluetooth_dart     vendored bluetooth_dart 0.0.1 + fix
tool/build_native.sh           fetches and builds bluetooth_core (Rust) into native/
```

## Releasing

Releases are driven by [Melos](https://melos.invertase.dev) and GitHub
Actions; see [CONTRIBUTING.md](CONTRIBUTING.md) for the step by step.
