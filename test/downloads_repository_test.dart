import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sydwalt_os/src/downloads_repository.dart';

void main() {
  late Directory root;
  late DownloadsRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sydwalt_dl_');
    repo = DownloadsRepository(
      directory: Directory(p.join(root.path, 'Downloads')),
      trashDirectory: Directory(p.join(root.path, 'Trash')),
    );
  });

  tearDown(() => root.delete(recursive: true));

  test('save writes the bytes under a safe name and notifies listeners', () async {
    var notified = 0;
    repo.addListener(() => notified++);
    final f = await repo.save(utf8.encode('a,b\n1,2\n'), 'log: 2026/10.csv');
    expect(f.name, 'log 2026 10.csv');
    expect(await File(f.path).readAsString(), 'a,b\n1,2\n');
    expect(f.size, 8);
    expect(notified, 1);
  });

  test('saving the same name twice keeps both files', () async {
    await repo.save([1], 'Report.pdf');
    final second = await repo.save([2], 'Report.pdf');
    expect(second.name, 'Report (2).pdf');
    expect((await repo.list()).length, 2);
  });

  test('list is newest first and searchable by name, ignoring case', () async {
    final a = await repo.save([1], 'Minutes March.docx');
    await File(a.path).setLastModified(DateTime(2026, 3, 1));
    await repo.save([1], 'Netcash batch.txt');
    final all = await repo.list();
    expect(all.map((f) => f.name), ['Netcash batch.txt', 'Minutes March.docx']);
    expect((await repo.list(query: 'minutes')).map((f) => f.name), ['Minutes March.docx']);
    expect(await repo.list(query: 'nothing'), isEmpty);
  });

  test('list filters by date', () async {
    final old = await repo.save([1], 'old.csv');
    await File(old.path).setLastModified(DateTime(2025, 1, 1));
    await repo.save([1], 'new.csv');
    final recent = await repo.list(since: DateTime.now().subtract(const Duration(days: 1)));
    expect(recent.map((f) => f.name), ['new.csv']);
  });

  test('rename keeps the extension when none is typed and avoids clashes', () async {
    final f = await repo.save([1], 'draft.docx');
    await repo.save([1], 'Final.docx');
    final renamed = await repo.rename(f, 'Final');
    expect(renamed.name, 'Final (2).docx');
    expect(File(f.path).existsSync(), isFalse);
  });

  test('delete can be undone, and the trash is emptied later', () async {
    final f = await repo.save([7, 8, 9], 'company-book.json');
    final token = await repo.delete(f);
    expect(await repo.list(), isEmpty);
    final back = await repo.restore(token);
    expect(back!.name, 'company-book.json');
    expect(await File(back.path).readAsBytes(), [7, 8, 9]);

    final token2 = await repo.delete(back);
    await repo.emptyTrash();
    expect(await repo.restore(token2), isNull);
    expect(await repo.list(), isEmpty);
  });

  test('restore does not overwrite a newer file with the same name', () async {
    final f = await repo.save([1], 'a.csv');
    final token = await repo.delete(f);
    await repo.save([2], 'a.csv');
    final back = await repo.restore(token);
    expect(back!.name, 'a (2).csv');
  });
}
