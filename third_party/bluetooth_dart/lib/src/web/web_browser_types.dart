/// A web browser, identified so Web Bluetooth guidance can be tailored to it.
///
/// Web Bluetooth availability differs sharply between browsers: Chrome, Edge,
/// and Opera ship it enabled; Brave gates it behind a flag; Firefox and Safari
/// do not implement it at all, so per-browser advice is more useful than a
/// single generic message. See [detectWebBrowser] and [webBluetoothGuidance].
///
/// Off the web (Dart VM/CLI, or native Flutter builds) detection always yields
/// [unknown], since there is no browser.
enum WebBrowser {
  /// Google Chrome (Chromium). Web Bluetooth on by default.
  chrome,

  /// Microsoft Edge (Chromium). Web Bluetooth on by default.
  edge,

  /// Brave (Chromium). Web Bluetooth present but disabled by default.
  brave,

  /// Opera (Chromium). Web Bluetooth on by default.
  opera,

  /// Mozilla Firefox. Does not implement Web Bluetooth.
  firefox,

  /// Apple Safari. Does not implement Web Bluetooth.
  safari,

  /// Not a recognized browser, or not running on the web at all.
  unknown,
}
