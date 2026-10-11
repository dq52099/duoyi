import 'i18n.dart';

/// Generated habit labels. Authored names and measurement units stay literal.
class HabitUiCopy {
  final AppLocale locale;

  const HabitUiCopy(this.locale);

  bool get _isEn => locale == AppLocale.en;

  String get weekPrefix => _isEn ? 'This week' : '本周';
  String get monthPrefix => _isEn ? 'This month' : '本月';

  String _countUnit(int count, String? authoredUnit) =>
      authoredUnit ?? (_isEn ? (count == 1 ? 'time' : 'times') : '次');

  String weekGoal(int target) => _isEn
      ? 'Weekly goal: $target ${_countUnit(target, null)}/week'
      : '每周目标: $target 次/周';

  String monthGoal(int target) => _isEn
      ? 'Monthly goal: $target ${_countUnit(target, null)}/month'
      : '每月目标: $target 次/月';

  String countLabel({
    required int count,
    required int target,
    required bool negative,
    bool flexible = false,
    String? authoredUnit,
    String? flexProgressLabel,
  }) {
    final measuredCount = '$count ${_countUnit(count, authoredUnit)}';
    if (flexProgressLabel != null) {
      return '$measuredCount · $flexProgressLabel';
    }
    if (flexible) return measuredCount;
    if (negative) {
      return _isEn ? 'Recorded $measuredCount' : '已记录 $measuredCount';
    }
    return '$measuredCount / $target ${_countUnit(target, authoredUnit)}';
  }
}
