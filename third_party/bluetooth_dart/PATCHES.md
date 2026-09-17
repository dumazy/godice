# Local patches to bluetooth_dart 0.0.1

Vendored from pub.dev (`bluetooth_dart` 0.0.1, MIT). The upstream package is
used unchanged except for:

1. `lib/src/backends/native/native_backend_ffi.dart` – `FfiBackend.subscribe`
   crashed on the Dart VM with
   `Illegal argument in isolate message: object is unsendable ... _Timer`.
   The `Isolate.run` closures inside `onListen`/`onCancel` shared the method's
   context, which captured the stream controller and `this` (with the `_poll`
   `Timer`). They now go through a static helper `_runVoidOp` that captures
   only its parameters.

Drop this directory (and the `third_party/bluetooth_dart` workspace entry)
once a fixed version is published.
