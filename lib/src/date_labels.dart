/// Date wording for the Downloads list and its date filter.
enum DateFilter {
  all('All'),
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days');

  const DateFilter(this.label);
  final String label;

  /// The earliest moment a file may have been saved to pass this filter.
  DateTime? since(DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    return switch (this) {
      DateFilter.all => null,
      DateFilter.today => midnight,
      DateFilter.week => midnight.subtract(const Duration(days: 6)),
      DateFilter.month => midnight.subtract(const Duration(days: 29)),
    };
  }
}

class DateLabels {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "Today 14:05", "Yesterday 09:12", "3 Oct 16:40", or "3 Oct 2025" for an
  /// earlier year.
  static String describe(DateTime when, DateTime now) {
    final day = DateTime(when.year, when.month, when.day);
    final today = DateTime(now.year, now.month, now.day);
    final time = '${_two(when.hour)}:${_two(when.minute)}';
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today $time';
    if (diff == 1) return 'Yesterday $time';
    final date = '${when.day} ${_months[when.month - 1]}';
    return when.year == now.year ? '$date $time' : '$date ${when.year}';
  }
}
