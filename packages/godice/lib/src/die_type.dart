/// The physical shells a GoDice can be mounted in.
///
/// GoDice sells three shell geometries; the [DieType] tells the library which
/// geometry the die is in and how to map the resting face to a number.
enum Shell {
  /// The bare die itself: 6 faces.
  d6(6),

  /// The 20-face shell, also used for D10 and D10X (percentile) dice.
  d20(20),

  /// The 24-face shell, used for D4, D8 and D12 dice.
  d24(24);

  const Shell(this.faces);

  /// Number of physical faces on this shell.
  final int faces;
}

/// The kind of die a GoDice currently represents. The [code] values match the
/// official GoDice APIs.
enum DieType {
  /// Standard six-sided die (no shell).
  d6(0, Shell.d6, 6),

  /// Twenty-sided die.
  d20(1, Shell.d20, 20),

  /// Ten-sided die reporting 0-9 (uses the D20 shell).
  d10(2, Shell.d20, 10),

  /// Percentile die reporting 00-90 in steps of 10 (uses the D20 shell).
  d10x(3, Shell.d20, 10),

  /// Four-sided die (uses the D24 shell).
  d4(4, Shell.d24, 4),

  /// Eight-sided die (uses the D24 shell).
  d8(5, Shell.d24, 8),

  /// Twelve-sided die (uses the D24 shell).
  d12(6, Shell.d24, 12);

  const DieType(this.code, this.shell, this.sides);

  /// Numeric code used by the official GoDice APIs.
  final int code;

  /// The physical shell this die type is mounted in.
  final Shell shell;

  /// Number of distinct values this die can roll.
  final int sides;

  /// Looks up a die type by its official [code]; `null` if unknown.
  static DieType? fromCode(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }

  /// Parses a user-facing name such as `d6`, `D20` or `d10x`; `null` if the
  /// name is not recognised.
  static DieType? tryParse(String name) {
    final lower = name.trim().toLowerCase();
    for (final type in values) {
      if (type.name == lower) return type;
    }
    return null;
  }
}
