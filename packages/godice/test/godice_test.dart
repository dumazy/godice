import 'dart:async';
import 'dart:typed_data';

import 'package:godice/godice.dart';
import 'package:test/test.dart';

/// In-memory transport that records writes and lets the test inject
/// notifications.
class FakeTransport implements GoDiceTransport {
  final List<Uint8List> writes = <Uint8List>[];
  final StreamController<Uint8List> _notify =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _conn = StreamController<bool>.broadcast();
  bool _connected = false;

  /// Called after every write so tests can auto-reply.
  void Function(Uint8List data)? onWrite;

  void emit(List<int> data) => _notify.add(Uint8List.fromList(data));

  @override
  Future<void> connect() async {
    _connected = true;
    _conn.add(true);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _conn.add(false);
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<void> write(Uint8List data) async {
    writes.add(data);
    onWrite?.call(data);
  }

  @override
  Stream<Uint8List> get notifications => _notify.stream;

  @override
  Stream<bool> get connectionState => _conn.stream;

  @override
  Future<void> dispose() async {
    await _notify.close();
    await _conn.close();
  }
}

void main() {
  late FakeTransport transport;
  late GoDice die;

  setUp(() {
    transport = FakeTransport();
    die = GoDice(transport, dieType: DieType.d6, name: 'GoDice_1A2B3C_B_v03');
  });

  tearDown(() => die.dispose());

  test('exposes parsed device name', () {
    expect(die.deviceName?.id, '1A2B3C');
    expect(die.color, DiceColor.blue); // from the name, before fetching
  });

  test('rolls stream only emits genuine stable results', () async {
    await die.connect();
    final rolls = <GoDiceRoll>[];
    final sub = die.rolls.listen(rolls.add);
    final positions = <PositionMessage>[];
    final sub2 = die.positions.listen(positions.add);

    transport.emit([0x52]); // R
    transport.emit([0x46, 0x53, 0x40, 0, 0]); // FS -> 6
    transport.emit([0x53, 0xC0, 0, 0]); // S -> 1
    transport.emit([0x4D, 0x53, 0, 0x40, 0]); // MS -> 3
    await Future<void>.delayed(Duration.zero);

    expect(rolls.map((r) => r.value), [1]);
    expect(rolls.single.die, same(die));
    expect(positions.map((p) => p.value), [6, 1, 3]);
    expect(die.lastRoll?.value, 1);
    await sub.cancel();
    await sub2.cancel();
  });

  test('changing dieType re-interprets subsequent positions', () async {
    await die.connect();
    final values = <int>[];
    final sub = die.positions.listen((p) => values.add(p.value));
    // Notifications are delivered asynchronously, so let each one land before
    // switching the die type (as happens with real dice).
    transport.emit([0x53, 0x40, 0, 0xEA]); // (64,0,-22) -> D6 6
    await Future<void>.delayed(Duration.zero);
    die.dieType = DieType.d20;
    transport.emit([0x53, 0x40, 0, 0xEA]); // -> D20 8
    await Future<void>.delayed(Duration.zero);
    die.dieType = DieType.d10x;
    transport.emit([0x53, 0x40, 0, 0xEA]); // -> D10X 0
    await Future<void>.delayed(Duration.zero);
    expect(values, [6, 8, 0]);
    await sub.cancel();
  });

  test('getBatteryLevel writes the request and awaits Bat', () async {
    await die.connect();
    transport.onWrite = (data) {
      if (data.single == 3) transport.emit([0x42, 0x61, 0x74, 73]);
    };
    expect(await die.getBatteryLevel(), 73);
    expect(transport.writes.single, [3]);
    expect(die.lastBatteryLevel, 73);
  });

  test('getColor caches and refreshes', () async {
    await die.connect();
    var requests = 0;
    transport.onWrite = (data) {
      if (data.single == 23) {
        requests++;
        transport.emit([0x43, 0x6F, 0x6C, DiceColor.orange.code]);
      }
    };
    expect(await die.getColor(), DiceColor.orange);
    expect(await die.getColor(), DiceColor.orange);
    expect(requests, 1);
    expect(await die.getColor(refresh: true), DiceColor.orange);
    expect(requests, 2);
    expect(die.color, DiceColor.orange);
  });

  test('requests time out when the die stays silent', () async {
    await die.connect();
    expect(
      () => die.getBatteryLevel(timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('disconnect fails pending requests', () async {
    await die.connect();
    final pending = die.getBatteryLevel();
    await die.disconnect();
    expect(pending, throwsStateError);
  });

  test('LED helpers write the expected bytes', () async {
    await die.connect();
    await die.setLeds(RgbColor.green);
    await die.ledsOff();
    await die.pulseLed(
      color: RgbColor.red,
      pulseCount: 2,
      onTime: 5,
      offTime: 7,
    );
    expect(transport.writes[0], [8, 0, 255, 0, 0, 255, 0]);
    expect(transport.writes[1], [8, 0, 0, 0, 0, 0, 0]);
    expect(transport.writes[2], [16, 2, 5, 7, 255, 0, 0, 1, 0]);
  });
}
