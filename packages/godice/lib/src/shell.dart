import 'die_type.dart';
import 'vector3.dart';

/// Reference accelerometer vectors and shell-to-value transforms, copied from
/// the official GoDice APIs. A resting die reports a gravity vector; the face
/// whose reference vector is closest to it is the face pointing up.
abstract final class GoDiceShells {
  /// Face vectors for the bare D6.
  static const Map<int, Vector3> d6Vectors = <int, Vector3>{
    1: Vector3(-64, 0, 0),
    2: Vector3(0, 0, 64),
    3: Vector3(0, 64, 0),
    4: Vector3(0, -64, 0),
    5: Vector3(0, 0, -64),
    6: Vector3(64, 0, 0),
  };

  /// Face vectors for the D20 shell (also D10 / D10X).
  static const Map<int, Vector3> d20Vectors = <int, Vector3>{
    1: Vector3(-64, 0, -22),
    2: Vector3(42, -42, 40),
    3: Vector3(0, 22, -64),
    4: Vector3(0, 22, 64),
    5: Vector3(-42, -42, 42),
    6: Vector3(22, 64, 0),
    7: Vector3(-42, -42, -42),
    8: Vector3(64, 0, -22),
    9: Vector3(-22, 64, 0),
    10: Vector3(42, -42, -42),
    11: Vector3(-42, 42, 42),
    12: Vector3(22, -64, 0),
    13: Vector3(-64, 0, 22),
    14: Vector3(42, 42, 42),
    15: Vector3(-22, -64, 0),
    16: Vector3(42, 42, -42),
    17: Vector3(0, -22, -64),
    18: Vector3(0, -22, 64),
    19: Vector3(-42, 42, -42),
    20: Vector3(64, 0, 22),
  };

  /// Face vectors for the D24 shell (D4 / D8 / D12).
  static const Map<int, Vector3> d24Vectors = <int, Vector3>{
    1: Vector3(20, -60, -20),
    2: Vector3(20, 0, 60),
    3: Vector3(-40, -40, 40),
    4: Vector3(-60, 0, 20),
    5: Vector3(40, 20, 40),
    6: Vector3(-20, -60, -20),
    7: Vector3(20, 60, 20),
    8: Vector3(-40, 20, -40),
    9: Vector3(-40, 40, 40),
    10: Vector3(-20, 0, 60),
    11: Vector3(-20, -60, 20),
    12: Vector3(60, 0, 20),
    13: Vector3(-60, 0, -20),
    14: Vector3(20, 60, -20),
    15: Vector3(20, 0, -60),
    16: Vector3(40, -20, -40),
    17: Vector3(-20, 60, -20),
    18: Vector3(-40, -40, -40),
    19: Vector3(40, -20, 40),
    20: Vector3(20, -60, 20),
    21: Vector3(60, 0, -20),
    22: Vector3(40, 20, -40),
    23: Vector3(-20, 0, -60),
    24: Vector3(-20, 60, 20),
  };

  /// D20-shell face → D10 value (0-9).
  static const Map<int, int> d10Transform = <int, int>{
    1: 8, 2: 2, 3: 6, 4: 1, 5: 4, 6: 3, 7: 9, 8: 0, 9: 7, 10: 5, //
    11: 5, 12: 7, 13: 0, 14: 9, 15: 3, 16: 4, 17: 1, 18: 6, 19: 2, 20: 8,
  };

  /// D20-shell face → D10X value (00-90).
  static const Map<int, int> d10XTransform = <int, int>{
    1: 80, 2: 20, 3: 60, 4: 10, 5: 40, 6: 30, 7: 90, 8: 0, 9: 70, 10: 50, //
    11: 50, 12: 70, 13: 0, 14: 90, 15: 30, 16: 40, 17: 10, 18: 60, 19: 20,
    20: 80,
  };

  /// D24-shell face → D4 value (1-4).
  static const Map<int, int> d4Transform = <int, int>{
    1: 3,
    2: 1,
    3: 4,
    4: 1,
    5: 4,
    6: 4,
    7: 1,
    8: 4,
    9: 2,
    10: 3,
    11: 1,
    12: 1, //
    13: 1, 14: 4, 15: 2, 16: 3, 17: 3, 18: 2, 19: 2, 20: 2, 21: 4, 22: 1,
    23: 3, 24: 2,
  };

  /// D24-shell face → D8 value (1-8).
  static const Map<int, int> d8Transform = <int, int>{
    1: 3,
    2: 3,
    3: 6,
    4: 1,
    5: 2,
    6: 8,
    7: 1,
    8: 1,
    9: 4,
    10: 7,
    11: 5,
    12: 5, //
    13: 4, 14: 4, 15: 2, 16: 5, 17: 7, 18: 7, 19: 8, 20: 2, 21: 8, 22: 3,
    23: 6, 24: 6,
  };

  /// D24-shell face → D12 value (1-12).
  static const Map<int, int> d12Transform = <int, int>{
    1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11, //
    12: 12, 13: 1, 14: 2, 15: 3, 16: 4, 17: 5, 18: 6, 19: 7, 20: 8, 21: 9,
    22: 10, 23: 11, 24: 12,
  };

  /// The reference face vectors for [shell].
  static Map<int, Vector3> vectorsFor(Shell shell) => switch (shell) {
    Shell.d6 => d6Vectors,
    Shell.d20 => d20Vectors,
    Shell.d24 => d24Vectors,
  };

  /// Returns the physical face (1-based) of [shell] whose reference vector is
  /// closest to the accelerometer reading [xyz].
  static int closestFace(Shell shell, Vector3 xyz) {
    final table = vectorsFor(shell);
    var bestFace = 0;
    var bestDistance = 1 << 62;
    for (final entry in table.entries) {
      final distance = xyz.squaredDistanceTo(entry.value);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestFace = entry.key;
      }
    }
    return bestFace;
  }

  /// Converts the accelerometer reading [xyz] to the value shown by a die of
  /// [type], applying the shell transform where needed.
  static int rolledValue(DieType type, Vector3 xyz) {
    final face = closestFace(type.shell, xyz);
    return switch (type) {
      DieType.d6 || DieType.d20 => face,
      DieType.d10 => d10Transform[face]!,
      DieType.d10x => d10XTransform[face]!,
      DieType.d4 => d4Transform[face]!,
      DieType.d8 => d8Transform[face]!,
      DieType.d12 => d12Transform[face]!,
    };
  }
}
