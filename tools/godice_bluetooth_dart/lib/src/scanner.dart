import 'dart:async';

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:godice/godice.dart';

/// Finds nearby GoDice.
///
/// GoDice do not always include the service UUID in their advertisement, so
/// the scan is unfiltered at the BLE level and dice are recognised by their
/// `GoDice_` name prefix instead.
class GoDiceScanner {
  /// Creates a scanner. Uses [Bluetooth.instance] unless [bluetooth] is given.
  GoDiceScanner({Bluetooth? bluetooth})
    : _bluetooth = bluetooth ?? Bluetooth.instance;

  final Bluetooth _bluetooth;

  /// Makes sure Bluetooth may be used, prompting for permission on platforms
  /// that need it (macOS/iOS). Throws [GoDiceTransportException] when denied.
  Future<void> ensurePermission() async {
    final PermissionStatus status;
    try {
      status = await _bluetooth.requestPermission();
    } on BluetoothException catch (e) {
      throw GoDiceTransportException('Bluetooth is unavailable', e);
    }
    if (!status.isUsable) {
      throw GoDiceTransportException('Bluetooth permission is ${status.name}');
    }
  }

  /// Streams every GoDice advertisement seen until the returned stream is
  /// cancelled. The same die may appear repeatedly with updated RSSI.
  Stream<BleDevice> discover() {
    late StreamController<BleDevice> controller;
    ScanSession? session;
    StreamSubscription<BleDevice>? sub;

    Future<void> start() async {
      try {
        await ensurePermission();
        session = await _bluetooth.startScan();
        sub = session!.devices
            .where((d) => GoDiceDeviceName.isGoDice(d.name))
            .listen(controller.add, onError: controller.addError);
      } on Object catch (e, s) {
        controller.addError(e, s);
        await controller.close();
      }
    }

    Future<void> stop() async {
      await sub?.cancel();
      await session?.stop();
    }

    controller = StreamController<BleDevice>(onListen: start, onCancel: stop);
    return controller.stream;
  }

  /// Scans for [timeout] and returns the dice seen, strongest signal first.
  Future<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final seen = <String, BleDevice>{};
    final sub = discover().listen((d) => seen[d.id] = d);
    try {
      await Future<void>.delayed(timeout);
    } finally {
      await sub.cancel();
    }
    return seen.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
  }

  /// Scans until a die whose name or id contains [query] appears, or
  /// [timeout] elapses (then returns `null`). With a `null` [query] the first
  /// die seen is returned.
  Future<BleDevice?> find(
    String? query, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final needle = query?.toLowerCase();
    try {
      return await discover()
          .where(
            (d) =>
                needle == null ||
                (d.name?.toLowerCase().contains(needle) ?? false) ||
                d.id.toLowerCase().contains(needle),
          )
          .first
          .timeout(timeout);
    } on TimeoutException {
      return null;
    } on StateError {
      // Stream closed without a match (e.g. permission error already surfaced).
      return null;
    }
  }
}
