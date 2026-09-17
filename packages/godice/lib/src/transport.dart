import 'dart:typed_data';

/// The BLE link to one GoDice, abstracted so the protocol layer can run on
/// any Bluetooth stack.
///
/// An implementation is responsible for:
///  * connecting to the peripheral and (if the stack requires it) discovering
///    services,
///  * writing bytes to `GoDiceProtocol.writeCharacteristicUuid`,
///  * subscribing to `GoDiceProtocol.notifyCharacteristicUuid` and emitting
///    every notification on [notifications].
abstract interface class GoDiceTransport {
  /// Connects and starts delivering notifications. Completes once the die is
  /// ready to receive commands.
  Future<void> connect();

  /// Disconnects. Safe to call when not connected.
  Future<void> disconnect();

  /// Whether the link is currently up.
  bool get isConnected;

  /// Writes [data] to the die's command characteristic.
  Future<void> write(Uint8List data);

  /// Raw notifications from the die. Must be a broadcast stream that stays
  /// open across reconnects.
  Stream<Uint8List> get notifications;

  /// `true` when the link comes up and `false` when it drops, including
  /// unexpected disconnects. Must be a broadcast stream.
  Stream<bool> get connectionState;

  /// Releases resources held by the transport. The transport is unusable
  /// afterwards.
  Future<void> dispose();
}

/// Thrown by transports for BLE-level failures.
class GoDiceTransportException implements Exception {
  /// Creates an exception with a human-readable [message] and optional
  /// underlying [cause].
  const GoDiceTransportException(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// The underlying error from the BLE stack, if any.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'GoDiceTransportException: $message'
      : 'GoDiceTransportException: $message ($cause)';
}
