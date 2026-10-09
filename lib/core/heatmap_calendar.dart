/// Calendar labels, not elapsed 24-hour intervals. Date constructors preserve
/// consecutive civil days when the device crosses a daylight-saving boundary.
class HeatmapCalendarWindow {
  final int weeks;
  final DateTime today;
  final DateTime start;

  factory HeatmapCalendarWindow({required int weeks, DateTime? today}) {
    if (weeks < 1) throw RangeError.range(weeks, 1, null, 'weeks');
    final now = today ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return HeatmapCalendarWindow._(
      weeks,
      day,
      shiftDay(day, -(day.weekday - 1) - (weeks - 1) * 7),
    );
  }

  const HeatmapCalendarWindow._(this.weeks, this.today, this.start);

  static DateTime shiftDay(DateTime day, int offset) =>
      DateTime(day.year, day.month, day.day + offset);

  static String dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static int dayDistance(DateTime first, DateTime last) => DateTime.utc(
    last.year,
    last.month,
    last.day,
  ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;

  static int level(int? value) => (value ?? 0).clamp(0, 5);

  static int progressLevel(double ratio) =>
      ratio <= 0 ? 0 : (ratio * 5).ceil().clamp(1, 5);

  static DateTime? tryParseDateKey(String key) {
    if (key.length != 10 ||
        !RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(key)) {
      return null;
    }
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(5, 7));
    final day = int.parse(key.substring(8, 10));
    if (year < 1 || year > 9999) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  int get elapsedDays => dayDistance(start, today) + 1;
  DateTime dayAt(int index) => shiftDay(start, index);
  bool contains(DateTime day) {
    final index = dayDistance(start, day);
    return index >= 0 && index < elapsedDays;
  }

  Iterable<DateTime> get visibleDays sync* {
    for (var index = 0; index < elapsedDays; index++) {
      yield dayAt(index);
    }
  }

  HeatmapSummary summarize(Map<String, int> data) {
    var activeDays = 0;
    var maximum = 0;
    for (final date in visibleDays) {
      final value = level(data[dateKey(date)]);
      if (value > 0) activeDays++;
      if (value > maximum) maximum = value;
    }
    return HeatmapSummary(activeDays: activeDays, maximumLevel: maximum);
  }
}

class HeatmapSummary {
  final int activeDays;
  final int maximumLevel;

  const HeatmapSummary({required this.activeDays, required this.maximumLevel});
}
