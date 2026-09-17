import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

void main() {
  group('BleDevice.fromJson', () {
    test('decodes a full device event payload', () {
      final device = BleDevice.fromJson({
        'id': '657f8cb5-49f4-448e-ad77-a7505e663eeb',
        'address': '',
        'name': 'AirPods Pro',
        'rssi': -48,
        'tx_power': 12,
        'manufacturer_data': {
          '76': [1, 2, 3],
        },
        'service_data': <String, dynamic>{},
        'services': ['180d'],
        'connected': false,
      });

      expect(device.id, '657f8cb5-49f4-448e-ad77-a7505e663eeb');
      expect(device.name, 'AirPods Pro');
      expect(device.rssi, -48);
      expect(device.txPower, 12);
      expect(device.manufacturerData['76'], [1, 2, 3]);
      expect(device.services, ['180d']);
      expect(device.connected, isFalse);
    });

    test('tolerates a minimal payload with nulls', () {
      final device = BleDevice.fromJson({'id': 'abc'});
      expect(device.id, 'abc');
      expect(device.name, isNull);
      expect(device.rssi, isNull);
      expect(device.manufacturerData, isEmpty);
      expect(device.services, isEmpty);
    });
  });

  group('BleService.fromJson', () {
    test('decodes services with characteristics and property flags', () {
      final service = BleService.fromJson({
        'uuid': '0000180d-0000-1000-8000-00805f9b34fb',
        'primary': true,
        'characteristics': [
          {
            'uuid': '00002a37-0000-1000-8000-00805f9b34fb',
            'service_uuid': '0000180d-0000-1000-8000-00805f9b34fb',
            'properties': ['read', 'notify'],
          },
        ],
      });

      expect(service.primary, isTrue);
      expect(service.characteristics, hasLength(1));
      final ch = service.characteristics.single;
      expect(ch.canRead, isTrue);
      expect(ch.canNotify, isTrue);
      expect(ch.canWrite, isFalse);
    });
  });

  group('BleDevice edge cases', () {
    test('fromJson with connected=true', () {
      final device = BleDevice.fromJson({'id': 'd1', 'connected': true});
      expect(device.connected, isTrue);
    });

    test('fromJson with service_data populated', () {
      final device = BleDevice.fromJson({
        'id': 'd1',
        'service_data': {
          '180d': [10, 20],
        },
      });
      expect(device.serviceData['180d'], isNotNull);
      expect(device.serviceData['180d'], [10, 20]);
    });

    test('toString with name and rssi', () {
      const device = BleDevice(id: 'abc', address: '', name: 'Foo', rssi: -60);
      expect(device.toString(), contains('abc'));
      expect(device.toString(), contains('Foo'));
      expect(device.toString(), contains('-60'));
    });

    test('toString without name or rssi', () {
      const device = BleDevice(id: 'abc', address: '');
      expect(device.toString(), contains('(unknown)'));
      expect(device.toString(), contains('?'));
    });
  });

  group('BleCharacteristic property helpers', () {
    test('canWrite is true for write-without-response', () {
      const ch = BleCharacteristic(
        uuid: 'a',
        serviceUuid: 'b',
        properties: ['write-without-response'],
      );
      expect(ch.canWrite, isTrue);
      expect(ch.canRead, isFalse);
      expect(ch.canNotify, isFalse);
    });

    test('canNotify is true for indicate', () {
      const ch = BleCharacteristic(
        uuid: 'a',
        serviceUuid: 'b',
        properties: ['indicate'],
      );
      expect(ch.canNotify, isTrue);
    });

    test('fromJson with missing properties list', () {
      final ch = BleCharacteristic.fromJson({
        'uuid': 'a',
        'service_uuid': 'b',
      });
      expect(ch.properties, isEmpty);
      expect(ch.canRead, isFalse);
    });
  });

  group('BleService edge cases', () {
    test('fromJson with no characteristics key', () {
      final service = BleService.fromJson({
        'uuid': '180d',
      });
      expect(service.uuid, '180d');
      expect(service.primary, isFalse);
      expect(service.characteristics, isEmpty);
    });
  });

  group('PermissionStatus.fromCode', () {
    test('maps native codes', () {
      expect(PermissionStatus.fromCode(0), PermissionStatus.notDetermined);
      expect(PermissionStatus.fromCode(1), PermissionStatus.granted);
      expect(PermissionStatus.fromCode(2), PermissionStatus.denied);
      expect(PermissionStatus.fromCode(3), PermissionStatus.restricted);
      expect(PermissionStatus.fromCode(4), PermissionStatus.unsupported);
    });

    test('unknown code falls back to notDetermined', () {
      expect(PermissionStatus.fromCode(99), PermissionStatus.notDetermined);
      expect(PermissionStatus.fromCode(-1), PermissionStatus.notDetermined);
    });

    test('granted and unsupported are usable; denied is not', () {
      expect(PermissionStatus.granted.isUsable, isTrue);
      expect(PermissionStatus.unsupported.isUsable, isTrue);
      expect(PermissionStatus.denied.isUsable, isFalse);
    });

    test('notDetermined and restricted are not usable', () {
      expect(PermissionStatus.notDetermined.isUsable, isFalse);
      expect(PermissionStatus.restricted.isUsable, isFalse);
    });
  });

  group('AdapterState.fromNative', () {
    test('maps btleplug CentralState strings', () {
      expect(AdapterState.fromNative('poweredon'), AdapterState.poweredOn);
      expect(AdapterState.fromNative('poweredoff'), AdapterState.poweredOff);
      expect(AdapterState.fromNative('unknown'), AdapterState.unknown);
    });

    test('is case-insensitive and defaults unrecognized to unknown', () {
      expect(AdapterState.fromNative('PoweredOn'), AdapterState.poweredOn);
      expect(AdapterState.fromNative('something-else'), AdapterState.unknown);
    });
  });

  group('BleConnectionState', () {
    test('carries the device id and connected flag', () {
      const s = BleConnectionState(deviceId: 'abc', connected: true);
      expect(s.deviceId, 'abc');
      expect(s.connected, isTrue);
      expect(s.toString(), contains('connected'));
      expect(
        const BleConnectionState(deviceId: 'abc', connected: false).toString(),
        contains('disconnected'),
      );
    });
  });
}
