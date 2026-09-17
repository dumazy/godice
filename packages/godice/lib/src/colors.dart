/// The colour of a die's dots, as reported by the `Col` message and encoded
/// in the advertised device name.
enum DiceColor {
  /// Black dots (name letter `K`).
  black(0, 'K'),

  /// Red dots (name letter `R`).
  red(1, 'R'),

  /// Green dots (name letter `G`).
  green(2, 'G'),

  /// Blue dots (name letter `B`).
  blue(3, 'B'),

  /// Yellow dots (name letter `Y`).
  yellow(4, 'Y'),

  /// Orange dots (name letter `O`).
  orange(5, 'O');

  const DiceColor(this.code, this.nameLetter);

  /// The byte value used in the `Col` response.
  final int code;

  /// The letter used in the advertised device name (`GoDice_xxxxxx_R_v03`).
  final String nameLetter;

  /// An RGB value that resembles this colour, handy for lighting the LEDs in
  /// the die's own colour. Black maps to white so the LEDs stay visible.
  RgbColor get rgb => switch (this) {
    DiceColor.black => RgbColor.white,
    DiceColor.red => RgbColor.red,
    DiceColor.green => RgbColor.green,
    DiceColor.blue => RgbColor.blue,
    DiceColor.yellow => RgbColor.yellow,
    DiceColor.orange => RgbColor.orange,
  };

  /// Looks up the colour for a `Col` response [code]; `null` if unknown.
  static DiceColor? fromCode(int code) {
    for (final color in values) {
      if (color.code == code) return color;
    }
    return null;
  }

  /// Looks up the colour for a device-name [letter] (case-insensitive);
  /// `null` if unknown.
  static DiceColor? fromNameLetter(String letter) {
    final upper = letter.toUpperCase();
    for (final color in values) {
      if (color.nameLetter == upper) return color;
    }
    return null;
  }
}

/// An 8-bit RGB colour for the die's LEDs. Components are clamped to 0-255.
final class RgbColor {
  /// Creates a colour, clamping each component to 0-255.
  const RgbColor(int r, int g, int b)
    : r = r < 0 ? 0 : (r > 255 ? 255 : r),
      g = g < 0 ? 0 : (g > 255 ? 255 : g),
      b = b < 0 ? 0 : (b > 255 ? 255 : b);

  /// Red component (0-255).
  final int r;

  /// Green component (0-255).
  final int g;

  /// Blue component (0-255).
  final int b;

  /// LED off.
  static const RgbColor off = RgbColor(0, 0, 0);

  /// Pure white.
  static const RgbColor white = RgbColor(255, 255, 255);

  /// Pure red.
  static const RgbColor red = RgbColor(255, 0, 0);

  /// Pure green.
  static const RgbColor green = RgbColor(0, 255, 0);

  /// Pure blue.
  static const RgbColor blue = RgbColor(0, 0, 255);

  /// Yellow.
  static const RgbColor yellow = RgbColor(255, 255, 0);

  /// Orange.
  static const RgbColor orange = RgbColor(255, 96, 0);

  /// Whether all components are zero.
  bool get isOff => r == 0 && g == 0 && b == 0;

  /// The three components as a list, in `[r, g, b]` order.
  List<int> toList() => <int>[r, g, b];

  @override
  bool operator ==(Object other) =>
      other is RgbColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'RgbColor($r, $g, $b)';
}
