import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/account_preference_writes.dart';
import '../core/ics_subscription_storage.dart';
import '../core/oauth_calendar_storage.dart';
import '../core/location_reminder_storage.dart';

/// Clears data that belongs to the signed-in account.
///
/// Device-level settings such as locale and app lock are intentionally not
/// listed here. Account data, sync metadata, notification history, backup
/// targets and cached integration payloads must not survive logout or account
/// switching.
class AccountLocalDataCleaner {
  AccountLocalDataCleaner._();

  static const accountDataOwnerKey = 'duoyi_account_data_owner_v1';
  static int _accountDataGeneration = 0;
  static final ValueNotifier<int> _accountDataGenerationNotifier =
      ValueNotifier<int>(0);

  static int get accountDataGeneration => _accountDataGeneration;

  /// Signals invalidation immediately, before asynchronous cleanup begins.
  static ValueListenable<int> get accountDataGenerationListenable =>
      _accountDataGenerationNotifier;

  static bool isCurrentAccountDataGeneration(int generation) {
    return generation == _accountDataGeneration;
  }

  static void invalidateInFlightAccountWrites() {
    AccountPreferenceWrites.invalidate();
    _accountDataGeneration++;
    _accountDataGenerationNotifier.value = _accountDataGeneration;
  }

  static const accountScopedKeys = <String>{
    accountDataOwnerKey,
    'duoyi_notification_action_key_v1',
    'todos',
    'habits',
    'pomodoro_sessions',
    'pomodoro_running_snapshot',
    'pomodoro_focus_penalties',
    'pomodoro_config',
    'pomodoro_count_today',
    'pomodoro_last_date',
    'user_profile',
    'duoyi_notes',
    'duoyi_anniversaries_v2',
    'duoyi_countdowns',
    'duoyi_diary',
    'duoyi_goals',
    'duoyi_local_calendar_events_v1',
    'duoyi_time_entries',
    'duoyi_courses',
    'duoyi_course_settings',
    'duoyi_location_reminders_v1',
    'duoyi_achievements_unlocked',
    'duoyi_achievements_notified',
    'duoyi_virtual_rewards',
    'duoyi_custom_focus_sounds',
    'duoyi_focus_rooms',
    'active_brand',
    'theme_switch_count',
    'theme_unlocked_brands',
    'theme_shop_state',
    'duoyi_quick_capture_templates_v1',
    'ai_review_history',
    'duoyi_notif_history',
    'duoyi_notif_history_seen_at',
    'duoyi_widget_display_mode',
    'duoyi_widget_display_selection_v1',
    'widget_display_mode',
    'todo_kanban_columns_v1',
    'reminder_scheduler_registry_v1',
    'reminder_scheduler_display_registry_v1',
    'duoyi_ics_subscriptions_v1',
    'duoyi_oauth_calendar_accounts_v1',
    'duoyi_oauth_calendar_pending_authorization_v1',
    'duoyi_caldav_write_target_v1',
    'duoyi_caldav_pushed_uids_v1',
    'duoyi_caldav_pushed_etags_v1',
    'webdav_backup_base_url',
    'webdav_backup_username',
    'webdav_backup_password',
    'webdav_backup_remote_path',
    'webdav_backup_filename',
    'sync_last_time',
    'sync_auto',
    'sync_deleted_items',
    'sync_workspace_deleted_items',
    'sync_server_updated_at',
    'sync_server_version',
    'sync_collection_hashes',
    'sync_item_hashes',
    'sync_pending_local_changes',
    'sync_preferences_updated_at',
    'sync_preferences_values_snapshot',
    'sync_preferences_changed_keys',
    'sync_quick_capture_templates_updated_at',
    'sync_merge_decisions',
    'pref_haptic_feedback',
    'pref_show_lunar',
    'pref_show_completed_todos',
    'pref_quick_capture_fab',
    'pref_notification_quick_add',
    'pref_notification_today_progress',
    'pref_daily_reminder_enabled',
    'pref_daily_reminder_today_tasks',
    'pref_daily_reminder_tomorrow_plan',
    'pref_daily_reminder_overdue',
    'pref_daily_reminder_pause_holidays',
    'pref_daily_reminder_slot2_enabled',
    'pref_daily_reminder_slot2_today',
    'pref_daily_reminder_slot2_tomorrow',
    'pref_daily_reminder_slot2_overdue',
    'pref_daily_reminder_slot2_pause_holidays',
    'pref_daily_reminder_slot3_enabled',
    'pref_daily_reminder_slot3_today',
    'pref_daily_reminder_slot3_tomorrow',
    'pref_daily_reminder_slot3_overdue',
    'pref_daily_reminder_slot3_pause_holidays',
    'pref_daily_report_reminder',
    'pref_weekly_report_reminder',
    'pref_monthly_report_reminder',
    'pref_yearly_report_reminder',
    'pref_first_day_of_week',
    'pref_default_tab',
    'pref_default_pomodoro_minutes',
    'pref_notification_history_limit',
    'pref_auto_archive_completed_days',
    'pref_daily_reminder_hour',
    'pref_daily_reminder_minute',
    'pref_daily_reminder_slot2_hour',
    'pref_daily_reminder_slot2_minute',
    'pref_daily_reminder_slot3_hour',
    'pref_daily_reminder_slot3_minute',
    'pref_daily_report_reminder_hour',
    'pref_daily_report_reminder_minute',
    'pref_weekly_report_reminder_weekday',
    'pref_weekly_report_reminder_hour',
    'pref_weekly_report_reminder_minute',
    'pref_monthly_report_reminder_day',
    'pref_monthly_report_reminder_hour',
    'pref_monthly_report_reminder_minute',
    'pref_yearly_report_reminder_month',
    'pref_yearly_report_reminder_day',
    'pref_yearly_report_reminder_hour',
    'pref_yearly_report_reminder_minute',
    'pref_reminder_ringtone_volume_percent',
    'pref_reminder_ringtone_alarm_migrated_to_soft',
    'pref_date_format',
    'pref_app_timezone_iana',
    'pref_app_timezone_mode',
    'pref_daily_reminder_kind',
    'pref_daily_reminder_slot2_kind',
    'pref_daily_reminder_slot3_kind',
    'pref_reminder_ringtone_sound',
    'pref_daily_reminder_repeat_days',
    'pref_daily_reminder_slot2_repeat_days',
    'pref_daily_reminder_slot3_repeat_days',
    'pref_bottom_nav_order',
    'pref_bottom_nav_visible',
  };

