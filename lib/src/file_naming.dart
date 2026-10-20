import 'package:path/path.dart' as p;

/// File naming rules for everything saved to the app's Downloads folder.
///
/// The web app already chooses good names (for example
/// `resolutions-log-2026-10-20.csv`), so these rules only make a name safe for
/// every file system and avoid overwriting an earlier download.
class FileNaming {
  static const int maxLength = 120;

  static const Map<String, String> _extForMime = {
    'application/pdf': 'pdf',
    'text/csv': 'csv',
    'text/plain': 'txt',
    'application/json': 'json',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
    'application/zip': 'zip',
    'text/markdown': 'md',
    'text/html': 'html',
    'image/png': 'png',
    'image/jpeg': 'jpg',
  };

  /// Removes path separators and characters Windows, Android and iOS reject,
  /// collapses whitespace, and keeps the extension when shortening.
  static String sanitise(String name, {String? mime, String fallbackStem = 'Sydwalt download'}) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ');
    // Words made only of dots ("..", left over from "../") carry no meaning.
    s = s.split(RegExp(r'\s+')).where((w) => !RegExp(r'^\.+$').hasMatch(w)).join(' ').trim();
    s = s.replaceAll(RegExp(r'^\.+'), '').trim();
    var ext = p.extension(s);
    var stem = p.basenameWithoutExtension(s).trim();
    if (stem.isEmpty) stem = fallbackStem;
    if (ext.isEmpty || ext == '.') {
      final guessed = mime == null ? null : _extForMime[mime.split(';').first.trim().toLowerCase()];
      ext = guessed == null ? '' : '.$guessed';
    }
    final room = maxLength - ext.length;
    if (stem.length > room) stem = stem.substring(0, room).trim();
    return '$stem$ext';
  }

  /// `Report.pdf`, then `Report (2).pdf`, `Report (3).pdf` and so on, the same
  /// convention desktop browsers use, so nothing already saved is replaced.
  static String unique(String name, bool Function(String candidate) exists) {
    if (!exists(name)) return name;
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    for (var i = 2; i < 10000; i++) {
      final candidate = '$stem ($i)$ext';
      if (!exists(candidate)) return candidate;
    }
    return '$stem ${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  /// Reads the file name out of a Content-Disposition header, preferring the
  /// RFC 5987 `filename*=UTF-8''...` form the server uses for uploaded files.
  static String? fromContentDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    final star = RegExp(r"filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)").firstMatch(header);
    if (star != null) {
      try {
        return Uri.decodeComponent(star.group(1)!.trim());
      } catch (_) {
        // Malformed escapes: fall through to the plain form.
      }
    }
    final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?').firstMatch(header);
    return plain?.group(1)?.trim();
  }

  /// Human readable size, for the Downloads list.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
