/// BLE protocol constants for GoDice, as defined by the official GoDice APIs
/// (https://github.com/ParticulaCode/GoDiceJavaScriptAPI and
/// https://github.com/ParticulaCode/GoDicePythonAPI).
///
/// GoDice speaks the Nordic UART Service (NUS) profile: the host writes
/// commands to [writeCharacteristicUuid] and receives notifications on
/// [notifyCharacteristicUuid].
abstract final class GoDiceProtocol {
  /// Primary GATT service exposed by every GoDice.
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  /// Characteristic the host writes commands to (NUS RX).
  static const String writeCharacteristicUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Characteristic the die sends notifications on (NUS TX).
  static const String notifyCharacteristicUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  /// Advertised local name prefix. Full names look like `GoDice_1A2B3C_R_v03`
  /// (see `GoDiceDeviceName`).
  static const String deviceNamePrefix = 'GoDice_';

  // ---------------------------------------------------------------------------
  // Outgoing message identifiers (first byte of a command).
  // ---------------------------------------------------------------------------

  /// Request the battery level; the die answers with a [batteryHeader] message.
  static const int batteryLevelRequest = 3;

  /// Request the dice (dots) colour; the die answers with a [colorHeader]
  /// message.
  static const int diceColorRequest = 23;

  /// Set both RGB LEDs: `[8, r1, g1, b1, r2, g2, b2]`.
  static const int setLed = 8;

  /// Pulse both LEDs: `[16, pulseCount, onTime, offTime, r, g, b, 1, 0]`.
  static const int setLedToggle = 16;

  // ---------------------------------------------------------------------------
  // Incoming message headers (ASCII bytes at the start of a notification).
  // ---------------------------------------------------------------------------

  /// `R`: the die started rolling.
  static const int rollStartHeader = 0x52;

  /// `S`: the die came to rest; followed by the xyz vector.
  static const int stableHeader = 0x53;

  /// `F` (then `S`): "fake stable", a brief pause during a roll; followed by
  /// the xyz vector.
  static const int fakeStablePrefix = 0x46;

  /// `T` (then `S`): "tilt stable", the die rests tilted against something;
  /// followed by the xyz vector.
  static const int tiltStablePrefix = 0x54;

  /// `M` (then `S`): "move stable", the die was moved without rolling;
  /// followed by the xyz vector.
  static const int moveStablePrefix = 0x4D;

  /// `Bat`: battery level response, level in the 4th byte (0-100).
  static const List<int> batteryHeader = <int>[0x42, 0x61, 0x74];

  /// `Col`: colour response, colour code in the 4th byte (see `DiceColor`).
  static const List<int> colorHeader = <int>[0x43, 0x6F, 0x6C];
}