  static const accountScopedPrefixes = <String>[
    'sync_',
    'widget_display_mode_',
    'pref_daily_reminder_slot',
    'pref_reminder_ringtone_fallback_channel_sound_',
    'pref_reminder_ringtone_fallback_channel_sound_schema_',
    'duoyi_ics_',
    'duoyi_ics_events_',
    'duoyi_oauth_calendar_',
    'duoyi_oauth_calendar_events_',
    'duoyi_caldav_',
    'todos_corrupt_backup_',
  ];

  static const accountScopedDocumentDirectories = <String>{
    'custom_focus_sounds',
    'profile_avatars',
    'avatar_cache',
  };

  static Future<T> runPreferenceBoundary<T>(Future<T> Function() operation) =>
      AccountPreferenceWrites.boundary(operation);

  static final Object _retirementZone = Object();
  static final Object _retirementWorkZone = Object();
  static Future<void>? _retirementTail;

  /// One fence covers the callback, provider resets and every cleanup pass.
  /// Nested callers inherit the same session and cannot finalize it early.
  static Future<T> runAccountRetirement<T>(Future<T> Function() operation) {
    final inherited = Zone.current[_retirementZone] as _AccountRetirementScope?;
    if (inherited != null) {
      if (inherited.session is OAuthScopeRetirementSession) {
        return Future<T>.error(const OAuthAccountRetirementPending());
      }
      return inherited.enroll(operation, _retirementWorkZone);
    }
    final announcement = OAuthCalendarStorage.announceAccountRetirement();
    return _runRetirement(operation, announcement: announcement);
  }

