import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_naming.dart';

/// One file in the app's Downloads folder.
@immutable
class DownloadedFile {
  const DownloadedFile({required this.path, required this.size, required this.modified});

  final String path;
  final int size;
  final DateTime modified;

  String get name => p.basename(path);
  String get extension => p.extension(path).replaceFirst('.', '').toLowerCase();

  @override
  bool operator ==(Object other) => other is DownloadedFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Everything the web app exports (CSV logs, Word reports, Netcash batches,
/// company-book backups, uploaded documents) lands here, so nothing is lost
/// once the share sheet or viewer closes.
///
/// The folder itself is the database: each file is a record, and its name and
/// modified time are the searchable fields. On iOS the folder sits inside the
/// app's Documents directory, which the Files app shows under "On My iPhone >
/// Sydwalt OS". Deleted files go to a private trash folder first so a delete
/// can be undone, and the trash is emptied the next time the app starts.
class DownloadsRepository extends ChangeNotifier {
  DownloadsRepository({required this.directory, required this.trashDirectory});

  final Directory directory;
  final Directory trashDirectory;

  static Future<DownloadsRepository> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final repo = DownloadsRepository(
      directory: Directory(p.join(docs.path, 'Downloads')),
      trashDirectory: Directory(p.join(support.path, 'DownloadsTrash')),
    );
    await repo.emptyTrash();
    return repo;
  }

  Future<void> _ensure() async {
    await directory.create(recursive: true);
    await trashDirectory.create(recursive: true);
  }

  /// Saves [bytes] under a safe, unique version of [name] and returns it.
  /// Writes to a temporary file first, then renames, so a crash mid-write
  /// never leaves a half-written file that looks complete.
  Future<DownloadedFile> save(List<int> bytes, String name, {String? mime}) async {
    await _ensure();
    final safe = FileNaming.sanitise(name, mime: mime);
    final finalName = FileNaming.unique(safe, (c) => File(p.join(directory.path, c)).existsSync());
    final target = File(p.join(directory.path, finalName));
    final temp = File(p.join(trashDirectory.path, '.partial-${DateTime.now().microsecondsSinceEpoch}'));
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path).catchError((Object _) async {
      // rename() fails across volumes; fall back to copy and delete.
      await temp.copy(target.path);
      await temp.delete();
      return target;
    });
    final file = await _describe(target);
    notifyListeners();
    return file;
  }

  Future<DownloadedFile> _describe(File f) async {
    final stat = await f.stat();
    return DownloadedFile(path: f.path, size: stat.size, modified: stat.modified);
  }

  /// Newest first. [query] matches any part of the file name, ignoring case.
  /// [since] keeps only files saved on or after that moment.
  Future<List<DownloadedFile>> list({String query = '', DateTime? since}) async {
    await _ensure();
    final q = query.trim().toLowerCase();
    final out = <DownloadedFile>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) continue;
      final f = await _describe(entity);
      if (since != null && f.modified.isBefore(since)) continue;
      out.add(f);
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  /// Renames a download, keeping its extension when the new name has none.
  Future<DownloadedFile> rename(DownloadedFile file, String newName) async {
    var name = newName.trim();
    if (p.extension(name).isEmpty && file.extension.isNotEmpty) name = '$name.${file.extension}';
    name = FileNaming.sanitise(name);
    if (name == file.name) return file;
    final finalName = FileNaming.unique(name, (c) => File(p.join(directory.path, c)).existsSync());
    final moved = await File(file.path).rename(p.join(directory.path, finalName));
    final out = await _describe(moved);
    notifyListeners();
    return out;
  }

  /// Moves the file to the trash and returns a token for [restore].
  Future<String> delete(DownloadedFile file) async {
    await _ensure();
    final token = p.join(trashDirectory.path, '${DateTime.now().microsecondsSinceEpoch}__${file.name}');
    await File(file.path).rename(token);
    notifyListeners();
    return token;
  }

  /// Undoes [delete]. If a file with the same name has appeared since, the
  /// restored copy gets a "(2)" suffix rather than replacing it.
  Future<DownloadedFile?> restore(String token) async {
    final trashed = File(token);
    if (!await trashed.exists()) return null;
    final original = p.basename(token).split('__').skip(1).join('__');
    final finalName = FileNaming.unique(original, (c) => File(p.join(directory.path, c)).existsSync());
    final back = await trashed.rename(p.join(directory.path, finalName));
    final out = await _describe(back);
    notifyListeners();
    return out;
  }

  Future<void> emptyTrash() async {
    if (!await trashDirectory.exists()) return;
    await for (final entity in trashDirectory.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // A file still open elsewhere is retried at the next start.
      }
    }
  }
}
