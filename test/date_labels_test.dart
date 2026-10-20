import 'package:flutter_test/flutter_test.dart';
import 'package:sydwalt_os/src/date_labels.dart';
import 'package:sydwalt_os/src/transfers.dart';

void main() {
  final now = DateTime(2026, 10, 20, 15, 30);

  test('describe', () {
    expect(DateLabels.describe(DateTime(2026, 10, 20, 9, 5), now), 'Today 09:05');
    expect(DateLabels.describe(DateTime(2026, 10, 19, 23, 59), now), 'Yesterday 23:59');
    expect(DateLabels.describe(DateTime(2026, 10, 3, 16, 40), now), '3 Oct 16:40');
    expect(DateLabels.describe(DateTime(2025, 12, 31, 8, 0), now), '31 Dec 2025');
  });

  test('date filters count whole days back from midnight', () {
    expect(DateFilter.all.since(now), isNull);
    expect(DateFilter.today.since(now), DateTime(2026, 10, 20));
    expect(DateFilter.week.since(now), DateTime(2026, 10, 14));
    expect(DateFilter.month.since(now), DateTime(2026, 9, 21));
  });

  test('transfer tracker start, update, finish', () {
    final t = TransferTracker();
    var notified = 0;
    t.addListener(() => notified++);
    final id = t.start('Report.docx');
    expect(t.isBusy, isTrue);
    t.update(id, 1.7);
    expect(t.active.single.progress, 1.0);
    t.finish(id);
    t.finish(id);
    expect(t.isBusy, isFalse);
    expect(notified, 3);
  });
}