  /// Retires OAuth credentials and private journals without deleting ordinary
  /// guest content or invoking full-account file/provider cleanup callbacks.
  static Future<T> runOAuthScopeRetirement<T>(
    OAuthScopeRetirementRequest request,
    Future<T> Function() cleanupOwnedResources,
  ) {
    final inherited = Zone.current[_retirementZone] as _AccountRetirementScope?;
    if (inherited != null) {
      final session = inherited.session;
      if (!identical(session.preferences, request.preferences) ||
          (session is OAuthScopeRetirementSession &&
              !identical(session.request, request))) {
        return Future<T>.error(const OAuthAccountRetirementPending());
      }
      return inherited.enroll(cleanupOwnedResources, _retirementWorkZone);
    }
    if (!request.isCurrent) {
      return Future<T>.error(const OAuthAccountRetirementPending());
    }
    final announcement = OAuthCalendarStorage.announceOAuthScopeRetirement(
      store: request.preferences,
    );
    return _runRetirement(
      cleanupOwnedResources,
      announcement: announcement,
      request: request,
    );
  }

  static Future<T> _runRetirement<T>(
    Future<T> Function() operation, {
    required OAuthAccountRetirementAnnouncement announcement,
    OAuthScopeRetirementRequest? request,
  }) {
    invalidateInFlightAccountWrites();
    final previous = _retirementTail;
    final result = AccountPreferenceWrites.boundary<T>(() async {
      if (previous != null) await previous;
      final preferences =
          request?.preferences ?? await SharedPreferences.getInstance();
      final session = await OAuthCalendarStorage.run<OAuthRetirementSession>(
        () => request == null
            ? OAuthCalendarStorage.beginAccountRetirementLocked(
                preferences,
                announcement: announcement,
              )
            : OAuthCalendarStorage.beginOAuthScopeRetirementLocked(
                preferences,
                announcement: announcement,
                request: request,
              ),
        epoch: OAuthCalendarStorage.epoch,
        recovering: true,
      );
      final scope = _AccountRetirementScope(session);
      final root = _AccountRetirementWork(isRoot: true);
      return runZoned<Future<T>>(() async {
        T? value;
        try {
          value = await operation();
        } catch (error, stack) {
          scope.fail(error, stack);
        } finally {
          root.active = false;
          await scope.closeAndDrain();
        }
        try {
          scope.ensureSucceeded();
          if (session is OAuthScopeRetirementSession) {
            await OAuthCalendarStorage.run<void>(
              () async {
                await _clearOAuthPreferences(session);
                await OAuthCalendarStorage.finishOAuthScopeRetirementLocked(
                  session,
                );
              },
              epoch: OAuthCalendarStorage.epoch,
              recovering: true,
            );
          } else if (session is OAuthAccountRetirementSession) {
            await _clearPreferencesWithinSession(session);
            await OAuthCalendarStorage.run<void>(
              () => OAuthCalendarStorage.finishAccountRetirementLocked(
                session,
                hasRemainingOwnedData: (prefs) => prefs.getKeys().any(
                  (key) => !_isRetirementFence(key) && _isAccountScopedKey(key),
                ),
                onConfirmed: () {
                  LocationReminderStorage.confirmAccountClearLocked();
                  IcsSubscriptionStorage.confirmAccountClearLocked();
                  OAuthCalendarStorage.confirmAccountClearLocked(preferences);
                },
              ),
              epoch: OAuthCalendarStorage.epoch,
              recovering: true,
            );
          }
          return value as T;
        } catch (error, stack) {
          scope.fail(error, stack);
          scope.ensureSucceeded();
          rethrow;
        }
      }, zoneValues: {_retirementZone: scope, _retirementWorkZone: root});
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        OAuthCalendarStorage.failAccountRetirementAnnouncement(announcement);
      },
    );
    _retirementTail = tail;
    tail.then<void>((_) {
      if (identical(_retirementTail, tail)) _retirementTail = null;
    });
    return result;
  }

  static bool _isAccountScopedKey(String key) =>
      accountScopedKeys.contains(key) ||
      accountScopedPrefixes.any((prefix) => key.startsWith(prefix));

  static bool _isRetirementFence(String key) =>
      key == OAuthCalendarStorage.retirementFenceKey ||
      key == OAuthCalendarStorage.scopeRetirementFenceKey;

