import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sydwalt_os/src/downloads_repository.dart';
import 'package:sydwalt_os/src/screens/downloads_screen.dart';

void main() {
  late Directory root;
  late DownloadsRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sydwalt_dls_');
    repo = DownloadsRepository(
      directory: Directory(p.join(root.path, 'Downloads')),
      trashDirectory: Directory(p.join(root.path, 'Trash')),
    );
  });

  tearDown(() => root.delete(recursive: true));

  /// File I/O completes on the real event loop, outside the test's fake
  /// clock, so alternate real waits with frames until the list has loaded.
  Future<void> settleIo(WidgetTester tester, Finder until, {bool gone = false}) async {
    bool done() => until.evaluate().isEmpty == gone;
    for (var i = 0; i < 150 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(until, gone ? findsNothing : findsWidgets, reason: 'timed out waiting for the Downloads list to update');
  }

  Future<void> pumpScreen(WidgetTester tester, Finder until) async {
    await tester.pumpWidget(MaterialApp(home: DownloadsScreen(repository: repo)));
    await settleIo(tester, until);
  }

  testWidgets('empty state explains what will appear here', (tester) async {
    await pumpScreen(tester, find.text('No downloads yet'));
  });

  testWidgets('lists files and filters them by search', (tester) async {
    await tester.runAsync(() async {
      await repo.save([1, 2, 3], 'resolutions-log-2026-10-20.csv');
      await repo.save([1], 'Netcash 2026-10.txt');
    });
    await pumpScreen(tester, find.text('resolutions-log-2026-10-20.csv'));
    expect(find.text('Netcash 2026-10.txt'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'netcash');
    await tester.pump(const Duration(milliseconds: 250));
    await settleIo(tester, find.text('resolutions-log-2026-10-20.csv'), gone: true);
    expect(find.text('Netcash 2026-10.txt'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 250));
    await settleIo(tester, find.text('Nothing matches'));
  });

  testWidgets('delete shows Undo, and Undo brings the file back', (tester) async {
    await tester.runAsync(() => repo.save([1], 'company-book.json'));
    await pumpScreen(tester, find.text('company-book.json'));

    await tester.tap(find.byTooltip('File actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settleIo(tester, find.text('No downloads yet'));
    expect(find.text('Deleted company-book.json'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settleIo(tester, find.text('company-book.json'));
  });
}
