import 'package:godice/godice.dart';
import 'package:test/test.dart';

void main() {
  group('GoDiceShells.closestFace', () {
    for (final shell in Shell.values) {
      test('recovers every face of ${shell.name} from its own vector', () {
        final table = GoDiceShells.vectorsFor(shell);
        expect(table, hasLength(shell.faces));
        for (final entry in table.entries) {
          expect(GoDiceShells.closestFace(shell, entry.value), entry.key);
        }
      });

      test('tolerates noise on ${shell.name}', () {
        final table = GoDiceShells.vectorsFor(shell);
        for (final entry in table.entries) {
          final v = entry.value;
          final noisy = Vector3(v.x + 5, v.y - 4, v.z + 3);
          expect(GoDiceShells.closestFace(shell, noisy), entry.key);
        }
      });
    }
  });

  group('GoDiceShells.rolledValue', () {
    test('D6 maps the official vectors 1-6', () {
      expect(GoDiceShells.rolledValue(DieType.d6, const Vector3(-64, 0, 0)), 1);
      expect(GoDiceShells.rolledValue(DieType.d6, const Vector3(0, 0, 64)), 2);
      expect(GoDiceShells.rolledValue(DieType.d6, const Vector3(0, 64, 0)), 3);
      expect(GoDiceShells.rolledValue(DieType.d6, const Vector3(0, -64, 0)), 4);
      expect(GoDiceShells.rolledValue(DieType.d6, const Vector3(0, 0, -64)), 5);
      expect(GoDiceShells.rolledValue(DieType.d6, const Vector3(64, 0, 0)), 6);
    });

    test('D20 face 1 and 20', () {
      expect(
        GoDiceShells.rolledValue(DieType.d20, const Vector3(-64, 0, -22)),
        1,
      );
      expect(
        GoDiceShells.rolledValue(DieType.d20, const Vector3(64, 0, 22)),
        20,
      );
    });

    test('D10 and D10X apply the D20 transforms', () {
      // D20 face 8 -> 0 / 00, face 7 -> 9 / 90.
      expect(
        GoDiceShells.rolledValue(DieType.d10, const Vector3(64, 0, -22)),
        0,
      );
      expect(
        GoDiceShells.rolledValue(DieType.d10x, const Vector3(64, 0, -22)),
        0,
      );
      expect(
        GoDiceShells.rolledValue(DieType.d10, const Vector3(-42, -42, -42)),
        9,
      );
      expect(
        GoDiceShells.rolledValue(DieType.d10x, const Vector3(-42, -42, -42)),
        90,
      );
    });

    test('D4/D8/D12 apply the D24 transforms', () {
      // D24 face 1 -> D4 3, D8 3, D12 1.
      const face1 = Vector3(20, -60, -20);
      expect(GoDiceShells.rolledValue(DieType.d4, face1), 3);
      expect(GoDiceShells.rolledValue(DieType.d8, face1), 3);
      expect(GoDiceShells.rolledValue(DieType.d12, face1), 1);
      // D24 face 24 -> D4 2, D8 6, D12 12.
      const face24 = Vector3(-20, 60, 20);
      expect(GoDiceShells.rolledValue(DieType.d4, face24), 2);
      expect(GoDiceShells.rolledValue(DieType.d8, face24), 6);
      expect(GoDiceShells.rolledValue(DieType.d12, face24), 12);
    });

    test('every transform covers exactly the values of its die', () {
      expect(GoDiceShells.d10Transform.values.toSet(), {
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      });
      expect(GoDiceShells.d10XTransform.values.toSet(), {
        0,
        10,
        20,
        30,
        40,
        50,
        60,
        70,
        80,
        90,
      });
      expect(GoDiceShells.d4Transform.values.toSet(), {1, 2, 3, 4});
      expect(GoDiceShells.d8Transform.values.toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
      expect(
        GoDiceShells.d12Transform.values.toSet(),
        List<int>.generate(12, (i) => i + 1).toSet(),
      );
      // D10/D10X/D12 use each value twice and D8 three times. (The official
      // D4 table is uneven: 7/6/5/6 faces for 1/2/3/4, copied as published.)
      for (final t in [
        GoDiceShells.d10Transform,
        GoDiceShells.d10XTransform,
        GoDiceShells.d12Transform,
      ]) {
        for (final v in t.values.toSet()) {
          expect(t.values.where((x) => x == v).length, 2);
        }
      }
      expect(GoDiceShells.d4Transform, hasLength(24));
      for (var v = 1; v <= 8; v++) {
        expect(GoDiceShells.d8Transform.values.where((x) => x == v).length, 3);
      }
    });
  });
}