  static Future<void> _clearOAuthPreferences(
    OAuthScopeRetirementSession session,
  ) async {
    final prefs = session.preferences;
    await prefs.reload();
    OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
    Object? firstError;
    StackTrace? firstStack;
    for (final key
        in prefs
            .getKeys()
            .where(OAuthCalendarStorage.isOAuthScopeKey)
            .toList(growable: false)) {
      try {
        OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
        final removed = await prefs.remove(key);
        await prefs.reload();
        OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
        if (!removed || prefs.containsKey(key)) {
          throw const OAuthAccountRetirementPending();
        }
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    try {
      await prefs.reload();
      OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
      if (prefs.getKeys().any(OAuthCalendarStorage.isOAuthScopeKey)) {
        throw const OAuthAccountRetirementPending();
      }
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  static Future<void> clearSharedPreferences() {
    final scope = Zone.current[_retirementZone] as _AccountRetirementScope?;
    if (scope == null) return runAccountRetirement<void>(() async {});
    final session = scope.session;
    if (session is! OAuthAccountRetirementSession) {
      return Future<void>.error(const OAuthAccountRetirementPending());
    }
    // Check the inherited capability before opening a boundary, which changes
    // the write generation even when no data is removed.
    return scope.enroll(
      () => _clearPreferencesWithinSession(session),
      _retirementWorkZone,
    );
  }

  static Future<void> _clearPreferencesWithinSession(
    OAuthAccountRetirementSession session,
  ) {
    OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
    return AccountPreferenceWrites.boundary(
      () => LocationReminderStorage.run(
        () => IcsSubscriptionStorage.run(
          () => OAuthCalendarStorage.run<void>(
            () => _clearSharedPreferences(session),
            epoch: OAuthCalendarStorage.epoch,
            recovering: true,
          ),
          epoch: IcsSubscriptionStorage.epoch,
          allowUncertain: true,
        ),
        allowUncertain: true,
      ),
    );
  }

  static Future<void> _clearSharedPreferences(
    OAuthAccountRetirementSession session,
  ) async {
    final prefs = session.preferences;
    await prefs.reload();
    OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> removeKey(String key) async {
      try {
        if (_isRetirementFence(key)) return;
        OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
        if (!prefs.containsKey(key)) return;
        final removed = await prefs.remove(key);
        // A reader may reload the optimistic cache while removal awaits ACK.
        // The final authoritative reload and complete residual check below
        // prove deletion; a rejected ACK still fails this exact key.
        if (!removed) {
          throw StateError('Account preference cleanup failed: $key');
        }
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }

    for (final key in accountScopedKeys) {
      await removeKey(key);
    }
    final dynamicKeys = prefs.getKeys().where(
      (key) => accountScopedPrefixes.any((prefix) => key.startsWith(prefix)),
    );
    for (final key in dynamicKeys.toList(growable: false)) {
      await removeKey(key);
    }
    // SharedPreferences publishes cache changes before platform acknowledgement.
    // Account storage retirement requires an authoritative reload as well.
    try {
      await prefs.reload();
    } catch (e, st) {
      firstError ??= e;
      firstStackTrace ??= st;
    }
    final remaining = prefs.getKeys().where(
      (key) =>
          !_isRetirementFence(key) &&
          (accountScopedKeys.contains(key) ||
              accountScopedPrefixes.any((prefix) => key.startsWith(prefix))),
    );
    if (remaining.isNotEmpty) {
      firstError ??= StateError('Account preferences remain after cleanup');
      firstStackTrace ??= StackTrace.current;
    }
    final error = firstError;
    final stackTrace = firstStackTrace;
    if (error != null && stackTrace != null) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
  }

  static Future<void> clearLocalFiles({Directory? documentsDirectory}) async {
    final cleanup = await quarantineLocalFiles(
      documentsDirectory: documentsDirectory,
    );
    await cleanup.delete();
  }

  /// Detaches the departing account's files before a new account can write.
  ///
  /// Deleting the returned directory may run in the background: new avatars
  /// and sounds use their original paths, which this handle never removes.
  static Future<AccountLocalFileCleanup> quarantineLocalFiles({
    Directory? documentsDirectory,
  }) async {
    final root = documentsDirectory ?? await getApplicationDocumentsDirectory();
    Directory? quarantine;
    final moved = <(Directory, String)>[];

    try {
      for (final name in accountScopedDocumentDirectories) {
        final dir = Directory('${root.path}${Platform.pathSeparator}$name');
        if (!await dir.exists()) continue;
        quarantine ??= await root.createTemp('.duoyi-account-cleanup-');
        final detached = await dir.rename(
          '${quarantine.path}${Platform.pathSeparator}$name',
        );
        moved.add((detached, dir.path));
      }
    } catch (_) {
      // A failed transition must keep its files recoverable. Restore every
      // directory already moved; retain quarantine if restoration also fails.
      for (final (directory, originalPath) in moved.reversed) {
        try {
          await directory.rename(originalPath);
        } catch (_) {}
      }
      try {
        if (quarantine != null && await quarantine.list().isEmpty) {
          await quarantine.delete();
        }
      } catch (_) {
        // Preserve the staging failure when the empty-directory cleanup also
        // fails. A nonempty quarantine still holds files for recovery.
      }
      rethrow;
    }
    return AccountLocalFileCleanup._(quarantine);
  }
}

class _AccountRetirementWork {
  final bool isRoot;
  final Set<Future<void>> children = {};
  bool active = true;
  _AccountRetirementWork({this.isRoot = false});
}

class _AccountRetirementScope {
  final OAuthRetirementSession session;
  final Set<Future<void>> _pending = {};
  bool _accepting = true;
  Object? _error;
  StackTrace? _stack;

  _AccountRetirementScope(this.session);

  void fail(Object error, StackTrace stack) {
    _error ??= error;
    _stack ??= stack;
    OAuthCalendarStorage.failAccountRetirementLocked(session);
  }

  void ensureSucceeded() {
    if (_error != null) Error.throwWithStackTrace(_error!, _stack!);
    OAuthCalendarStorage.ensureRetirementCurrentLocked(session);
  }

  Future<T> enroll<T>(Future<T> Function() operation, Object workZone) {
    final parent = Zone.current[workZone] as _AccountRetirementWork?;
    if (parent == null || !parent.active || (!_accepting && parent.isRoot)) {
      return Future<T>.error(const OAuthAccountRetirementPending());
    }
    try {
      ensureSucceeded();
    } catch (error, stack) {
      return Future<T>.error(error, stack);
    }
    final completion = Completer<void>();
    final returned = Completer<T>();
    _pending.add(completion.future);
    parent.children.add(completion.future);
    final member = _AccountRetirementWork();
    final result = runZoned<Future<T>>(
      () => Future<T>.sync(operation),
      zoneValues: {workZone: member},
    );
    void settle() {
      _pending.remove(completion.future);
      parent.children.remove(completion.future);
      completion.complete();
    }

    Future<void> drainChildren() async {
      member.active = false;
      while (member.children.isNotEmpty) {
        await Future.wait(member.children.toList());
      }
    }

    result.then<void>(
      (value) async {
        await drainChildren();
        settle();
        if (_error != null) {
          returned.completeError(_error!, _stack!);
        } else {
          returned.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) async {
        fail(error, stack);
        await drainChildren();
        settle();
        returned.completeError(error, stack);
      },
    );
    // The coordinator owns failures even when the caller did not await its
    // child. The same error still reaches an awaiting caller and outer drain.
    returned.future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return returned.future;
  }

  Future<void> closeAndDrain() async {
    _accepting = false;
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }
}

class AccountLocalFileCleanup {
  final Directory? _quarantine;
  Future<void>? _deletion;

  AccountLocalFileCleanup._(this._quarantine);

  /// Removes only the detached files, including when retried after a failure.
  Future<void> delete() async {
    final pending = _deletion;
    if (pending != null) return pending;
    final task = _deleteQuarantinedFiles();
    _deletion = task;
    try {
      await task;
    } finally {
      if (identical(_deletion, task)) _deletion = null;
    }
  }

  Future<void> _deleteQuarantinedFiles() async {
    final quarantine = _quarantine;
    if (quarantine == null || !await quarantine.exists()) return;
    await quarantine.delete(recursive: true);
  }
}
