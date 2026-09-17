import 'dart:typed_data';

import 'colors.dart';
import 'die_type.dart';
import 'protocol.dart';
import 'shell.dart';
import 'vector3.dart';

/// How the die came to rest when a position message was sent.
enum StabilityKind {
  /// `S`: a normal roll finished.
  stable,

  /// `FS`: the die paused briefly mid-roll (not a final result).
  fakeStable,

  /// `TS`: the die rests tilted, e.g. leaning against an object.
  tiltStable,

  /// `MS`: the die was moved/placed without an actual roll.
  moveStable,
}

/// A parsed notification from a GoDice.
sealed class GoDiceMessage {
  const GoDiceMessage(this.raw);

  /// The raw notification bytes.
  final Uint8List raw;

  /// Parses a raw notification.
  ///
  /// [dieType] is needed to turn the accelerometer vector of position messages
  /// into a rolled value. Unrecognised payloads become an [UnknownMessage]
  /// instead of throwing, so a firmware that adds messages does not break the
  /// stream.
  static GoDiceMessage parse(Uint8List data, {required DieType dieType}) {
    if (data.isEmpty) return UnknownMessage(data);

    final first = data[0];
    if (first == GoDiceProtocol.rollStartHeader) {
      return RollStartMessage(data);
    }

    if (first == GoDiceProtocol.stableHeader && data.length >= 4) {
      return PositionMessage._(
        data,
        kind: StabilityKind.stable,
        xyz: _xyzAt(data, 1),
        dieType: dieType,
      );
    }

    if (data.length >= 2 && data[1] == GoDiceProtocol.stableHeader) {
      final kind = switch (first) {
        GoDiceProtocol.fakeStablePrefix => StabilityKind.fakeStable,
        GoDiceProtocol.tiltStablePrefix => StabilityKind.tiltStable,
        GoDiceProtocol.moveStablePrefix => StabilityKind.moveStable,
        _ => null,
      };
      if (kind != null && data.length >= 5) {
        return PositionMessage._(
          data,
          kind: kind,
          xyz: _xyzAt(data, 2),
          dieType: dieType,
        );
      }
    }

    if (_startsWith(data, GoDiceProtocol.batteryHeader) && data.length >= 4) {
      return BatteryLevelMessage(data, level: data[3]);
    }

    if (_startsWith(data, GoDiceProtocol.colorHeader) && data.length >= 4) {
      return DiceColorMessage(data, color: DiceColor.fromCode(data[3]));
    }

    return UnknownMessage(data);
  }

  static bool _startsWith(Uint8List data, List<int> header) {
    if (data.length < header.length) return false;
    for (var i = 0; i < header.length; i++) {
      if (data[i] != header[i]) return false;
    }
    return true;
  }

  /// Reads three signed 8-bit values starting at [offset].
  static Vector3 _xyzAt(Uint8List data, int offset) {
    final view = ByteData.sublistView(data, offset, offset + 3);
    return Vector3(view.getInt8(0), view.getInt8(1), view.getInt8(2));
  }
}

/// The die started rolling (`R`).
final class RollStartMessage extends GoDiceMessage {
  /// Creates a roll-start message from its raw bytes.
  const RollStartMessage(super.raw);

  @override
  String toString() => 'RollStartMessage()';
}

/// The die reported a resting position (`S`, `FS`, `TS` or `MS`).
final class PositionMessage extends GoDiceMessage {
  PositionMessage._(
    super.raw, {
    required this.kind,
    required this.xyz,
    required this.dieType,
  }) : value = GoDiceShells.rolledValue(dieType, xyz);

  /// How the die came to rest.
  final StabilityKind kind;

  /// The raw accelerometer vector.
  final Vector3 xyz;

  /// The die type used to interpret [xyz].
  final DieType dieType;

  /// The face value, interpreted for [dieType].
  final int value;

  /// `true` for a genuine roll result (`S`), `false` for the intermediate or
  /// hand-placed variants.
  bool get isRollResult => kind == StabilityKind.stable;

  @override
  String toString() =>
      'PositionMessage(${kind.name}, value: $value, xyz: $xyz, '
      '${dieType.name})';
}

/// Battery level response (`Bat`).
final class BatteryLevelMessage extends GoDiceMessage {
  /// Creates a battery message from its raw bytes and decoded [level].
  const BatteryLevelMessage(super.raw, {required this.level});

  /// Battery charge in percent (0-100).
  final int level;

  @override
  String toString() => 'BatteryLevelMessage($level%)';
}

/// Dice colour response (`Col`).
final class DiceColorMessage extends GoDiceMessage {
  /// Creates a colour message from its raw bytes and decoded [color].
  const DiceColorMessage(super.raw, {required this.color});

  /// The dot colour, or `null` if the die reported an unknown code.
  final DiceColor? color;

  /// The raw colour code byte.
  int get code => raw[3];

  @override
  String toString() => 'DiceColorMessage(${color?.name ?? 'code $code'})';
}

/// A notification the library does not understand.
final class UnknownMessage extends GoDiceMessage {
  /// Creates an unknown message wrapping the raw bytes.
  const UnknownMessage(super.raw);

  @override
  String toString() => 'UnknownMessage($raw)';
}
