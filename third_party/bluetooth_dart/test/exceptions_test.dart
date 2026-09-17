import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

void main() {
  group('BluetoothException', () {
    test('stores and exposes its message', () {
      const e = BluetoothException('something broke');
      expect(e.message, 'something broke');
    });

    test('toString includes the class name and message', () {
      const e = BluetoothException('oops');
      expect(e.toString(), 'BluetoothException: oops');
    });

    test('implements Exception', () {
      const e = BluetoothException('x');
      expect(e, isA<Exception>());
    });
  });

  group('NoBackendAvailableException', () {
    test('has a default message when none is provided', () {
      const e = NoBackendAvailableException();
      expect(e.message, contains('No Bluetooth backend'));
    });

    test('accepts a custom message', () {
      const e = NoBackendAvailableException('custom');
      expect(e.message, 'custom');
    });

    test('is a BluetoothException', () {
      const e = NoBackendAvailableException();
      expect(e, isA<BluetoothException>());
    });
  });

  group('PermissionDeniedException', () {
    test('has a default message', () {
      const e = PermissionDeniedException();
      expect(e.message, contains('denied'));
    });

    test('accepts a custom message', () {
      const e = PermissionDeniedException('nope');
      expect(e.message, 'nope');
    });

    test('is a BluetoothException', () {
      const e = PermissionDeniedException();
      expect(e, isA<BluetoothException>());
    });
  });

  group('BleException', () {
    test('stores its message', () {
      const e = BleException('scan failed');
      expect(e.message, 'scan failed');
    });

    test('is a BluetoothException', () {
      const e = BleException('x');
      expect(e, isA<BluetoothException>());
    });
  });
}
