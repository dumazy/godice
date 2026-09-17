import 'colors.dart';
import 'protocol.dart';

/// The information encoded in a GoDice's advertised name.
///
/// Names have the shape `GoDice_<id>_<colour letter>_<firmware>`, e.g.
/// `GoDice_1A2B3C_R_v03`. Older firmware may omit trailing parts, so every
/// field except [id] is optional.
final class GoDiceDeviceName {
  const GoDiceDeviceName._({
    required this.raw,
    required this.id,
    this.color,
    this.firmware,
  });

  /// The full advertised name.
  final String raw;

  /// The unique id part (typically the last 6 hex digits of the MAC address).
  final String id;

  /// The dot colour derived from the colour letter, if present and known.
  final DiceColor? color;

  /// The firmware tag, e.g. `v03`, if present.
  final String? firmware;

  /// Whether [name] is an advertised GoDice name.
  static bool isGoDice(String? name) =>
      name != null && name.startsWith(GoDiceProtocol.deviceNamePrefix);

  /// Parses [name]; returns `null` when it is not a GoDice name.
  static GoDiceDeviceName? tryParse(String? name) {
    if (!isGoDice(name)) return null;
    final parts = name!.split('_');
    // parts[0] == 'GoDice'
    final id = parts.length > 1 ? parts[1] : '';
    final color = parts.length > 2 ? DiceColor.fromNameLetter(parts[2]) : null;
    final firmware = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
    return GoDiceDeviceName._(
      raw: name,
      id: id,
      color: color,
      firmware: firmware,
    );
  }

  @override
  String toString() => raw;
}
