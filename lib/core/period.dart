import 'format.dart';

/// A date range [start, end) with a human label.
class Period {
  final DateTime? start;
  final DateTime? end;
  final String label;
  const Period(this.start, this.end, this.label);

  static const all = Period(null, null, 'All time');

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Weeks start on Monday.
  static Period week(DateTime now, {int offset = 0}) {
    final today = _day(now);
    final start = today.subtract(Duration(days: today.weekday - 1 - offset * 7));
    final end = DateTime(start.year, start.month, start.day + 7);
    final label = offset == 0
        ? 'This week'
        : offset == -1
            ? 'Last week'
            : '${shortDayFmt.format(start)} – ${shortDayFmt.format(end.subtract(const Duration(days: 1)))}';
    return Period(start, end, label);
  }

  static Period month(int year, int month) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    return Period(start, end, monthFmt.format(start));
  }

  static Period thisMonth(DateTime now) => month(now.year, now.month);
  static Period lastMonth(DateTime now) => month(now.year, now.month - 1);

  /// [to] is inclusive (a whole day).
  static Period custom(DateTime from, DateTime to) {
    final s = _day(from);
    final e = _day(to).add(const Duration(days: 1));
    return Period(s, e, '${shortDayFmt.format(s)} – ${shortDayFmt.format(_day(to))}');
  }

  bool get isMonth =>
      start != null &&
      end != null &&
      start!.day == 1 &&
      end!.day == 1 &&
      DateTime(start!.year, start!.month + 1) == end;

  Period shiftMonth(int delta) =>
      Period.month(start!.year, start!.month + delta);

  @override
  bool operator ==(Object other) =>
      other is Period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
