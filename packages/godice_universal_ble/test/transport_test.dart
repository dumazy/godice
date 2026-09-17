import 'package:flutter_test/flutter_test.dart';
import 'package:godice/godice.dart';
import 'package:godice_universal_ble/godice_universal_ble.dart';
import 'package:universal_ble/universal_ble.dart';

import 'fake_platform.dart';

const _id = 'AA:BB:CC:DD:EE:FF';

void main() {
  late FakeUniversalBlePlatform platform;

  setUp(() {
    platform = FakeUniversalBlePlatform();
    UniversalBle.setInstance(platform);
    UniversalBle.queueType = QueueType.none;
  });

  group('UniversalBleTransport (owns connection)', () {
    test(
      'connects, discovers, subscribes and forwards notifications',
      () async {
        final transport = UniversalBleTransport(_id);
        final states = <bool>[];
        transport.connectionState.listen(states.add);
        final received = <List<int>>[];
        transport.notifications.listen((d) => received.add(d.toList()));

        await transport.connect();
        expect(transport.isConnected, isTrue);
        expect(
          platform.log,
          containsAllInOrder(<String>[
            'connect $_id',
            'discover $_id',
            'setNotifiable notification',
          ]),
        );

        platform.notify(_id, <int>[0x52]);
        await pumpEventQueue();
        expect(received, <List<int>>[
          <int>[0x52],
        ]);

        await transport.write(GoDiceCommands.batteryLevel());
        expect(platform.writes.single, <int>[3]);

        await transport.disconnect();
        expect(transport.isConnected, isFalse);
        expect(
          platform.log,
          containsAllInOrder(<String>[
            'setNotifiable disabled',
            'disconnect $_id',
          ]),
        );
        expect(states, <bool>[true, false]);
        await transport.dispose();
      },
    );

    test('reuses an existing connection and subscription', () async {
      platform.states[_id] = BleConnectionState.connected;
      platform.subscribed[_id] = <String>{
        GoDiceProtocol.notifyCharacteristicUuid,
      };
      // Mirror what UniversalBle's cache would know.
      await UniversalBle.subscribeNotifications(
        _id,
        GoDiceProtocol.serviceUuid,
        GoDiceProtocol.notifyCharacteristicUuid,
      );
      platform.log.clear();

      final transport = UniversalBleTransport(_id);
      await transport.connect();
      expect(platform.log, isNot(contains('connect $_id')));
      expect(platform.log, isNot(contains('setNotifiable notification')));
      expect(transport.isConnected, isTrue);
      await transport.dispose();
    });

    test('rejects a peripheral without the GoDice service', () async {
      platform.exposeGoDiceService = false;
      final transport = UniversalBleTransport(_id);
      await expectLater(
        transport.connect(),
        throwsA(
          isA<GoDiceTransportException>().having(
            (e) => e.message,
            'message',
            contains('GoDice service'),
          ),
        ),
      );
      expect(transport.isConnected, isFalse);
      await transport.dispose();
    });

    test('reports an unexpected drop', () async {
      final transport = UniversalBleTransport(_id);
      await transport.connect();
      final drops = transport.connectionState.first;
      platform.dropLink(_id);
      expect(await drops, isFalse);
      expect(transport.isConnected, isFalse);
      await expectLater(
        transport.write(GoDiceCommands.batteryLevel()),
        throwsA(isA<GoDiceTransportException>()),
      );
      await transport.dispose();
    });
  });

  group('UniversalBleTransport (shared connection)', () {
    test('refuses to connect when the app has not connected yet', () async {
      final transport = UniversalBleTransport(_id, ownsConnection: false);
      await expectLater(
        transport.connect(),
        throwsA(isA<GoDiceTransportException>()),
      );
      expect(platform.log, isNot(contains('connect $_id')));
      await transport.dispose();
    });

    test('attaches to the app connection and never tears it down', () async {
      platform.states[_id] = BleConnectionState.connected;
      final transport = UniversalBleTransport(_id, ownsConnection: false);
      await transport.connect();
      expect(transport.isConnected, isTrue);
      expect(platform.log, <String>['setNotifiable notification']);

      await transport.dispose();
      expect(platform.log, isNot(contains('setNotifiable disabled')));
      expect(platform.log, isNot(contains('disconnect $_id')));
    });
  });

  group('GoDiceUniversalBle', () {
    test('fromDevice builds a working GoDice', () async {
      final device = BleDevice(deviceId: _id, name: 'GoDice_1A2B3C_R_v03');
      final die = GoDiceUniversalBle.fromDevice(device, dieType: DieType.d20);
      expect(die.name, 'GoDice_1A2B3C_R_v03');
      expect(die.color, DiceColor.red);
      expect(die.dieType, DieType.d20);

      await die.connect();
      platform.onWrite = (data) {
        if (data.single == 3) platform.notify(_id, <int>[0x42, 0x61, 0x74, 88]);
      };
      expect(await die.getBatteryLevel(), 88);

      final roll = die.rolls.first;
      platform.notify(_id, <int>[0x53, 0x40, 0x00, 0x16]); // (64,0,22) -> 20
      expect((await roll).value, 20);
      await die.dispose();
    });
  });
}
