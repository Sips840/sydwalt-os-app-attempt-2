import 'package:flutter/material.dart';

import 'config.dart';
import 'downloads_repository.dart';
import 'screens/shell_screen.dart';
import 'settings_store.dart';

class SydwaltApp extends StatefulWidget {
  const SydwaltApp({super.key});

  @override
  State<SydwaltApp> createState() => _SydwaltAppState();
}

class _SydwaltAppState extends State<SydwaltApp> {
  late Future<(SettingsStore, DownloadsRepository)> _boot = _open();

  static Future<(SettingsStore, DownloadsRepository)> _open() async =>
      (await SettingsStore.open(), await DownloadsRepository.open());

  @override
  Widget build(BuildContext context) {
    const brand = Color(AppConfig.brandColor);
    final scheme = ColorScheme.fromSeed(seedColor: brand, primary: brand);
    return MaterialApp(
      title: 'Sydwalt OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: brand, foregroundColor: Colors.white),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: FutureBuilder(
        future: _boot,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      const Text('The app could not start', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('${snap.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => setState(() => _boot = _open()), child: const Text('Try again')),
                    ],
                  ),
                ),
              ),
            );
          }
          final data = snap.data;
          if (data == null) return const ColoredBox(color: brand);
          return ShellScreen(settings: data.$1, downloads: data.$2);
        },
      ),
    );
  }
}
