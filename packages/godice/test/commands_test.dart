import 'package:godice/godice.dart';
import 'package:test/test.dart';

void main() {
  test('battery and colour requests', () {
    expect(GoDiceCommands.batteryLevel(), [3]);
    expect(GoDiceCommands.diceColor(), [23]);
  });

  test('setLed', () {
    expect(
      GoDiceCommands.setLed(
        led1: const RgbColor(1, 2, 3),
        led2: const RgbColor(4, 5, 6),
      ),
      [8, 1, 2, 3, 4, 5, 6],
    );
    expect(GoDiceCommands.setLed(led1: RgbColor.red), [8, 255, 0, 0, 0, 0, 0]);
    expect(GoDiceCommands.ledsOff(), [8, 0, 0, 0, 0, 0, 0]);
  });

  test('pulseLed', () {
    expect(
      GoDiceCommands.pulseLed(
        pulseCount: 5,
        onTime: 10,
        offTime: 20,
        color: RgbColor.blue,
      ),
      [16, 5, 10, 20, 0, 0, 255, 1, 0],
    );
    expect(
      () => GoDiceCommands.pulseLed(
        pulseCount: 256,
        onTime: 1,
        offTime: 1,
        color: RgbColor.blue,
      ),
      throwsRangeError,
    );
  });

  test('RgbColor clamps', () {
    expect(const RgbColor(-5, 300, 128), const RgbColor(0, 255, 128));
  });
}
