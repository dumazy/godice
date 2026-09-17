import 'web_browser_types.dart';

/// Off the web there is no browser to detect, so this is always
/// [WebBrowser.unknown]. The web implementation lives in `web_browser_web.dart`
/// and is selected by the conditional import in `web_browser.dart`.
WebBrowser detectWebBrowser() => WebBrowser.unknown;
