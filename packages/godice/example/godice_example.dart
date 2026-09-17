// Minimal end-to-end example of package:godice without any Bluetooth
// hardware: a fake transport replays the bytes a real die would send.
//
// In an app you would use a real transport instead, for example
// `UniversalBleTransport` from package:godice_universal_ble, or your own
// implementation of GoDiceTransport on top of your BLE plugin.
import 'dart:async';
import 'dart:typed_data';

import 'package:godice/godice.dart';

Future<void> main() async {
  final transport = ReplayTransport();
  final die = GoDice(
    transport,
    dieType: DieType.d6,
    name: 'GoDice_1A2B3C_B_v04',
  );

  await die.connect();
  print('Connected to ${die.name} (dots: ${die.deviceName?.color?.name})');

  die.rollStarts.listen((_) => print('rolling...'));
  die.rolls.listen((roll) => print('rolled ${roll.value}'));

  // Battery and colour are request/response messages.
  print('battery: ${await die.getBatteryLevel()}%');
  print('colour:  ${await die.getColor()}');

  // Light both LEDs in the die's own colour, then simulate a roll.
  await die.setLeds(die.color!.rgb);
  transport.simulateRoll(faceUpVector: const Vector3(0, 64, 0)); // D6 face 3
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // Moved the die into a D20 shell? Just tell the client.
  die.dieType = DieType.d20;
  transport.simulateRoll(faceUpVector: const Vector3(64, 0, 22)); // D20 face 20
  await Future<void>.delayed(const Duration(milliseconds: 50));

  await die.dispose();
}

/// A GoDiceTransport that answers commands the way a real die would.
class ReplayTransport implements GoDiceTransport {
  final _notifications = StreamController<Uint8List>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Stream<bool> get connectionState => _connection.stream;

  @override
  Future<void> connect() async {
    _connected = true;
    _connection.add(true);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _connection.add(false);
  }

  @override
  Future<void> write(Uint8List data) async {
    print('  -> die: $data');
    switch (data.first) {
      case GoDiceProtocol.batteryLevelRequest:
        _emit([...GoDiceProtocol.batteryHeader, 87]);
      case GoDiceProtocol.diceColorRequest:
        _emit([...GoDiceProtocol.colorHeader, DiceColor.blue.code]);
    }
  }

  void simulateRoll({required Vector3 faceUpVector}) {
    _emit([GoDiceProtocol.rollStartHeader]);
    _emit([
      GoDiceProtocol.stableHeader,
      faceUpVector.x,
      faceUpVector.y,
      faceUpVector.z,
    ]);
  }

  void _emit(List<int> bytes) => _notifications.add(
    Uint8List.fromList(bytes.map((b) => b & 0xff).toList()),
  );

  @override
  Future<void> dispose() async {
    await _notifications.close();
    await _connection.close();
  }
}
