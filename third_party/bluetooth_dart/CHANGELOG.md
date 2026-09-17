## 0.0.1

- Initial scaffold: pure-Dart Bluetooth LE over FFI (Rust `bluetooth_core` /
  btleplug) with a pluggable backend registry.
- Permission status/request, scan (discovered-device stream), connect,
  discover services, read, write, and notification subscriptions.
- Scan path verified on macOS; deeper operations implemented but not yet
  hardware-verified. Web falls through to an unsupported floor (Web Bluetooth
  backend planned).
