import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'colors.dart';
import 'commands.dart';
import 'device_name.dart';
import 'die_type.dart';
import 'messages.dart';
import 'transport.dart';

/// A rolled result, emitted on [GoDice.rolls] once the die settles after a
/// real roll.
final class GoDiceRoll {
  /// Creates a roll result.
  const GoDiceRoll({required this.value, required this.dieType, this.die});

  /// The value shown by the die, interpreted for [dieType].
  final int value;

  /// The die type the value was interpreted for.
  final DieType dieType;

  /// The die that rolled, when known.
  final GoDice? die;

  @override
  String toString() => 'GoDiceRoll($value on ${dieType.name})';
}

/// A connected GoDice.
///
/// Wraps a [GoDiceTransport] with the GoDice protocol: it parses notifications
/// into typed [messages], exposes convenience streams for rolls, and offers
/// request/response helpers for battery and colour plus LED control.
///
/// ```dart
/// final die = GoDice(transport, dieType: DieType.d6);
/// await die.connect();
/// die.rolls.listen((roll) => print('Rolled ${roll.value}'));
/// print('Battery: ${await die.getBatteryLevel()}%');
/// await die.setLed(led1: RgbColor.blue, led2: RgbColor.blue);
/// ```
class GoDice {
  /// Creates a client over [transport]. [dieType] tells the client which shell
  /// the die sits in and can be changed later via the [dieType] setter.
  /// [name] is the advertised BLE name, if known.
  GoDice(this._transport, {this.dieType = DieType.d6, this.name}) {
    _messages = _transport.notifications
        .map((data) => GoDiceMessage.parse(data, dieType: dieType))
        .asBroadcastStream();
    _messageSub = _messages.listen(_dispatch);
  }

  final GoDiceTransport _transport;
  late final Stream<GoDiceMessage> _messages;
  late final StreamSubscription<GoDiceMessage> _messageSub;

  final Queue<Completer<int>> _batteryWaiters = Queue<Completer<int>>();
  final Queue<Completer<DiceColor>> _colorWaiters =
      Queue<Completer<DiceColor>>();

  DiceColor? _cachedColor;
  int? _lastBatteryLevel;
  GoDiceRoll? _lastRoll;

  /// The advertised BLE name (e.g. `GoDice_1A2B3C_R_v03`), if known.
  final String? name;

  /// Details parsed from [name], if available.
  GoDiceDeviceName? get deviceName => GoDiceDeviceName.tryParse(name);

  /// The die type used to interpret rolls. Assign a new value when the die is
  /// moved to another shell; it takes effect for the next position message.
  DieType dieType;

  /// The underlying transport.
  GoDiceTransport get transport => _transport;

  /// Whether the BLE link is up.
  bool get isConnected => _transport.isConnected;

  /// Connection changes: `true` when connected, `false` when the link drops.
  Stream<bool> get connectionState => _transport.connectionState;

  /// Every parsed notification from the die.
  Stream<GoDiceMessage> get messages => _messages;

  /// Every position report, including fake/tilt/move stables.
  Stream<PositionMessage> get positions =>
      _messages.where((m) => m is PositionMessage).cast<PositionMessage>();

  /// Fires when the die starts rolling.
  Stream<RollStartMessage> get rollStarts =>
      _messages.where((m) => m is RollStartMessage).cast<RollStartMessage>();

  /// Final results of genuine rolls (`S` messages only).
  Stream<GoDiceRoll> get rolls => positions
      .where((p) => p.isRollResult)
      .map((p) => GoDiceRoll(value: p.value, dieType: p.dieType, die: this));

  /// The most recent genuine roll, if any.
  GoDiceRoll? get lastRoll => _lastRoll;

  /// The most recently reported battery level, if any.
  int? get lastBatteryLevel => _lastBatteryLevel;

  /// The dot colour, once fetched via [getColor] (or known from [name]).
  DiceColor? get color => _cachedColor ?? deviceName?.color;

  /// Connects the transport. Notifications flow as soon as this completes.
  Future<void> connect() => _transport.connect();

  /// Disconnects the transport. Pending requests fail with a [StateError].
  Future<void> disconnect() async {
    await _transport.disconnect();
    _failPending(StateError('Disconnected before a response arrived'));
  }

  /// Disconnects and releases all resources. The instance is unusable
  /// afterwards.
  Future<void> dispose() async {
    await _messageSub.cancel();
    _failPending(StateError('GoDice disposed'));
    await _transport.dispose();
  }

  /// Sends raw [command] bytes to the die.
  Future<void> send(Uint8List command) => _transport.write(command);

  /// Requests the battery level (0-100). Throws a [TimeoutException] if the
  /// die does not answer within [timeout].
  Future<int> getBatteryLevel({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final completer = Completer<int>();
    _batteryWaiters.add(completer);
    try {
      await send(GoDiceCommands.batteryLevel());
      return await completer.future.timeout(timeout);
    } finally {
      _batteryWaiters.remove(completer);
    }
  }

  /// Requests the dot colour. Cached after the first successful answer unless
  /// [refresh] is `true`. Throws a [TimeoutException] on no answer.
  Future<DiceColor> getColor({
    bool refresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final cached = _cachedColor;
    if (cached != null && !refresh) return cached;
    final completer = Completer<DiceColor>();
    _colorWaiters.add(completer);
    try {
      await send(GoDiceCommands.diceColor());
      return await completer.future.timeout(timeout);
    } finally {
      _colorWaiters.remove(completer);
    }
  }

  /// Sets the two LEDs. A `null` LED is switched off.
  Future<void> setLed({RgbColor? led1, RgbColor? led2}) =>
      send(GoDiceCommands.setLed(led1: led1, led2: led2));

  /// Sets both LEDs to the same [color].
  Future<void> setLeds(RgbColor color) => setLed(led1: color, led2: color);

  /// Switches both LEDs off.
  Future<void> ledsOff() => send(GoDiceCommands.ledsOff());

  /// Pulses both LEDs. Times are in units of 10 ms (max 255).
  Future<void> pulseLed({
    required RgbColor color,
    int pulseCount = 3,
    int onTime = 20,
    int offTime = 20,
  }) => send(
    GoDiceCommands.pulseLed(
      pulseCount: pulseCount,
      onTime: onTime,
      offTime: offTime,
      color: color,
    ),
  );

  void _dispatch(GoDiceMessage message) {
    switch (message) {
      case BatteryLevelMessage(:final level):
        _lastBatteryLevel = level;
        if (_batteryWaiters.isNotEmpty) {
          _batteryWaiters.removeFirst().complete(level);
        }
      case DiceColorMessage(:final color):
        if (color != null) {
          _cachedColor = color;
          if (_colorWaiters.isNotEmpty) {
            _colorWaiters.removeFirst().complete(color);
          }
        } else if (_colorWaiters.isNotEmpty) {
          _colorWaiters.removeFirst().completeError(
            FormatException('Unknown colour code ${message.code}'),
          );
        }
      case PositionMessage() when message.isRollResult:
        _lastRoll = GoDiceRoll(
          value: message.value,
          dieType: message.dieType,
          die: this,
        );
      case PositionMessage() || RollStartMessage() || UnknownMessage():
        break;
    }
  }

  void _failPending(Object error) {
    while (_batteryWaiters.isNotEmpty) {
      _batteryWaiters.removeFirst().completeError(error);
    }
    while (_colorWaiters.isNotEmpty) {
      _colorWaiters.removeFirst().completeError(error);
    }
  }

  @override
  String toString() => 'GoDice(${name ?? 'unnamed'}, ${dieType.name})';
}
