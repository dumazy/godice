import 'package:godice/godice.dart';
import 'package:test/test.dart';

void main() {
  test('parses a full name', () {
    final n = GoDiceDeviceName.tryParse('GoDice_1A2B3C_R_v03')!;
    expect(n.id, '1A2B3C');
    expect(n.color, DiceColor.red);
    expect(n.firmware, 'v03');
  });

  test('parses partial names', () {
    final n = GoDiceDeviceName.tryParse('GoDice_1A2B3C')!;
    expect(n.id, '1A2B3C');
    expect(n.color, isNull);
    expect(n.firmware, isNull);
    expect(
      GoDiceDeviceName.tryParse('GoDice_ABCDEF_K')!.color,
      DiceColor.black,
    );
  });

  test('rejects non GoDice names', () {
    expect(GoDiceDeviceName.tryParse(null), isNull);
    expect(GoDiceDeviceName.tryParse('Pixels Die'), isNull);
    expect(GoDiceDeviceName.isGoDice('GoDice_X'), isTrue);
  });

  test('DieType.tryParse', () {
    expect(DieType.tryParse('D20'), DieType.d20);
    expect(DieType.tryParse('d10x'), DieType.d10x);
    expect(DieType.tryParse('d7'), isNull);
  });
}
