import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sydwalt_os/src/screens/settings_screen.dart';
import 'package:sydwalt_os/src/settings_store.dart';

void main() {
  late SettingsStore settings;
  final requested = <Uri>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Sydwalt OS',
      packageName: 'za.co.sydwalt.os',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );
    settings = await SettingsStore.open();
    requested.clear();
  });

  Future<void> pump(WidgetTester tester, {int status = 200, Future<void> Function()? onClear}) async {
    final client = MockClient((req) async {
      requested.add(req.url);
      return http.Response('ok', status);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(settings: settings, onClearWebData: onClear ?? () async {}, httpClient: client),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the version and the current server', (tester) async {
    await pump(tester);
    expect(find.text('Sydwalt OS app 1.0.0 (1)'), findsOneWidget);
    expect(find.widgetWithText(TextField, settings.serverUrl), findsOneWidget);
  });

  testWidgets('rejects an unencrypted public address with a reason', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'http://example.com');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use https://'), findsOneWidget);
    expect(requested, isEmpty);
  });

  testWidgets('tests /healthz and saves a reachable server', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'staging.example.com');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(requested.single.toString(), 'https://staging.example.com/healthz');
    expect(settings.serverUrl, 'https://staging.example.com');
    expect(find.text('Connected. The server is running.'), findsOneWidget);
    expect(find.text('Use the standard server'), findsOneWidget);
  });

  testWidgets('asks before saving a server that did not answer', (tester) async {
    await pump(tester, status: 503);
    await tester.enterText(find.byType(TextField), 'staging.example.com');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Server not reachable'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.isDefaultServer, isTrue);
  });

  testWidgets('sign out asks for confirmation before clearing', (tester) async {
    var cleared = 0;
    await pump(tester, onClear: () async => cleared++);
    await tester.tap(find.text('Sign out and clear app data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cleared, 0);

    await tester.tap(find.text('Sign out and clear app data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out and clear'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });
}
