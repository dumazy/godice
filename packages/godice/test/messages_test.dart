import 'dart:typed_data';

import 'package:godice/godice.dart';
import 'package:test/test.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  group('GoDiceMessage.parse', () {
    test('R -> RollStartMessage', () {
      final m = GoDiceMessage.parse(bytes([0x52]), dieType: DieType.d6);
      expect(m, isA<RollStartMessage>());
    });

    test('S xyz -> stable PositionMessage with signed bytes', () {
      // -64 as an unsigned byte is 0xC0 -> D6 face 1.
      final m = GoDiceMessage.parse(
        bytes([0x53, 0xC0, 0x00, 0x00]),
        dieType: DieType.d6,
      );
      final p = m as PositionMessage;
      expect(p.kind, StabilityKind.stable);
      expect(p.isRollResult, isTrue);
      expect(p.xyz, const Vector3(-64, 0, 0));
      expect(p.value, 1);
      expect(p.dieType, DieType.d6);
    });

    test('FS / TS / MS use the xyz at offset 2', () {
      const cases = {
        0x46: StabilityKind.fakeStable,
        0x54: StabilityKind.tiltStable,
        0x4D: StabilityKind.moveStable,
      };
      for (final entry in cases.entries) {
        final m = GoDiceMessage.parse(
          bytes([entry.key, 0x53, 0x40, 0x00, 0x00]),
          dieType: DieType.d6,
        );
        final p = m as PositionMessage;
        expect(p.kind, entry.value);
        expect(p.isRollResult, isFalse);
        expect(p.xyz, const Vector3(64, 0, 0));
        expect(p.value, 6);
      }
    });

    test('position uses the requested die type', () {
      final m = GoDiceMessage.parse(
        bytes([0x53, 0x40, 0x00, 0xEA]),
        dieType: DieType.d20,
      );
      expect((m as PositionMessage).value, 8); // (64, 0, -22)
      final m10 = GoDiceMessage.parse(
        bytes([0x53, 0x40, 0x00, 0xEA]),
        dieType: DieType.d10,
      );
      expect((m10 as PositionMessage).value, 0);
    });

    test('Bat -> BatteryLevelMessage', () {
      final m = GoDiceMessage.parse(
        bytes([0x42, 0x61, 0x74, 87]),
        dieType: DieType.d6,
      );
      expect((m as BatteryLevelMessage).level, 87);
    });

    test('Col -> DiceColorMessage', () {
      final m = GoDiceMessage.parse(
        bytes([0x43, 0x6F, 0x6C, 3]),
        dieType: DieType.d6,
      );
      expect((m as DiceColorMessage).color, DiceColor.blue);
      final unknown = GoDiceMessage.parse(
        bytes([0x43, 0x6F, 0x6C, 42]),
        dieType: DieType.d6,
      );
      expect((unknown as DiceColorMessage).color, isNull);
      expect(unknown.code, 42);
    });

    test('unknown or truncated payloads become UnknownMessage', () {
      expect(
        GoDiceMessage.parse(bytes([]), dieType: DieType.d6),
        isA<UnknownMessage>(),
      );
      expect(
        GoDiceMessage.parse(bytes([0x99, 1, 2]), dieType: DieType.d6),
        isA<UnknownMessage>(),
      );
      expect(
        GoDiceMessage.parse(bytes([0x53, 1]), dieType: DieType.d6),
        isA<UnknownMessage>(),
      );
      expect(
        GoDiceMessage.parse(bytes([0x42, 0x61, 0x74]), dieType: DieType.d6),
        isA<UnknownMessage>(),
      );
    });
  });
}
