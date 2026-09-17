@TestOn('browser')
library;

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

/// Exercises the web build of `bluetooth_dart`. The `WebBluetoothBackend` is
/// always registered on the web, but reports `isAvailable == false` when the
/// browser exposes no `navigator.bluetooth`. That covers Firefox, Chromium
/// without the flag, and the headless Chrome this test runs in. In that case
/// selection must fall through to the unsupported floor rather than crash.
///
/// Run with `dart test -p chrome test/web_backend_test.dart`.
void main() {
  final bt = Bluetooth.instance;

  tearDown(() async => bt.reset());

  test('selects a backend without throwing on the web', () {
    expect(bt.backend.name, anyOf('web', 'unsupported'));
  });

  test('permission resolves to a usable-or-denied status', () async {
    final status = await bt.permissionStatus();
    expect(status, isA<PermissionStatus>());
  });

  test('startScan resolves (or surfaces a Bluetooth error)', () async {
    // With no adapter or gesture this either yields the empty unsupported scan
    // or throws a BluetoothException. Either outcome is acceptable here; a crash
    // would not be.
    try {
      final scan = await bt.startScan();
      expect(scan, isNotNull);
      await scan.stop();
    } on BluetoothException {
      // Expected when Web Bluetooth is present but no scan can start here.
    }
  });

  test('detects a concrete browser and yields matching guidance', () async {
    final browser = detectWebBrowser();
    // The test runner drives a real browser, so detection must not be unknown.
    expect(browser, isNot(WebBrowser.unknown));

    final guidance = webBluetoothGuidance(
      await bt.permissionStatus(),
      browser: browser,
    );
    expect(guidance.browser, browser);
    expect(guidance.message, isNotEmpty);
    // Firefox/Safari can't run a Web Bluetooth scan; Chromium can. The CHROME
    // executable package:test uses is Chromium, so support is expected here,
    // but assert the invariant generically rather than hard-coding the browser.
    final isChromium = {
      WebBrowser.chrome,
      WebBrowser.edge,
      WebBrowser.brave,
      WebBrowser.opera,
    }.contains(browser);
    expect(guidance.supported, isChromium);
  });
}
