import 'dart:typed_data';

import 'colors.dart';
import 'protocol.dart';

/// Builders for the byte payloads written to
/// [GoDiceProtocol.writeCharacteristicUuid].
abstract final class GoDiceCommands {
  /// Ask for the battery level; the die replies with a `Bat` message.
  static Uint8List batteryLevel() =>
      Uint8List.fromList(<int>[GoDiceProtocol.batteryLevelRequest]);

  /// Ask for the dot colour; the die replies with a `Col` message.
  static Uint8List diceColor() =>
      Uint8List.fromList(<int>[GoDiceProtocol.diceColorRequest]);

  /// Set the two RGB LEDs. A `null` LED is turned off.
  static Uint8List setLed({RgbColor? led1, RgbColor? led2}) {
    final a = led1 ?? RgbColor.off;
    final b = led2 ?? RgbColor.off;
    return Uint8List.fromList(<int>[
      GoDiceProtocol.setLed,
      a.r, a.g, a.b, //
      b.r, b.g, b.b,
    ]);
  }

  /// Turn both LEDs off.
  static Uint8List ledsOff() => setLed();

  /// Pulse both LEDs [pulseCount] times in [color], staying on for [onTime]
  /// and off for [offTime]. Times are in units of 10 ms; all three values
  /// must fit in a byte (0-255).
  static Uint8List pulseLed({
    required int pulseCount,
    required int onTime,
    required int offTime,
    required RgbColor color,
  }) {
    _checkByte(pulseCount, 'pulseCount');
    _checkByte(onTime, 'onTime');
    _checkByte(offTime, 'offTime');
    return Uint8List.fromList(<int>[
      GoDiceProtocol.setLedToggle,
      pulseCount,
      onTime,
      offTime,
      color.r, color.g, color.b, //
      1, 0, // trailer used by the official APIs
    ]);
  }

  static void _checkByte(int value, String name) {
    if (value < 0 || value > 255) {
      throw RangeError.range(value, 0, 255, name);
    }
  }
}
