import 'i18n.dart';
import '../l10n/generated/app_localizations.dart';

/// Generated habit labels. Authored names and measurement units stay literal.
class HabitUiCopy {
  final AppLocale locale;

  const HabitUiCopy(this.locale);

  static bool isEn([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en;

  AppLocalizations get _l10n =>
      lookupAppLocalizations(locale.flutterLocale);

  static AppLocalizations _l10nFor([AppLocale? locale]) =>
      lookupAppLocalizations((locale ?? I18n.current).flutterLocale);

  static String _countUnitWithLocale(
    int count,
    String? authoredUnit, [
    AppLocale? locale,
  ]) => measurementUnit(count, authoredUnit: authoredUnit, locale: locale);

  String _countUnit(int count, String? authoredUnit) =>
      _countUnitWithLocale(count, authoredUnit, locale);

  String get weekPrefix =>
      _l10n.habitFlexThisWeek;

  String get monthPrefix =>
      _l10n.habitFlexThisMonth;

  static String measurementUnit(
    num count, {
    String? authoredUnit,
    String? generatedUnitKey,
    AppLocale? locale,
  }) {
    if (authoredUnit != null) return authoredUnit;
    final l10n = _l10nFor(locale);
    if (generatedUnitKey == 'cup') {
      return count == 1 ? l10n.habitCopyUnitCup : l10n.habitCopyUnitCups;
    }
    return count == 1 ? l10n.habitCopyUnitTime : l10n.habitUnitTimes;
  }

  String weekGoal(int target) =>
      _l10n.habitCopyWeekGoal(target, _countUnit(target, null));

  String monthGoal(int target) =>
      _l10n.habitCopyMonthGoal(target, _countUnit(target, null));

  static String weekGoalFor(int target, [AppLocale? locale]) =>
      _l10nFor(locale).habitCopyWeekGoal(target, _countUnitWithLocale(target, null, locale));

  static String monthGoalFor(int target, [AppLocale? locale]) =>
      _l10nFor(locale).habitCopyMonthGoal(target, _countUnitWithLocale(target, null, locale));

  String countLabel({
    required int count,
    required int target,
    required bool negative,
    bool flexible = false,
    String? authoredUnit,
    String? generatedUnitKey,
    String? flexProgressLabel,
  }) {
    final l10n = _l10n;
    String unit(int quantity) => measurementUnit(
      quantity,
      authoredUnit: authoredUnit,
      generatedUnitKey: generatedUnitKey,
      locale: locale,
    );
    final measuredCount = l10n.habitCopyMeasuredCount(count, unit(count));
    if (flexProgressLabel != null) {
      return l10n.habitCopyCountWithFlexProgress(
        measuredCount,
        flexProgressLabel,
      );
    }
    if (flexible) return measuredCount;
    if (negative) return l10n.habitCopyCountRecorded(measuredCount);
    return l10n.habitCopyCountRatio(measuredCount, target, unit(target));
  }

  static String actionCancel([AppLocale? locale]) =>
      _l10nFor(locale).actionCancel;

  static String actionDelete([AppLocale? locale]) =>
      _l10nFor(locale).actionDelete;

  static String actionEdit([AppLocale? locale]) =>
      _l10nFor(locale).actionEdit;

  static String actionEnd([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyActionEnd;

  static String actionSave([AppLocale? locale]) =>
      _l10nFor(locale).actionSave;

  static String deleteConfirmTitle([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyDeleteConfirmTitle;

  static String deleteConfirmContent(String habitName, [AppLocale? locale]) =>
      _l10nFor(locale).habitCopyDeleteConfirmContent(habitName);

  static String endConfirmTitle([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyEndConfirmTitle;

  static String endConfirmContent(String habitName, [AppLocale? locale]) =>
      _l10nFor(locale).habitCopyEndConfirmContent(habitName);

  static String endHabitAction([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyEndHabitAction;

  static String deleteHabitAction([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyDeleteHabitAction;

  static String moreActions([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyMoreActions;

  static String endedFeedback([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyEndedFeedback;

  static String deletedFeedback([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyDeletedFeedback;

  static String saveSuccess([AppLocale? locale]) =>
      _l10nFor(locale).habitCopySaveSuccess;

  static String checkInFailedWithRetry([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyCheckInFailedWithRetry;

  static String undoFailedWithRetry([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyUndoFailedWithRetry;

  static String saveFailedWithRetry([AppLocale? locale]) =>
      _l10nFor(locale).habitCopySaveFailedWithRetry;

  static String actionFailedWithRetry([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyActionFailedWithRetry;

  static String nameRequired([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyNameRequired;

  static String dailyTargetInvalid([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyDailyTargetInvalid;

  static String flexTargetInvalid([AppLocale? locale]) =>
      _l10nFor(locale).habitErrorFlexTarget;

  static String dateRangeInvalid([AppLocale? locale]) =>
      _l10nFor(locale).habitErrorDateRange;

  static String reminderSchedulerMissing([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyReminderSchedulerMissing;

  static String notificationsNotGranted([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyNotificationsNotGranted;

  static String reminderPermissionError([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyReminderPermissionError;

  static String reminderRegisterFailed([AppLocale? locale]) =>
      _l10nFor(locale).habitCopyReminderRegisterFailed;

  static String reminderSyncWarning(String issueText, [AppLocale? locale]) =>
      _l10nFor(locale).habitCopyReminderSyncWarning(issueText);

  static String periodGoalReached(
    String habitName,
    String periodLabel, [
    AppLocale? locale,
  ]) =>
      _l10nFor(locale).habitCopyPeriodGoalReached(habitName, periodLabel);

  static String singleSessionGoalReached(
    String habitName, [
    AppLocale? locale,
  ]) =>
      _l10nFor(locale).habitCopySingleSessionGoalReached(habitName);

  static String checkInSuccessNegative(String habitName, [AppLocale? locale]) =>
      _l10nFor(locale).habitCopyCheckInSuccessNegative(habitName);

  static String checkInSuccessStandard(
    String habitName,
    int count,
    int target,
    bool reachedTarget, [
    AppLocale? locale,
  ]) {
    final l10n = _l10nFor(locale);
    return reachedTarget
        ? l10n.habitCopyCheckInSuccessStandardReached(habitName)
        : l10n.habitCopyCheckInSuccessStandardProgress(habitName, count, target);
  }

  static String checkInSuccessFlex(
    String habitName,
    int count,
    int target,
    String? flexLabel,
    bool isFlexCompleted,
    String? flexPrefix, [
    AppLocale? locale,
  ]) {
    final l10n = _l10nFor(locale);
    if (flexLabel == null) {
      return l10n.habitCopyCheckInSuccessStandardProgress(habitName, count, target);
    }
    if (isFlexCompleted) {
      return l10n.habitCopyPeriodGoalReached(
        habitName,
        flexPrefix ?? l10n.habitCopyPeriodFallback,
      );
    }
    return l10n.habitCopyCheckInSuccessFlexProgress(habitName, flexLabel);
  }

  static String dateRecordFeedback(
    String habitName,
    DateTime date, [
    AppLocale? locale,
  ]) =>
      _l10nFor(locale).habitCopyDateRecordFeedback(habitName);

  static String dateUndoFeedback(
    String habitName,
    DateTime date, [
    AppLocale? locale,
  ]) =>
      _l10nFor(locale).habitCopyDateUndoFeedback(habitName);
}
