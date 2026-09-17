import 'package:flutter_test/flutter_test.dart';
import 'package:godice/godice.dart';
import 'package:godice_universal_ble/godice_universal_ble.dart';
import 'package:universal_ble/universal_ble.dart';

import 'fake_platform.dart';

void main() {
  late FakeUniversalBlePlatform platform;

  setUp(() {
    platform = FakeUniversalBlePlatform();
    UniversalBle.setInstance(platform);
    UniversalBle.queueType = QueueType.none;
  });

  test(
    'filters the scan stream without touching the scan by default',
    () async {
      final scanner = GoDiceScanner();
      final seen = <String>[];
      final sub = scanner.discover().listen((d) => seen.add(d.name!));
      await pumpEventQueue();
      platform.advertise('1', 'GoDice_5F9714_B_v04');
      platform.advertise('2', 'Pixels Die');
      platform.advertise('3', 'GoDice_AA64AE_O_v04');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, <String>['GoDice_5F9714_B_v04', 'GoDice_AA64AE_O_v04']);
      expect(platform.log, isEmpty);
    },
  );

  test('manageScan starts and stops the scan around listeners', () async {
    final scanner = GoDiceScanner(manageScan: true);
    final sub = scanner.discover().listen((_) {});
    await pumpEventQueue();
    expect(platform.log, <String>['startScan']);
    await sub.cancel();
    expect(platform.log, <String>['startScan', 'stopScan']);
  });

  test('manageScan reports Bluetooth being off', () async {
    platform.availability = AvailabilityState.poweredOff;
    final scanner = GoDiceScanner(manageScan: true);
    await expectLater(
      scanner.discover().first,
      throwsA(isA<GoDiceTransportException>()),
    );
    expect(platform.log, isEmpty);
  });

  test('scan() sorts by RSSI and dedupes', () async {
    final scanner = GoDiceScanner();
    final future = scanner.scan(timeout: const Duration(milliseconds: 50));
    await pumpEventQueue();
    platform.advertise('1', 'GoDice_1_B_v04', rssi: -80);
    platform.advertise('2', 'GoDice_2_R_v04', rssi: -50);
    platform.advertise('1', 'GoDice_1_B_v04', rssi: -70);
    final dice = await future;
    expect(dice.map((d) => d.deviceId), <String>['2', '1']);
    expect(dice.last.rssi, -70);
  });

  test('find() matches name or id and times out to null', () async {
    final scanner = GoDiceScanner();
    final future = scanner.find('aa64ae', timeout: const Duration(seconds: 1));
    await pumpEventQueue();
    platform.advertise('1', 'GoDice_5F9714_B_v04');
    platform.advertise('2', 'GoDice_AA64AE_O_v04');
    expect((await future)!.deviceId, '2');

    expect(
      await scanner.find('nothing', timeout: const Duration(milliseconds: 30)),
      isNull,
    );
  });
}
