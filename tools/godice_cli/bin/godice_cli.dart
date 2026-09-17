// Terminal example for package:godice.
//
// Scans for GoDice, connects to one, lights its LEDs in the die's own colour
// and prints every roll. Keys while connected:
//   1-7  switch die type (d6 d20 d10 d10x d4 d8 d12)
//   b    battery level        c  dot colour
//   l    toggle LEDs          p  pulse LEDs
//   h    help                 q  quit
//
// Usage:
//   dart run godice_cli [--list] [--device <name|id part>] [--type d20]
//                       [--scan <seconds>] [--duration <seconds>]
import 'dart:async';
import 'dart:io';

import 'package:godice/godice.dart';
import 'package:godice_bluetooth_dart/godice_bluetooth_dart.dart';

const _usage = '''
Usage: godice_cli [options]

  --list               Scan and list nearby GoDice, then exit.
  --device <text>      Connect to the die whose name or id contains <text>.
                       Default: the first die found.
  --type <die>         Die type: d6 (default) d20 d10 d10x d4 d8 d12.
  --scan <seconds>     How long to scan (default 5 for --list, 15 otherwise).
  --duration <seconds> Disconnect and exit after this long (default: run
                       until q / Ctrl-C).
  -h, --help           Show this help.
''';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stdout.write(_usage);
    exit(64);
  }
  if (options.help) {
    stdout.write(_usage);
    return;
  }

  final bt = Bluetooth.instance;
  if (bt.backend.name != 'ffi') {
    stderr.writeln(
      'No native Bluetooth backend found (active backend: '
      '"${bt.backend.name}").\n'
      'Build the bluetooth_core library first:\n'
      '  tool/build_native.sh\n'
      'or point BLUETOOTH_CORE_LIB at an existing libbluetooth_core library.',
    );
    exit(1);
  }

  final scanner = GoDiceScanner(bluetooth: bt);
  try {
    if (options.list) {
      await _listDice(scanner, options.scanDuration(defaultSeconds: 5));
      return;
    }
    await _run(scanner, options);
  } on GoDiceTransportException catch (e) {
    stderr.writeln('Bluetooth error: ${e.message}');
    if (e.cause != null) stderr.writeln('  ${e.cause}');
    exit(1);
  }
}

Future<void> _listDice(GoDiceScanner scanner, Duration duration) async {
  stdout.writeln('Scanning for GoDice (${duration.inSeconds}s)...');
  final dice = await scanner.scan(timeout: duration);
  if (dice.isEmpty) {
    stdout.writeln('No GoDice found. Shake a die to wake it up and retry.');
    return;
  }
  stdout.writeln('Found ${dice.length} die/dice:');
  for (final d in dice) {
    final info = GoDiceDeviceName.tryParse(d.name);
    final colour = info?.color?.name ?? '?';
    final rssi = (d.rssi?.toString() ?? '?').padLeft(4);
    stdout.writeln('  $rssi dBm  ${d.name}  colour=$colour  id=${d.id}');
  }
}

