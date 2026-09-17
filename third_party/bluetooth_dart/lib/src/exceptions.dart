/// Base class for all errors thrown by `bluetooth_dart`.
class BluetoothException implements Exception {
  const BluetoothException(this.message);

  final String message;

  @override
  String toString() => 'BluetoothException: $message';
}

/// Thrown when no registered backend can run in the current environment.
class NoBackendAvailableException extends BluetoothException {
  const NoBackendAvailableException([
    super.message =
        'No Bluetooth backend is available in this environment. '
        'Register one with Bluetooth.registerBackend, or use bluetooth_flutter.',
  ]);
}

/// Thrown when Bluetooth access is denied or restricted by the OS.
class PermissionDeniedException extends BluetoothException {
  const PermissionDeniedException([
    super.message = 'Bluetooth permission was denied.',
  ]);
}

/// Thrown when the native BLE layer reports a failure (scan, connect, I/O).
class BleException extends BluetoothException {
  const BleException(super.message);
}
