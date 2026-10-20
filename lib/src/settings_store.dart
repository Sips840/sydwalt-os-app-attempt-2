import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'link_policy.dart';

/// Device-level settings that survive restarts.
///
/// The web app's own data (sign-in token, drafts, the offline copy of the
/// company book) lives in the WebView's localStorage, which the WebView keeps
/// on disk by itself. This store only holds what the shell owns.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs);

  static const _kServerUrl = 'server_url';
  static const _kLastUrl = 'last_url';

  final SharedPreferences _prefs;

  static Future<SettingsStore> open() async => SettingsStore(await SharedPreferences.getInstance());

  String get serverUrl => LinkPolicy.normaliseServerUrl(_prefs.getString(_kServerUrl) ?? AppConfig.defaultServerUrl);

  bool get isDefaultServer => serverUrl == LinkPolicy.normaliseServerUrl(AppConfig.defaultServerUrl);

  Future<void> setServerUrl(String url) async {
    final normalised = LinkPolicy.normaliseServerUrl(url);
    if (normalised == serverUrl) return;
    await _prefs.setString(_kServerUrl, normalised);
    // A page from the old server must not be reopened against the new one.
    await _prefs.remove(_kLastUrl);
    notifyListeners();
  }

  Future<void> resetServerUrl() async {
    await _prefs.remove(_kServerUrl);
    await _prefs.remove(_kLastUrl);
    notifyListeners();
  }

  /// The page to open at launch: the last screen the person was on (so a
  /// restart or an OS kill lands them back where they were), or the home page.
  String get startUrl {
    final policy = LinkPolicy(serverUrl);
    return policy.restorableUrl(_prefs.getString(_kLastUrl)) ?? '$serverUrl/';
  }

  Future<void> rememberUrl(String? url) async {
    final keep = LinkPolicy(serverUrl).restorableUrl(url);
    if (keep == null || keep == _prefs.getString(_kLastUrl)) return;
    await _prefs.setString(_kLastUrl, keep);
  }

  Future<void> forgetLastUrl() => _prefs.remove(_kLastUrl);
}
