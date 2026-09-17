import 'dart:js_interop';

import 'web_browser_types.dart';

// `package:web` ships no `navigator.brave`, and reading `navigator.userAgent` is
// simplest bound directly, so the slice this needs is bound here (mirroring the
// Web Bluetooth bindings in `native_backend_web.dart`).
@JS('navigator.userAgent')
external String get _userAgent;

// Brave-only marker object; absent (so null here) in every other browser.
@JS('navigator.brave')
external JSObject? get _brave;

/// Identifies the browser from the user agent.
///
/// Brave shares Chrome's user agent, so it is detected first via its
/// `navigator.brave` marker. Order otherwise matters because the Edge and Opera
/// user-agent strings also contain `Chrome`.
WebBrowser detectWebBrowser() {
  if (_brave != null) return WebBrowser.brave;

  final ua = _userAgent;
  if (ua.contains('Edg/') || ua.contains('Edg ') || ua.contains('Edge/')) {
    return WebBrowser.edge;
  }
  if (ua.contains('OPR/') || ua.contains('Opera')) return WebBrowser.opera;
  if (ua.contains('Firefox/')) return WebBrowser.firefox;
  if (ua.contains('Chrome/') || ua.contains('Chromium/')) {
    return WebBrowser.chrome;
  }
  // Safari's user agent contains `Safari` but not `Chrome`.
  if (ua.contains('Safari/')) return WebBrowser.safari;
  return WebBrowser.unknown;
}