Future<void> _run(GoDiceScanner scanner, _Options options) async {
  final timeout = options.scanDuration(defaultSeconds: 15);
  final target = options.device;
  stdout.writeln(
    target == null
        ? 'Scanning for the first GoDice (up to ${timeout.inSeconds}s)... '
              'shake a die to wake it.'
        : 'Scanning for a GoDice matching "$target" '
              '(up to ${timeout.inSeconds}s)...',
  );
  final device = await scanner.find(target, timeout: timeout);
  if (device == null) {
    stderr.writeln('No matching GoDice found.');
    exit(1);
  }

  stdout.writeln('Connecting to ${device.name} (${device.id})...');
  final die = GoDiceBluetoothDart.fromBleDevice(device, dieType: options.type);
  final done = Completer<void>();

  final connSub = die.connectionState.listen((up) {
    if (!up && !done.isCompleted) {
      stdout.writeln('\nDie disconnected.');
      done.complete();
    }
  });

  await die.connect();
  stdout.writeln('Connected. Die type: ${die.dieType.name}');

  // Identify the die.
  try {
    final colour = await die.getColor();
    stdout.writeln('Dot colour: ${colour.name}');
  } on TimeoutException {
    stdout.writeln('Dot colour: (no answer)');
  }
  try {
    final battery = await die.getBatteryLevel();
    stdout.writeln('Battery: $battery%');
  } on TimeoutException {
    stdout.writeln('Battery: (no answer)');
  }

  var ledsOn = true;
  final ledColour = die.color?.rgb ?? RgbColor.white;
  await die.setLeds(ledColour);

  stdout.writeln('\nRoll the die! (h for help, q to quit)\n');

  final msgSub = die.messages.listen((m) {
    switch (m) {
      case RollStartMessage():
        stdout.writeln('  rolling...');
      case PositionMessage(:final kind, :final value, :final xyz):
        final label = switch (kind) {
          StabilityKind.stable => 'ROLLED',
          StabilityKind.fakeStable => 'paused at',
          StabilityKind.tiltStable => 'tilted on',
          StabilityKind.moveStable => 'moved to',
        };
        final shown = die.dieType == DieType.d10x
            ? value.toString().padLeft(2, '0')
            : value.toString();
        stdout.writeln(
          '  $label ${shown.padLeft(2)}  (${die.dieType.name}, xyz $xyz)',
        );
      case BatteryLevelMessage(:final level):
        stdout.writeln('  battery: $level%');
      case DiceColorMessage(:final color):
        stdout.writeln('  colour: ${color?.name ?? 'unknown (${m.code})'}');
      case UnknownMessage(:final raw):
        stdout.writeln('  unknown message: $raw');
    }
  });

  // Keyboard handling.
  StreamSubscription<List<int>>? keySub;
  final hasTerminal = _enableRawStdin();
  if (hasTerminal) {
    keySub = stdin.listen((bytes) async {
      for (final byte in bytes) {
        final key = String.fromCharCode(byte);
        switch (key) {
          case 'q':
          case '\x03': // Ctrl-C
            if (!done.isCompleted) done.complete();
          case 'h':
            stdout.writeln(
              '  keys: 1-7 die type (d6 d20 d10 d10x d4 d8 d12), '
              'b battery, c colour, l LEDs, p pulse, q quit',
            );
          case 'b':
            unawaited(die.send(GoDiceCommands.batteryLevel()));
          case 'c':
            unawaited(die.send(GoDiceCommands.diceColor()));
          case 'l':
            ledsOn = !ledsOn;
            unawaited(ledsOn ? die.setLeds(ledColour) : die.ledsOff());
            stdout.writeln('  LEDs ${ledsOn ? 'on' : 'off'}');
          case 'p':
            unawaited(die.pulseLed(color: ledColour, pulseCount: 3));
          case '1' || '2' || '3' || '4' || '5' || '6' || '7':
            final type = DieType.fromCode(int.parse(key) - 1)!;
            die.dieType = type;
            stdout.writeln('  die type: ${type.name}');
        }
      }
    });
  }

  final sigSub = ProcessSignal.sigint.watch().listen((_) {
    if (!done.isCompleted) done.complete();
  });
  Timer? autoQuit;
  if (options.duration != null) {
    autoQuit = Timer(options.duration!, () {
      if (!done.isCompleted) done.complete();
    });
  }

  await done.future;
  autoQuit?.cancel();

  stdout.writeln('Shutting down...');
  await keySub?.cancel();
  await sigSub.cancel();
  await msgSub.cancel();
  await connSub.cancel();
  if (hasTerminal) _restoreStdin();
  if (die.isConnected) {
    try {
      await die.ledsOff();
    } on GoDiceTransportException {
      // Link already gone.
    }
  }
  await die.dispose();
  exit(0);
}

/// Puts stdin in raw mode so single keys arrive immediately. Returns `false`
/// when there is no interactive terminal (pipes, IDE consoles, CI).
bool _enableRawStdin() {
  if (!stdin.hasTerminal) return false;
  try {
    stdin
      ..echoMode = false
      ..lineMode = false;
    return true;
  } on StdinException {
    stdout.writeln('(no interactive terminal: keyboard shortcuts disabled)');
    return false;
  }
}

void _restoreStdin() {
  try {
    stdin
      ..echoMode = true
      ..lineMode = true;
  } on StdinException {
    // Nothing to restore.
  }
}

class _Options {
  const _Options({
    required this.list,
    required this.help,
    required this.device,
    required this.type,
    required this.scanSeconds,
    required this.duration,
  });

  final bool list;
  final bool help;
  final String? device;
  final DieType type;
  final int? scanSeconds;
  final Duration? duration;

  Duration scanDuration({required int defaultSeconds}) =>
      Duration(seconds: scanSeconds ?? defaultSeconds);

  /// Returns `null` on invalid input.
  static _Options? parse(List<String> args) {
    var list = false;
    var help = false;
    String? device;
    var type = DieType.d6;
    int? scanSeconds;
    Duration? duration;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? next() => i + 1 < args.length ? args[++i] : null;
      switch (arg) {
        case '--list':
          list = true;
        case '-h' || '--help':
          help = true;
        case '--device':
          device = next();
          if (device == null) return null;
        case '--type':
          final value = next();
          final parsed = value == null ? null : DieType.tryParse(value);
          if (parsed == null) {
            stderr.writeln('Unknown die type "$value".');
            return null;
          }
          type = parsed;
        case '--scan':
          final value = next();
          final parsed = value == null ? null : int.tryParse(value);
          if (parsed == null || parsed <= 0) {
            stderr.writeln('--scan needs a positive number of seconds.');
            return null;
          }
          scanSeconds = parsed;
        case '--duration':
          final value = next();
          final parsed = value == null ? null : int.tryParse(value);
          if (parsed == null || parsed <= 0) {
            stderr.writeln('--duration needs a positive number of seconds.');
            return null;
          }
          duration = Duration(seconds: parsed);
        default:
          stderr.writeln('Unknown option "$arg".');
          return null;
      }
    }
    return _Options(
      list: list,
      help: help,
      device: device,
      type: type,
      scanSeconds: scanSeconds,
      duration: duration,
    );
  }
}
