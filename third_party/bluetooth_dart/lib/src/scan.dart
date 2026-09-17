import 'models.dart';

/// A controllable BLE scan.
///
/// Returned by `Bluetooth.startScan` / `BluetoothBackend.startScan`. The
/// [devices] stream emits a [BleDevice] each time a peripheral is discovered or
/// its advertisement updates (so the same id may appear repeatedly with fresher
/// RSSI/name). Call [stop] to end the scan and close the stream.
abstract class ScanSession {
  /// A broadcast stream of discovered/updated devices. Listening late is
  /// allowed but misses earlier events.
  Stream<BleDevice> get devices;

  /// Whether the scan is still running.
  bool get isScanning;

  /// Stops the scan and closes [devices]. Safe to call more than once.
  Future<void> stop();
}
