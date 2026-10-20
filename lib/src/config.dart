/// Build-time configuration.
///
/// The default server is the production Fly.io deployment. Override it for a
/// staging or local build with:
///
///   flutter run --dart-define=SYDWALT_URL=https://staging.example.com
///
/// Staff can also change it at runtime from Settings, which is stored on the
/// device and wins over this default (see SettingsStore).
class AppConfig {
  static const String defaultServerUrl = String.fromEnvironment(
    'SYDWALT_URL',
    defaultValue: 'https://sydwalt-os-3f9ywa.fly.dev',
  );

  /// Appended to the WebView's user agent so the server (or the web app) can
  /// tell requests from the installed app apart from a normal browser.
  static const String userAgentSuffix = 'SydwaltOSApp/1.0';

  /// Brand colour, matching manifest.json's theme_color in the web app.
  static const int brandColor = 0xFF042F3B;
}
