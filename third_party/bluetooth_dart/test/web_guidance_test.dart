@TestOn('vm')
library;

import 'package:bluetooth_dart/bluetooth_dart.dart';
import 'package:test/test.dart';

/// Unit tests for the pure [webBluetoothGuidance] message logic. These pass an
/// explicit [WebBrowser] so they run on the VM, independent of any browser.
/// Browser-side detection is covered by `web_backend_test.dart`.
void main() {
  group('webBluetoothGuidance', () {
    test('Firefox is unsupported with Chromium advice', () {
      final g = webBluetoothGuidance(
        PermissionStatus.unsupported,
        browser: WebBrowser.firefox,
      );
      expect(g.browser, WebBrowser.firefox);
      expect(g.supported, isFalse);
      expect(g.settingsUrl, isNull);
      expect(g.message.toLowerCase(), contains('firefox'));
      expect(g.message.toLowerCase(), contains('chromium'));
    });

    test('Safari is unsupported with Chromium advice', () {
      final g = webBluetoothGuidance(
        PermissionStatus.unsupported,
        browser: WebBrowser.safari,
      );
      expect(g.supported, isFalse);
      expect(g.settingsUrl, isNull);
      expect(g.message.toLowerCase(), contains('safari'));
    });

    test('Brave is supported and surfaces its flag URL when not usable', () {
      final g = webBluetoothGuidance(
        PermissionStatus.denied,
        browser: WebBrowser.brave,
      );
      expect(g.supported, isTrue);
      expect(g.settingsUrl, 'brave://flags/#brave-web-bluetooth-api');
      expect(g.message, contains('brave://flags/#brave-web-bluetooth-api'));
    });

    test('Brave reports ready once usable', () {
      final g = webBluetoothGuidance(
        PermissionStatus.granted,
        browser: WebBrowser.brave,
      );
      expect(g.supported, isTrue);
      expect(g.message.toLowerCase(), contains('ready'));
    });

    test('Chrome/Edge/Opera are supported with no flag URL', () {
      for (final b in [WebBrowser.chrome, WebBrowser.edge, WebBrowser.opera]) {
        final g = webBluetoothGuidance(PermissionStatus.denied, browser: b);
        expect(g.supported, isTrue, reason: '$b should be supported');
        expect(g.settingsUrl, isNull, reason: '$b needs no flag URL');
      }
      final name = webBluetoothGuidance(
        PermissionStatus.denied,
        browser: WebBrowser.edge,
      );
      expect(name.message, contains('Edge'));
    });

    test('Chrome reports ready when usable', () {
      final g = webBluetoothGuidance(
        PermissionStatus.granted,
        browser: WebBrowser.chrome,
      );
      expect(g.message, contains('Chrome'));
      expect(g.message.toLowerCase(), contains('ready'));
    });

    test('unknown browser falls back to a generic Chromium hint', () {
      final g = webBluetoothGuidance(
        PermissionStatus.denied,
        browser: WebBrowser.unknown,
      );
      expect(g.supported, isTrue);
      expect(g.message.toLowerCase(), contains('chromium'));
    });
  });

  test('detectWebBrowser is unknown off the web (VM)', () {
    expect(detectWebBrowser(), WebBrowser.unknown);
  });
}
