import 'dart:async';

import 'package:godice/godice.dart';
import 'package:universal_ble/universal_ble.dart';

/// Finds nearby GoDice through `universal_ble`.
///
/// Scanning in `universal_ble` is a single global state, so by default this
/// class only *filters* `UniversalBle.scanStream` for dice and leaves
/// starting and stopping the scan to the app. Pass [manageScan] `true` for
/// the scanner to start a scan when [discover] gets its first listener and
/// stop it when the last one cancels.
class GoDiceScanner {
  /// Creates a scanner. See the class docs for [manageScan].
  GoDiceScanner({this.manageScan = false});

  /// Whether this scanner starts and stops the BLE scan itself.
  final bool manageScan;

  /// Checks that Bluetooth is available and permissions are granted,
  /// prompting where the platform requires it (Android runtime permissions).
  /// Throws [GoDiceTransportException] when Bluetooth cannot be used.
  Future<void> ensureReady() async {
    try {
      if (BleCapabilities.requiresRuntimePermission &&
          !await UniversalBle.hasPermissions()) {
        await UniversalBle.requestPermissions();
      }
      final state = await UniversalBle.getBluetoothAvailabilityState();
      if (state != BleAvailabilityStateX.poweredOn) {
        throw GoDiceTransportException('Bluetooth is ${state.name}');
      }
    } on GoDiceTransportException {
      rethrow;
    } on Object catch (e) {
      throw GoDiceTransportException('Bluetooth is unavailable', e);
    }
  }

  /// Streams every GoDice advertisement seen. The same die may appear
  /// repeatedly with an updated RSSI.
  ///
  /// With [manageScan] the scan runs while this stream has listeners;
  /// otherwise the app must be scanning for anything to arrive.
  Stream<BleDevice> discover() {
    late StreamController<BleDevice> controller;
    StreamSubscription<BleDevice>? sub;
    var startedScan = false;

    Future<void> start() async {
      sub = UniversalBle.scanStream
          .where((d) => GoDiceDeviceName.isGoDice(d.name))
          .listen(controller.add, onError: controller.addError);
      if (!manageScan) return;
      try {
        await ensureReady();
        await UniversalBle.startScan(
          scanFilter: ScanFilter(withNamePrefix: const ['GoDice']),
        );
        startedScan = true;
      } on Object catch (e, s) {
        controller.addError(
          e is GoDiceTransportException
              ? e
              : GoDiceTransportException('Failed to start scanning', e),
          s,
        );
        await controller.close();
      }
    }

    Future<void> stop() async {
      await sub?.cancel();
      if (startedScan) {
        try {
          await UniversalBle.stopScan();
        } on Object {
          // Bluetooth may have gone away; nothing to stop.
        }
      }
    }

    controller = StreamController<BleDevice>(onListen: start, onCancel: stop);
    return controller.stream;
  }

  /// Collects the dice seen during [timeout], strongest signal first.
  Future<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final seen = <String, BleDevice>{};
    Object? error;
    final sub = discover().listen(
      (d) => seen[d.deviceId] = d,
      onError: (Object e) => error ??= e,
    );
    try {
      await Future<void>.delayed(timeout);
    } finally {
      await sub.cancel();
    }
    if (error != null && seen.isEmpty) throw error!;
    return seen.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
  }

  /// Waits for a die whose name or id contains [query] (case-insensitive),
  /// or for the first die when [query] is `null`. Returns `null` on
  /// [timeout].
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
                d.deviceId.toLowerCase().contains(needle),
          )
          .first
          .timeout(timeout);
    } on TimeoutException {
      return null;
    } on StateError {
      return null; // stream closed without a match
    }
  }
}

/// Small alias so the powered-on check reads clearly.
extension BleAvailabilityStateX on AvailabilityState {
  /// The state in which scanning and connecting work.
  static const AvailabilityState poweredOn = AvailabilityState.poweredOn;
}
