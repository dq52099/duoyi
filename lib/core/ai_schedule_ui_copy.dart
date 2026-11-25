import 'i18n.dart';
import '../services/ai_service.dart';
import '../services/api_client.dart';
import '../providers/notification_service.dart' show NotificationScheduleIssue;
import '../services/notification_permission_exception.dart'
    show NotificationScheduleUnavailableException;
import '../services/reminder_scheduler.dart' show TodoReminderPreflightIssue;
import '../services/reminder_sync_issue.dart' show ReminderSyncIssue;
import '../l10n/generated/app_localizations.dart';

/// User-facing copy for the AI schedule flow.
///
/// Input, titles, notes and subtasks are user data and must be rendered
/// unchanged. Only labels, actions and service status messages are localized.
class AiScheduleUiCopy {
  AiScheduleUiCopy._();

  static AppLocalizations _l10n([AppLocale? locale]) =>
      lookupAppLocalizations((locale ?? I18n.current).flutterLocale);

  static bool isEn([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en;

  static String get screenTitle => _l10n().aiScheduleScreenTitle;
  static String get aiDisabledTitle => _l10n().aiScheduleAiDisabledTitle;
  static String get aiDisabledMessage => _l10n().aiScheduleAiDisabledMessage;
  static String get inputTitle => _l10n().aiScheduleInputTitle;
  static String get inputSubtitle => _l10n().aiScheduleInputSubtitle;
  static String get inputHint => _l10n().aiScheduleInputHint;
  static String get emptyInput => _l10n().aiScheduleEmptyInput;
  static String get recognize => _l10n().aiScheduleRecognize;
  static String get recognizing => _l10n().aiScheduleRecognizing;
  static String get errorTitle => _l10n().aiScheduleErrorTitle;
  static String get draftTitle => _l10n().aiScheduleDraftTitle;
  static String get draftAiMessage => _l10n().aiScheduleDraftAiMessage;
  static String get draftFallbackMessage =>
      _l10n().aiScheduleDraftFallbackMessage;
  static String get warningAiIncomplete =>
      _l10n().aiScheduleWarningAiIncomplete;
  static String get warningLocalFallback =>
      _l10n().aiScheduleWarningLocalFallback;
  static String get warningAppendix => _l10n().aiScheduleWarningAppendix;
  static String get confirmCardTitle => _l10n().aiScheduleConfirmCardTitle;
  static String get typeLabel => _l10n().aiScheduleTypeLabel;
  static String get titleLabel => _l10n().aiScheduleTitleLabel;
  static String get startLabel => _l10n().aiScheduleStartLabel;
  static String get endLabel => _l10n().aiScheduleEndLabel;
  static String get reminderLabel => _l10n().aiScheduleReminderLabel;
  static String get notesLabel => _l10n().aiScheduleNotesLabel;
  static String get subtasksLabel => _l10n().aiScheduleSubtasksLabel;
  static String get calendarType => _l10n().aiScheduleCalendarType;
  static String get todoType => _l10n().aiScheduleTodoType;
  static String get reminderEnabled => _l10n().aiScheduleReminderEnabled;
  static String get reminderDisabled => _l10n().aiScheduleReminderDisabled;
  static String get saving => _l10n().aiScheduleSaving;
  static String get create => _l10n().aiScheduleCreate;
  static String get done => _l10n().aiScheduleDone;
  static String get viewDetails => _l10n().aiScheduleViewDetails;
  static String get createdEvent => _l10n().aiScheduleCreatedEvent;
  static String get createdTask => _l10n().aiScheduleCreatedTask;
  static String get createdEventWithReminderIssue =>
      _l10n().aiScheduleCreatedEventWithReminderIssue;
  static String get createdTaskWithReminderIssue =>
      _l10n().aiScheduleCreatedTaskWithReminderIssue;

  static String createdItemLabel(bool calendar) =>
      calendar ? calendarType : todoType;

  static String createdItemSummary(bool calendar, String title) =>
      _l10n().aiScheduleCreatedItemSummary(createdItemLabel(calendar), title);

  static String startSummary(bool calendar, String value) => calendar
      ? _l10n().aiScheduleStartSummaryCalendar(value)
      : _l10n().aiScheduleStartSummaryTodo(value);

  static String get localSaved => _l10n().aiScheduleLocalSaved;

  static String localSavedItem(bool isCalendar) => isCalendar
      ? _l10n().aiScheduleLocalSavedCalendar
      : _l10n().aiScheduleLocalSavedTodo;

  static String get reminderRegistered => _l10n().aiScheduleReminderRegistered;
  static String get taskReminderSubmitted =>
      _l10n().aiScheduleTaskReminderSubmitted;

  static String genericReminderIssue([AppLocale? locale]) =>
      _l10n(locale).aiScheduleGenericReminderIssue;

  static String get accountChanged => _l10n().aiScheduleAccountChanged;
  static String get inputChanged => _l10n().aiScheduleInputChanged;
  static String get genericSaveFailed => _l10n().aiScheduleGenericSaveFailed;
  static String get alarmPermissionRequired =>
      _l10n().aiScheduleAlarmPermissionRequired;
  static String get eventReminderIssueTitle =>
      _l10n().aiScheduleEventReminderIssueTitle;
  static String get taskReminderIssueTitle =>
      _l10n().aiScheduleTaskReminderIssueTitle;

  static String calendarSubtitle(bool allDay) => allDay
      ? _l10n().aiScheduleCalendarSubtitleAllDay
      : _l10n().aiScheduleCalendarSubtitle;

  static String get calendarReminderTitle =>
      _l10n().aiScheduleCalendarReminderTitle;

  static String dialogTitle({
    required bool isCalendar,
    required bool reminderFailed,
  }) {
    if (reminderFailed) {
      return isCalendar
          ? createdEventWithReminderIssue
          : createdTaskWithReminderIssue;
    }
    return isCalendar ? createdEvent : createdTask;
  }

  static String sourceLabel(AiScheduleSource source) => switch (source) {
    AiScheduleSource.ai => _l10n().aiScheduleSourceAi,
    AiScheduleSource.aiWithLocalFallback =>
      _l10n().aiScheduleSourceAiWithLocalFallback,
    AiScheduleSource.localParser => _l10n().aiScheduleSourceLocalParser,
  };

  static String warningTitle(AiScheduleDraft draft) =>
      switch (draft.warningKind) {
        AiScheduleWarningKind.missingReminderTime =>
          _l10n().aiScheduleWarningReminderNotice,
        _ => switch (draft.source) {
          AiScheduleSource.localParser => warningLocalFallback,
          AiScheduleSource.aiWithLocalFallback => warningAiIncomplete,
          AiScheduleSource.ai => _l10n().aiScheduleWarningNotice,
        },
      };

  static String warningMessage(AiScheduleDraft draft) {
    final kind = draft.warningKind;
    if (kind != null) {
      return switch (kind) {
        AiScheduleWarningKind.unavailable =>
          '${_l10n().aiScheduleWarningUnavailable} $warningAppendix',
        AiScheduleWarningKind.noUsableDraft =>
          '${_l10n().aiScheduleWarningNoUsableDraft} $warningAppendix',
        AiScheduleWarningKind.invalidResponse =>
          '${_l10n().aiScheduleWarningInvalidResponse} $warningAppendix',
        AiScheduleWarningKind.missingReminderTime =>
          _l10n().aiScheduleWarningMissingReminderTime,
      };
    }
    // Generic legacy warnings without typed warningKind:
    if (draft.source == AiScheduleSource.ai) {
      return _l10n().aiScheduleWarningReviewDraft;
    }
    return '${_l10n().aiScheduleWarningGenericFallback} $warningAppendix';
  }

  static String renderReminderIssue(Object? issue, [AppLocale? locale]) {
    if (issue is NotificationScheduleIssue) {
      if (issue.copy != null) {
        return issue.renderMessage(locale: locale);
      }
      return genericReminderIssue(locale);
    }
    if (issue is NotificationScheduleUnavailableException) {
      if (issue.copy != null) {
        return issue.renderMessage(locale: locale);
      }
      return genericReminderIssue(locale);
    }
    if (issue is TodoReminderPreflightIssue) {
      if (issue.copy != null) {
        return issue.copy!.message(locale: locale);
      }
      return genericReminderIssue(locale);
    }
    if (issue is ReminderSyncIssue) {
      final typed = issue.entries.where(
        (e) => e.copy != null || e.notice != null,
      );
      if (typed.isNotEmpty) {
        return typed.map((e) => e.render(locale: locale)).join('\n');
      }
      return genericReminderIssue(locale);
    }
    return genericReminderIssue(locale);
  }

  static String recognizeError(Object? error) {
    if (error is AiScheduleDiscardedException) return accountChanged;
    if (error is ApiException) {
      final raw = error.message.toLowerCase();
      if (raw.contains('账号') ||
          raw.contains('account') ||
          raw.contains('token')) {
        return accountChanged;
      }
    }
    if (error is AiException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('未启用') || msg.contains('not enabled')) {
        return _l10n().aiScheduleErrorNotEnabled;
      }
      // Explicit quota diagnosis only:
      if (msg.contains('额度已用尽') ||
          msg.contains('quota exceeded') ||
          msg.contains('insufficient_quota')) {
        return _l10n().aiScheduleErrorQuotaExceeded;
      }
      if (msg.contains('429') ||
          msg.contains('too many requests') ||
          msg.contains('请求过于频繁') ||
          msg.contains('rate limit')) {
        return _l10n().aiScheduleErrorRateLimit;
      }
      if (msg.contains('超时') || msg.contains('timeout')) {
        return _l10n().aiScheduleErrorTimeout;
      }
      if (msg.contains('空') || msg.contains('empty') || msg.contains('输入')) {
        return emptyInput;
      }
      if (msg.contains('账号') ||
          msg.contains('account') ||
          msg.contains('token')) {
        return accountChanged;
      }
    }
    return _l10n().aiScheduleErrorGeneric;
  }

  static String saveError(Object? error) {
    if (error is AiScheduleDiscardedException) return accountChanged;
    if (error is ApiException) {
      final raw = error.message.toLowerCase();
      if (raw.contains('账号') ||
          raw.contains('account') ||
          raw.contains('token')) {
        return accountChanged;
      }
    }
    return genericSaveFailed;
  }
}
