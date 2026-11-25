/// Gregorian civil-day navigation for Calendar's year 0001–9999 range.
/// UTC values are used only as calendar arithmetic containers; input instants
/// are never converted between zones. Returned dates use the device's zone.
class CalendarDateNavigation {
  static final _firstDay = DateTime.utc(1, 1, 1);
  static final _lastDay = DateTime.utc(9999, 12, 31);
  static const _lastMonthIndex = 9999 * 12 - 1;

  /// ISO weekday IDs stay stable; an invalid display preference uses Monday.
  static int normalizeFirstDayOfWeek(int value) =>
      value >= DateTime.monday && value <= DateTime.sunday
      ? value
      : DateTime.monday;

  static List<int> orderedWeekdays(int firstDayOfWeek) {
    final first = normalizeFirstDayOfWeek(firstDayOfWeek);
    return List<int>.unmodifiable(
      List<int>.generate(7, (index) => (first - 1 + index) % 7 + 1),
    );
  }

  /// Returns null at the range boundary or for an absent local civil day.
  static DateTime? tryShiftDays(DateTime date, int offset) {
    final civil = _utcCivilDay(date);
    if (civil == null) {
      return null;
    }
    final daysBefore = civil.difference(_firstDay).inDays;
    final daysAfter = _lastDay.difference(civil).inDays;
    // Bound before adding or constructing Duration, even for extreme offsets.
    if (offset < -daysBefore || offset > daysAfter) {
      return null;
    }
    return _localCivilDay(civil.add(Duration(days: offset)));
  }

  /// Keeps the day number when possible, otherwise uses the target month's
  /// last day. It never clamps an out-of-range year to an endpoint.
  static DateTime? tryShiftMonths(DateTime date, int offset) {
    if (_utcCivilDay(date) == null) {
      return null;
    }
    final monthIndex = (date.year - 1) * 12 + date.month - 1;
    if (offset < -monthIndex || offset > _lastMonthIndex - monthIndex) {
      return null;
    }
    final targetIndex = monthIndex + offset;
    return _inMonth(date, targetIndex ~/ 12 + 1, targetIndex % 12 + 1);
  }

  /// Keeps the month and day, with February 29 becoming February 28 when
  /// necessary. Validates the offset before adding it to the year.
  static DateTime? tryShiftYears(DateTime date, int offset) {
    if (_utcCivilDay(date) == null ||
        offset < 1 - date.year ||
        offset > 9999 - date.year) {
      return null;
    }
    return _inMonth(date, date.year + offset, date.month);
  }

  /// Seven civil-day slots; unavailable days retain their empty position.
  static List<DateTime?> weekDays(
    DateTime date, {
    int firstDayOfWeek = DateTime.monday,
  }) {
    final civil = _utcCivilDay(date);
    if (civil == null) {
      return List<DateTime?>.unmodifiable(List<DateTime?>.filled(7, null));
    }
    final first = normalizeFirstDayOfWeek(firstDayOfWeek);
    final startOffset = -((civil.weekday - first) % 7);
    return List<DateTime?>.unmodifiable(
      List<DateTime?>.generate(
        7,
        (index) => tryShiftDays(date, startOffset + index),
      ),
    );
  }

  /// Consecutive civil-day slots, including the starting day. Null slots must
  /// remain noninteractive instead of borrowing a neighboring day's date.
  static List<DateTime?> daysFrom(DateTime date, int count) {
    if (count < 0) {
      throw RangeError.range(count, 0, null, 'count');
    }
    return List<DateTime?>.unmodifiable(
      List<DateTime?>.generate(count, (index) => tryShiftDays(date, index)),
    );
  }

  static DateTime? _utcCivilDay(DateTime date) =>
      date.year >= 1 && date.year <= 9999
      ? DateTime.utc(date.year, date.month, date.day)
      : null;

  static DateTime? _inMonth(DateTime date, int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return _localCivilDay(DateTime.utc(year, month, day));
  }

  static DateTime? _localCivilDay(DateTime civil) {
    final local = DateTime(civil.year, civil.month, civil.day);
    return local.year == civil.year &&
            local.month == civil.month &&
            local.day == civil.day
        ? local
        : null;
  }
}
