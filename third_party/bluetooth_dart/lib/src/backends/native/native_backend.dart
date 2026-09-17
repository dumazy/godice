import '../../bluetooth_backend.dart';

// Selects the FFI implementation on native platforms and a web stub on the web,
// so importing `bluetooth_dart` never pulls in `dart:ffi` where it does not
// exist.
import 'native_backend_ffi.dart'
    if (dart.library.js_interop) 'native_backend_web.dart'
    as impl;

/// Returns the default native backend for this platform, or `null` when none
/// applies (e.g. the web until a Web Bluetooth backend ships).
BluetoothBackend? createNativeBackend() => impl.createNativeBackend();
