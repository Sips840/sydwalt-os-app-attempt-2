import 'package:flutter_test/flutter_test.dart';
import 'package:sydwalt_os/src/file_naming.dart';

void main() {
  group('sanitise', () {
    test('keeps good names from the web app unchanged', () {
      expect(FileNaming.sanitise('resolutions-log-2026-10-20.csv'), 'resolutions-log-2026-10-20.csv');
      expect(FileNaming.sanitise('Sydwalt control pack 2026-10-20.csv'), 'Sydwalt control pack 2026-10-20.csv');
    });

    test('removes characters file systems reject and path traversal', () {
      expect(FileNaming.sanitise('Q3: cash/flow? "final".docx'), 'Q3 cash flow final.docx');
      expect(FileNaming.sanitise('../../etc/passwd'), 'etc passwd');
      expect(FileNaming.sanitise('..hidden.txt'), 'hidden.txt');
    });

    test('adds an extension from the MIME type when the name has none', () {
      expect(FileNaming.sanitise('Netcash batch', mime: 'text/plain; charset=utf-8'), 'Netcash batch.txt');
      expect(
        FileNaming.sanitise('report', mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
        'report.docx',
      );
      expect(FileNaming.sanitise('blob', mime: 'application/x-unknown'), 'blob');
    });

    test('falls back to a readable stem when the name is empty', () {
      expect(FileNaming.sanitise('', mime: 'application/pdf'), 'Sydwalt download.pdf');
      expect(FileNaming.sanitise('   .csv'), 'csv');
    });

    test('shortens long names but keeps the extension', () {
      final out = FileNaming.sanitise('${'a' * 300}.pdf');
      expect(out.length, FileNaming.maxLength);
      expect(out.endsWith('.pdf'), isTrue);
    });
  });

  test('unique adds (2), (3) like a desktop browser', () {
    final taken = {'Report.pdf', 'Report (2).pdf'};
    expect(FileNaming.unique('Report.pdf', taken.contains), 'Report (3).pdf');
    expect(FileNaming.unique('Other.pdf', taken.contains), 'Other.pdf');
  });

  group('fromContentDisposition', () {
    test('reads the RFC 5987 form the server uses for uploads', () {
      expect(
        FileNaming.fromContentDisposition("inline; filename*=UTF-8''Tender%20pack%20%C3%A9.pdf"),
        'Tender pack é.pdf',
      );
    });

    test('reads the quoted form used by exports', () {
      expect(
        FileNaming.fromContentDisposition('attachment; filename="Netcash 2026-10 2026-10-25.txt"'),
        'Netcash 2026-10 2026-10-25.txt',
      );
    });

    test('returns null when there is no file name', () {
      expect(FileNaming.fromContentDisposition(null), isNull);
      expect(FileNaming.fromContentDisposition('inline'), isNull);
    });
  });

  test('formatSize', () {
    expect(FileNaming.formatSize(512), '512 B');
    expect(FileNaming.formatSize(2048), '2 KB');
    expect(FileNaming.formatSize(3 * 1024 * 1024 + 100), '3.0 MB');
  });
}
