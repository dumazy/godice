import '../models.dart';
// Selects the real user-agent based detection on the web and a stub that always
// returns [WebBrowser.unknown] off the web, so importing this never pulls in
// `dart:js_interop` where it does not exist.
import 'web_browser_stub.dart'
    if (dart.library.js_interop) 'web_browser_web.dart'
    as impl;
import 'web_browser_types.dart';

export 'web_browser_types.dart';

/// Identifies the current web browser (see [WebBrowser]).
///
/// Returns [WebBrowser.unknown] off the web.
WebBrowser detectWebBrowser() => impl.detectWebBrowser();

/// Actionable, per-browser advice for getting Web Bluetooth working.
///
/// Build one with [webBluetoothGuidance]. A UI (such as the example app's
/// permission banner) can render [message], and [settingsUrl] when present, so
/// the user knows what to do in whichever browser they are using.
class WebBluetoothGuidance {
  const WebBluetoothGuidance({
    required this.browser,
    required this.supported,
    required this.message,
    this.settingsUrl,
  });

  /// The browser this guidance describes.
  final WebBrowser browser;

  /// Whether this browser implements Web Bluetooth at all. `false` for Firefox
  /// and Safari, which expose no `navigator.bluetooth`; the UI should make clear
  /// that scanning cannot work here regardless of permission state.
  final bool supported;

  /// A short, human-readable instruction for the user.
  final String message;

  /// A browser-internal configuration URL that enables Web Bluetooth (e.g.
  /// `brave://flags/#brave-web-bluetooth-api`), when one applies; otherwise
  /// `null`.
  ///
  /// Browsers refuse programmatic navigation to these internal URLs, so present
  /// it as copyable text, not a link the app opens.
  final String? settingsUrl;
}

/// Builds [WebBluetoothGuidance] for the current browser and permission [status].
///
/// Pass an explicit [browser] to override detection (used in tests); it defaults
/// to [detectWebBrowser]. The message logic is pure, so it runs and is testable
/// anywhere, returning the generic message for [WebBrowser.unknown] off the web.
WebBluetoothGuidance webBluetoothGuidance(
  PermissionStatus status, {
  WebBrowser? browser,
}) {
  final b = browser ?? detectWebBrowser();
  switch (b) {
    case WebBrowser.firefox:
      return const WebBluetoothGuidance(
        browser: WebBrowser.firefox,
        supported: false,
        message:
            'Firefox does not support Web Bluetooth. Use a Chromium browser '
            '(Chrome, Edge, Brave, or Opera) to scan for devices.',
      );
    case WebBrowser.safari:
      return const WebBluetoothGuidance(
        browser: WebBrowser.safari,
        supported: false,
        message:
            'Safari does not support Web Bluetooth. Use a Chromium browser '
            '(Chrome, Edge, Brave, or Opera) to scan for devices.',
      );
    case WebBrowser.brave:
      return WebBluetoothGuidance(
        browser: WebBrowser.brave,
        supported: true,
        message: status.isUsable
            ? 'Brave is ready for Web Bluetooth.'
            : 'Brave disables Web Bluetooth by default. Enable it at '
                  'brave://flags/#brave-web-bluetooth-api, relaunch Brave, and '
                  'reload this page. Also make sure Bluetooth is turned on.',
        settingsUrl: 'brave://flags/#brave-web-bluetooth-api',
      );
    case WebBrowser.chrome:
    case WebBrowser.edge:
    case WebBrowser.opera:
      final name = switch (b) {
        WebBrowser.edge => 'Edge',
        WebBrowser.opera => 'Opera',
        _ => 'Chrome',
      };
      return WebBluetoothGuidance(
        browser: b,
        supported: true,
        message: status.isUsable
            ? '$name is ready for Web Bluetooth.'
            : '$name supports Web Bluetooth, but no adapter is available. Turn '
                  'Bluetooth on (and allow this site to use it), then reload. '
                  'On Linux, also enable chrome://flags/#enable-web-bluetooth.',
      );
    case WebBrowser.unknown:
      return WebBluetoothGuidance(
        browser: WebBrowser.unknown,
        supported: true,
        message: status.isUsable
            ? 'This browser appears ready for Web Bluetooth.'
            : 'Web Bluetooth needs a Chromium browser (Chrome, Edge, Brave, or '
                  'Opera) with Bluetooth turned on. Turn Bluetooth on, then '
                  'reload.',
      );
  }
}
