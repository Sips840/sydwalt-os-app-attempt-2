import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sydwalt_os/src/config.dart';
import 'package:sydwalt_os/src/settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts on the default server home page', () async {
    final s = await SettingsStore.open();
    expect(s.serverUrl, AppConfig.defaultServerUrl);
    expect(s.isDefaultServer, isTrue);
    expect(s.startUrl, '${AppConfig.defaultServerUrl}/');
  });

  test('reopens the last app page after a restart', () async {
    final s = await SettingsStore.open();
    await s.rememberUrl('${AppConfig.defaultServerUrl}/#/minutes');
    final again = SettingsStore(await SharedPreferences.getInstance());
    expect(again.startUrl, '${AppConfig.defaultServerUrl}/#/minutes');
  });

  test('never remembers API calls or other sites', () async {
    final s = await SettingsStore.open();
    await s.rememberUrl('${AppConfig.defaultServerUrl}/api/files/x?token=y');
    await s.rememberUrl('https://example.com/');
    expect(s.startUrl, '${AppConfig.defaultServerUrl}/');
  });

  test('changing server forgets the last page and notifies', () async {
    final s = await SettingsStore.open();
    await s.rememberUrl('${AppConfig.defaultServerUrl}/#/finance');
    var notified = 0;
    s.addListener(() => notified++);
    await s.setServerUrl('staging.example.com/');
    expect(s.serverUrl, 'https://staging.example.com');
    expect(s.isDefaultServer, isFalse);
    expect(s.startUrl, 'https://staging.example.com/');
    expect(notified, 1);

    await s.resetServerUrl();
    expect(s.serverUrl, AppConfig.defaultServerUrl);
    expect(notified, 2);
  });

  test('setting the same server again does nothing', () async {
    final s = await SettingsStore.open();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setServerUrl('${AppConfig.defaultServerUrl}/');
    expect(notified, 0);
  });
}
