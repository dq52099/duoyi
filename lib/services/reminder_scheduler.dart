import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brand_strings.dart';
import '../core/i18n.dart';
import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/countdown.dart';
import '../models/course_schedule.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/todo.dart';
import '../providers/preferences_provider.dart' show QuietHoursPolicy;
import 'account_local_data_cleaner.dart';
import 'alarm_service.dart';
import 'notification_permission_exception.dart';
import 'reminder_sinks.dart';
import 'reminder_notification_id.dart';
import 'todo_reminder_preflight_copy.dart';
import 'reminder_issue_copy.dart';
import 'reminder_sync_issue.dart';
import 'reminder_delivery_copy.dart';
import 'reminder_schedule_display_copy.dart';

const Duration _sameMinuteReminderGrace = Duration(seconds: 70);

class TodoReminderPreflightIssue {
  final String title;
  final String message;
  final bool blocking;
  final DateTime? scheduledTime;
  final TodoReminderPreflightCopy? copy;

  const TodoReminderPreflightIssue({
    required this.title,
    required this.message,
    this.blocking = true,
    this.scheduledTime,
    this.copy,
  });

  /// Keeps the canonical diagnostics stable while carrying locale-neutral copy.
  factory TodoReminderPreflightIssue.coded(
    TodoReminderPreflightNotice notice, {
    bool blocking = true,
    DateTime? scheduledTime,
  }) {
    final copy = TodoReminderPreflightCopy(notice);
    return TodoReminderPreflightIssue(
      title: copy.title(locale: AppLocale.zh),
      message: copy.message(locale: AppLocale.zh),
      blocking: blocking,
      scheduledTime: scheduledTime,
      copy: copy,
    );
  }
}

class TodoReminderPreflightResult {
  final bool hasEnabledPlan;
  final Set<ReminderKind> kinds;
  final DateTime? firstScheduledTime;
  final List<TodoReminderPreflightIssue> issues;

  const TodoReminderPreflightResult({
    required this.hasEnabledPlan,
    required this.kinds,
    required this.firstScheduledTime,
    required this.issues,
  });

  bool get ok => issues.every((issue) => !issue.blocking);
  TodoReminderPreflightIssue? get blockingIssue {
    for (final issue in issues) {
      if (issue.blocking) return issue;
    }
    return null;
  }
}

@immutable
class ReminderScheduleSnapshotEntry {
  final String objectType;
  final String objectId;
  final List<int> ids;
  final List<Set<int>> acceptedIdSets;
  final String _rawTitle;
  final String _rawSubtitle;
  final Set<ReminderKind> kinds;
  final ReminderScheduleDisplayCopy? displayCopy;

  const ReminderScheduleSnapshotEntry({
    required this.objectType,
    required this.objectId,
    required this.ids,
    this.acceptedIdSets = const <Set<int>>[],
    required String title,
    required String subtitle,
    this.kinds = const <ReminderKind>{},
    this.displayCopy,
  }) : _rawTitle = title,
       _rawSubtitle = subtitle;

  String get title => displayFor(I18n.current).title;
  String get subtitle => displayFor(I18n.current).subtitle;

  /// Rendering retained entries has no scheduling or persistence side effects.
  ({String title, String subtitle}) displayFor(AppLocale locale) {
    final copy = displayCopy;
    if (copy == null || copy.subject.name != objectType) {
      return (title: _rawTitle, subtitle: _rawSubtitle);
    }
    return copy.render(
      title: _rawTitle,
      subtitle: _rawSubtitle,
      kinds: kinds,
      locale: locale,
    );
  }

  int get idCount => ids.length;
  String get objectKey => '$objectType:$objectId';
}

@immutable
class ReminderScheduleDisplayInfo {
  final String title;
  final String subtitle;
  final Set<ReminderKind> kinds;
  final List<Set<int>> acceptedIdSets;
  final ReminderScheduleDisplayCopy? displayCopy;

  const ReminderScheduleDisplayInfo({
    required this.title,
    required this.subtitle,
    this.kinds = const <ReminderKind>{},
    this.acceptedIdSets = const <Set<int>>[],
    this.displayCopy,
  });
}

TodoReminderPreflightResult preflightTodoReminderPlan(
  TodoItem todo, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final plan = _effectiveTodoPlanForPreflight(todo);
  final enabledRules = plan.enabled
      ? plan.rules
            .where((rule) => rule.enabled && rule.kind != ReminderKind.off)
            .toList(growable: false)
      : const <ReminderRule>[];
  if (enabledRules.isEmpty) {
    return const TodoReminderPreflightResult(
      hasEnabledPlan: false,
      kinds: <ReminderKind>{},
      firstScheduledTime: null,
      issues: <TodoReminderPreflightIssue>[],
    );
  }

  final kinds = <ReminderKind>{};
  final issues = <TodoReminderPreflightIssue>[];
  DateTime? firstScheduledTime;
  var deliverableRules = 0;

  for (final rule in enabledRules) {
    kinds.add(rule.kind);
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final anchor = _absoluteTodoReminderAnchor(todo);
        if (anchor == null) {
          issues.add(
            TodoReminderPreflightIssue.coded(
              TodoReminderPreflightNotice.missingDate,
            ),
          );
          continue;
        }
        final base = _dateAtTimeForPreflight(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        final scheduledWhen = _coerceJustMissedOneShotReminder(
          base,
          effectiveNow,
        );
        if (scheduledWhen == null) {
          issues.add(
            TodoReminderPreflightIssue.coded(
              TodoReminderPreflightNotice.timeInPast,
              scheduledTime: base,
            ),
          );
          continue;
        }
        deliverableRules++;
        if (firstScheduledTime == null ||
            scheduledWhen.isBefore(firstScheduledTime)) {
          firstScheduledTime = scheduledWhen;
        }
        break;
      case ReminderRuleType.relativeToDue:
        final anchor = _relativeTodoReminderAnchor(todo);
        if (anchor == null) {
          issues.add(
            TodoReminderPreflightIssue.coded(
              TodoReminderPreflightNotice.missingDate,
            ),
          );
          continue;
        }
        final base = _dateAtTimeForPreflight(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        final scheduledWhen = _coerceJustMissedOneShotReminder(
          when,
          effectiveNow,
        );
        if (scheduledWhen == null) {
          issues.add(
            TodoReminderPreflightIssue.coded(
              TodoReminderPreflightNotice.timeInPast,
              scheduledTime: when,
            ),
          );
          continue;
        }
        deliverableRules++;
        if (firstScheduledTime == null ||
            scheduledWhen.isBefore(firstScheduledTime)) {
          firstScheduledTime = scheduledWhen;
        }
        break;
      case ReminderRuleType.dailyTime:
        if (!_validTimeForPreflight(rule.hour, rule.minute)) {
          issues.add(
            TodoReminderPreflightIssue.coded(
              TodoReminderPreflightNotice.invalidRepeatTime,
            ),
          );
          continue;
        }
        deliverableRules++;
        break;
      case ReminderRuleType.weeklyTime:
        if (!_validTimeForPreflight(rule.hour, rule.minute) ||
            rule.weekdays.isEmpty) {
          issues.add(
            TodoReminderPreflightIssue.coded(
              TodoReminderPreflightNotice.invalidWeeklyRule,
            ),
          );
          continue;
        }
        deliverableRules++;
        break;
    }
  }

  if (deliverableRules == 0 && issues.isEmpty) {
    issues.add(
      TodoReminderPreflightIssue.coded(
        TodoReminderPreflightNotice.noDeliverableRule,
      ),
    );
  }

  return TodoReminderPreflightResult(
    hasEnabledPlan: true,
    kinds: kinds,
    firstScheduledTime: firstScheduledTime,
    issues: issues,
  );
}

ReminderPlan _effectiveTodoPlanForPreflight(TodoItem t) {
  if (t.reminderPlan.enabled && t.reminderPlan.rules.isNotEmpty) {
    return t.reminderPlan;
  }
  if (t.reminder.enabled) {
    return ReminderPlan.fromLegacy(t.reminder);
  }
  // ignore: deprecated_member_use_from_same_package
  if (t.hasReminder) {
    final anchor = t.reminderAt ?? t.dueDate;
    if (anchor == null) return const ReminderPlan.disabled();
    return ReminderPlan(
      enabled: true,
      rules: [
        ReminderRule(
          id: 'legacy-${t.id}',
          enabled: true,
          type: ReminderRuleType.absolute,
          kind: ReminderKind.push,
          hour: anchor.hour,
          minute: anchor.minute,
        ),
      ],
    );
  }
  return const ReminderPlan.disabled();
}

DateTime? _absoluteTodoReminderAnchor(TodoItem todo) =>
    todo.reminderAt ?? todo.dueDate;

DateTime? _relativeTodoReminderAnchor(TodoItem todo) =>
    todo.dueDate ?? todo.reminderAt;

DateTime _dateAtTimeForPreflight(DateTime date, int hour, int minute) {
  return DateTime(date.year, date.month, date.day, hour, minute);
}

bool _validTimeForPreflight(int? hour, int? minute) {
  return hour != null &&
      minute != null &&
      hour >= 0 &&
      hour <= 23 &&
      minute >= 0 &&
      minute <= 59;
}

DateTime? _coerceJustMissedOneShotReminder(DateTime when, DateTime now) {
  if (when.isAfter(now)) return when;
  final missedBy = now.difference(when);
  final sameLocalMinute =
      when.year == now.year &&
      when.month == now.month &&
      when.day == now.day &&
      when.hour == now.hour &&
      when.minute == now.minute;
  if (sameLocalMinute &&
      !missedBy.isNegative &&
      missedBy <= _sameMinuteReminderGrace) {
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
  }
  return null;
}

DateTime? _resolveOneShotReminderTime(
  DateTime when,
  DateTime now, {
  required bool allowJustMissed,
}) {
  if (allowJustMissed) {
    return _coerceJustMissedOneShotReminder(when, now);
  }
  return when.isAfter(now) ? when : null;
}

/// 推送 / 闹钟路由分发用的统一载荷。
class _DispatchPayload {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;

  const _DispatchPayload({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    this.payload,
    this.fullScreen = true,
    this.vibrate = true,
    this.snoozeMinutes = 0,
    this.repeatCount = 0,
  });
}

class _ScheduledRule {
  final ReminderKind kind;
  final _DispatchMode mode;
  final String scope;
  final String fingerprint;
  final String intentFingerprint;
  final String title;
  final String body;

  const _ScheduledRule({
    required this.kind,
    required this.mode,
    required this.scope,
    required this.fingerprint,
    required this.intentFingerprint,
    required this.title,
    required this.body,
  });
}

enum _DispatchMode { once, repeating }

class ReminderScheduleSyncException implements Exception {
  final List<String> failures;

  final ReminderSyncIssue? issueCopy;

  const ReminderScheduleSyncException(this.failures, {this.issueCopy});

  @override
  String toString() {
    if (failures.isEmpty) return 'ReminderScheduleSyncException';
    return 'ReminderScheduleSyncException: ${failures.join('；')}';
  }
}

class ReminderSchedulerResetException implements Exception {
  final List<String> failures;

  const ReminderSchedulerResetException(this.failures);

  @override
  String toString() {
    if (failures.isEmpty) return 'ReminderSchedulerResetException';
    return 'ReminderSchedulerResetException: ${failures.join('；')}';
  }
}

abstract class ReminderScheduleRegistry {
  const ReminderScheduleRegistry();

  Future<Map<String, Set<int>>> idsByObject(String objectType);

  Future<Map<String, ReminderScheduleDisplayInfo>> displayByObject(
    String objectType,
  );

  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  });

  Future<void> removeObject(String objectType, String objectId);

  /// Applies a reconciliation's final object state. The default keeps custom
  /// test registries compatible; persistent implementations can coalesce the
  /// underlying JSON writes.
  Future<void> applyBatch(
    Map<String, Map<String, ReminderScheduleRegistryMutation>> mutations,
  ) async {
    for (final typeEntry in mutations.entries) {
      for (final objectEntry in typeEntry.value.entries) {
        final mutation = objectEntry.value;
        if (mutation.remove || mutation.ids.isEmpty) {
          await removeObject(typeEntry.key, objectEntry.key);
        } else {
          await replaceObject(
            typeEntry.key,
            objectEntry.key,
            mutation.ids,
            display: mutation.hasDisplay ? mutation.display : null,
          );
        }
      }
    }
  }
}

class ReminderScheduleRegistryMutation {
  final bool remove;
  final Set<int> ids;
  final ReminderScheduleDisplayInfo? display;
  final bool hasDisplay;

  const ReminderScheduleRegistryMutation.remove()
    : remove = true,
      ids = const <int>{},
      display = null,
      hasDisplay = false;

  const ReminderScheduleRegistryMutation.replace(this.ids, {this.display})
    : remove = false,
      hasDisplay = display != null;
}

class SharedPreferencesReminderScheduleRegistry
    implements ReminderScheduleRegistry {
  static const _storageKey = 'reminder_scheduler_registry_v1';
  static const _displayStorageKey = 'reminder_scheduler_display_registry_v1';

  const SharedPreferencesReminderScheduleRegistry();

  @override
  Future<Map<String, Set<int>>> idsByObject(String objectType) async {
    final all = await _readAll();
    return {
      for (final entry
          in (all[objectType] ?? const <String, Set<int>>{}).entries)
        entry.key: Set<int>.from(entry.value),
    };
  }

  @override
  Future<Map<String, ReminderScheduleDisplayInfo>> displayByObject(
    String objectType,
  ) async {
    final all = await _readDisplayAll();
    return {
      for (final entry
          in (all[objectType] ?? const <String, ReminderScheduleDisplayInfo>{})
              .entries)
        entry.key: entry.value,
    };
  }

  @override
  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  }) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final normalized = ids.where((id) => id != 0).toSet();
    if (normalized.isEmpty) {
      await _removeObjectWithGeneration(
        objectType,
        objectId,
        accountGeneration: accountGeneration,
      );
      return;
    }
    final all = await _readAll();
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final typeMap = all.putIfAbsent(objectType, () => <String, Set<int>>{});
    typeMap[objectId] = normalized;
    await _writeAll(all, accountGeneration: accountGeneration);
    if (display != null) {
      await _replaceDisplayObject(
        objectType,
        objectId,
        display,
        accountGeneration: accountGeneration,
      );
    }
  }

  @override
  Future<void> removeObject(String objectType, String objectId) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _removeObjectWithGeneration(
      objectType,
      objectId,
      accountGeneration: accountGeneration,
    );
  }

  @override
  Future<void> applyBatch(
    Map<String, Map<String, ReminderScheduleRegistryMutation>> mutations,
  ) async {
    if (mutations.isEmpty) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final all = await _readAll();
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }

    final hasDisplayMutation = mutations.values.any(
      (objects) => objects.isNotEmpty,
    );
    final displays = hasDisplayMutation ? await _readDisplayAll() : null;
    for (final typeEntry in mutations.entries) {
      final typeMap = all.putIfAbsent(
        typeEntry.key,
        () => <String, Set<int>>{},
      );
      final displayTypeMap = displays?.putIfAbsent(
        typeEntry.key,
        () => <String, ReminderScheduleDisplayInfo>{},
      );
      for (final objectEntry in typeEntry.value.entries) {
        final mutation = objectEntry.value;
        if (mutation.remove || mutation.ids.isEmpty) {
          typeMap.remove(objectEntry.key);
          displayTypeMap?.remove(objectEntry.key);
          continue;
        }
        typeMap[objectEntry.key] = Set<int>.from(mutation.ids);
        if (mutation.hasDisplay && mutation.display != null) {
          displayTypeMap?[objectEntry.key] = mutation.display!;
        }
      }
      if (typeMap.isEmpty) all.remove(typeEntry.key);
      if (displayTypeMap != null && displayTypeMap.isEmpty) {
        displays!.remove(typeEntry.key);
      }
    }
    await _writeAll(all, accountGeneration: accountGeneration);
    if (displays != null) {
      await _writeDisplayAll(displays, accountGeneration: accountGeneration);
    }
  }

  Future<void> _removeObjectWithGeneration(
    String objectType,
    String objectId, {
    required int accountGeneration,
  }) async {
    final all = await _readAll();
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final typeMap = all[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) all.remove(objectType);
    await _writeAll(all, accountGeneration: accountGeneration);
    await _removeDisplayObject(
      objectType,
      objectId,
      accountGeneration: accountGeneration,
    );
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    var bindingInitialized = true;
    assert(() {
      bindingInitialized = BindingBase.debugBindingType() != null;
      return true;
    }());
    if (!bindingInitialized) return null;
    try {
      return await SharedPreferences.getInstance();
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder registry prefs unavailable: $e\n$st',
      );
      return null;
    }
  }

  Future<Map<String, Map<String, Set<int>>>> _readAll() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return <String, Map<String, Set<int>>>{};
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <String, Map<String, Set<int>>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Map<String, Set<int>>>{};
      final result = <String, Map<String, Set<int>>>{};
      decoded.forEach((type, rawObjects) {
        if (type is! String || rawObjects is! Map) return;
        final objects = <String, Set<int>>{};
        rawObjects.forEach((objectId, rawIds) {
          if (objectId is! String || rawIds is! List) return;
          final ids = <int>{};
          for (final rawId in rawIds) {
            final id = rawId is int
                ? normalizePlatformNotificationId(rawId)
                : rawId is num
                ? normalizePlatformNotificationId(rawId.toInt())
                : null;
            if (id != null && id != 0) ids.add(id);
          }
          if (ids.isNotEmpty) objects[objectId] = ids;
        });
        if (objects.isNotEmpty) result[type] = objects;
      });
      return result;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder registry decode failed: $e\n$st',
      );
      return <String, Map<String, Set<int>>>{};
    }
  }

  Future<Map<String, Map<String, ReminderScheduleDisplayInfo>>>
  _readDisplayAll() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) {
      return <String, Map<String, ReminderScheduleDisplayInfo>>{};
    }
    final raw = prefs.getString(_displayStorageKey);
    if (raw == null || raw.isEmpty) {
      return <String, Map<String, ReminderScheduleDisplayInfo>>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, Map<String, ReminderScheduleDisplayInfo>>{};
      }
      final result = <String, Map<String, ReminderScheduleDisplayInfo>>{};
      decoded.forEach((type, rawObjects) {
        if (type is! String || rawObjects is! Map) return;
        final objects = <String, ReminderScheduleDisplayInfo>{};
        rawObjects.forEach((objectId, rawDisplay) {
          if (objectId is! String || rawDisplay is! Map) return;
          final title = rawDisplay['title'];
          final subtitle = rawDisplay['subtitle'];
          if (title is! String || subtitle is! String) return;
          final cleanTitle = title.trim();
          final cleanSubtitle = subtitle.trim();
          if (cleanTitle.isEmpty && cleanSubtitle.isEmpty) return;
          objects[objectId] = ReminderScheduleDisplayInfo(
            title: title,
            subtitle: subtitle,
            kinds: _decodeReminderKinds(rawDisplay['kinds']),
            acceptedIdSets: _decodeAcceptedIdSets(
              rawDisplay['accepted_id_sets'],
            ),
            displayCopy: ReminderScheduleDisplayCopy.tryFromJson(
              rawDisplay['display_copy'],
              objectType: type,
            ),
          );
        });
        if (objects.isNotEmpty) result[type] = objects;
      });
      return result;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder display registry decode failed: $e\n$st',
      );
      return <String, Map<String, ReminderScheduleDisplayInfo>>{};
    }
  }

  Future<void> _writeAll(
    Map<String, Map<String, Set<int>>> all, {
    required int accountGeneration,
  }) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final encoded = <String, Map<String, List<int>>>{};
    for (final typeEntry in all.entries) {
      final objects = <String, List<int>>{};
      for (final objectEntry in typeEntry.value.entries) {
        final ids = objectEntry.value.where((id) => id != 0).toList()..sort();
        if (ids.isNotEmpty) objects[objectEntry.key] = ids;
      }
      if (objects.isNotEmpty) encoded[typeEntry.key] = objects;
    }
    if (encoded.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, jsonEncode(encoded));
    }
  }

  Future<void> _replaceDisplayObject(
    String objectType,
    String objectId,
    ReminderScheduleDisplayInfo display, {
    required int accountGeneration,
  }) async {
    final all = await _readDisplayAll();
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final typeMap = all.putIfAbsent(
      objectType,
      () => <String, ReminderScheduleDisplayInfo>{},
    );
    typeMap[objectId] = display;
    await _writeDisplayAll(all, accountGeneration: accountGeneration);
  }

  Future<void> _removeDisplayObject(
    String objectType,
    String objectId, {
    required int accountGeneration,
  }) async {
    final all = await _readDisplayAll();
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final typeMap = all[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) all.remove(objectType);
    await _writeDisplayAll(all, accountGeneration: accountGeneration);
  }

  Future<void> _writeDisplayAll(
    Map<String, Map<String, ReminderScheduleDisplayInfo>> all, {
    required int accountGeneration,
  }) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final encoded = <String, Map<String, Map<String, Object>>>{};
    for (final typeEntry in all.entries) {
      final objects = <String, Map<String, Object>>{};
      for (final objectEntry in typeEntry.value.entries) {
        objects[objectEntry.key] = {
          'title': objectEntry.value.title,
          'subtitle': objectEntry.value.subtitle,
          if (objectEntry.value.displayCopy != null)
            'display_copy': objectEntry.value.displayCopy!.toJson(),
          if (objectEntry.value.kinds.isNotEmpty)
            'kinds': objectEntry.value.kinds.map((kind) => kind.name).toList(),
          if (objectEntry.value.acceptedIdSets.isNotEmpty)
            'accepted_id_sets': objectEntry.value.acceptedIdSets
                .map((ids) => (ids.toList()..sort()))
                .toList(),
        };
      }
      if (objects.isNotEmpty) encoded[typeEntry.key] = objects;
    }
    if (encoded.isEmpty) {
      await prefs.remove(_displayStorageKey);
    } else {
      await prefs.setString(_displayStorageKey, jsonEncode(encoded));
    }
  }

  Set<ReminderKind> _decodeReminderKinds(Object? raw) {
    if (raw is! List) return const <ReminderKind>{};
    final kinds = <ReminderKind>{};
    for (final value in raw) {
      ReminderKind? kind;
      if (value is String) {
        for (final candidate in ReminderKind.values) {
          if (candidate.name == value) {
            kind = candidate;
            break;
          }
        }
      } else if (value is int &&
          value >= 0 &&
          value < ReminderKind.values.length) {
        kind = ReminderKind.values[value];
      }
      if (kind != null && kind != ReminderKind.off) kinds.add(kind);
    }
    return kinds.isEmpty ? const <ReminderKind>{} : Set.unmodifiable(kinds);
  }

  List<Set<int>> _decodeAcceptedIdSets(Object? raw) {
    if (raw is! List) return const <Set<int>>[];
    final result = <Set<int>>[];
    for (final rawSet in raw) {
      if (rawSet is! List) continue;
      final ids = <int>{};
      for (final rawId in rawSet) {
        final id = rawId is int
            ? rawId
            : rawId is num
            ? rawId.toInt()
            : null;
        if (id != null && id != 0) ids.add(id);
      }
      if (ids.isNotEmpty) result.add(Set<int>.unmodifiable(ids));
    }
    return result.isEmpty
        ? const <Set<int>>[]
        : List<Set<int>>.unmodifiable(result);
  }
}

@visibleForTesting
class InMemoryReminderScheduleRegistry implements ReminderScheduleRegistry {
  final Map<String, Map<String, Set<int>>> _store = {};
  final Map<String, Map<String, ReminderScheduleDisplayInfo>> _displayStore =
      {};

  @visibleForTesting
  int batchApplyCalls = 0;

  @override
  Future<Map<String, Set<int>>> idsByObject(String objectType) async {
    return {
      for (final entry
          in (_store[objectType] ?? const <String, Set<int>>{}).entries)
        entry.key: Set<int>.from(entry.value),
    };
  }

  @override
  Future<Map<String, ReminderScheduleDisplayInfo>> displayByObject(
    String objectType,
  ) async {
    return {
      for (final entry
          in (_displayStore[objectType] ??
                  const <String, ReminderScheduleDisplayInfo>{})
              .entries)
        entry.key: entry.value,
    };
  }

  @override
  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  }) async {
    final normalized = ids.where((id) => id != 0).toSet();
    if (normalized.isEmpty) {
      await removeObject(objectType, objectId);
      return;
    }
    _store.putIfAbsent(objectType, () => <String, Set<int>>{})[objectId] =
        normalized;
    if (display != null) {
      _displayStore.putIfAbsent(
        objectType,
        () => <String, ReminderScheduleDisplayInfo>{},
      )[objectId] = display;
    }
  }

  @override
  Future<void> removeObject(String objectType, String objectId) async {
    final typeMap = _store[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) _store.remove(objectType);
    final displayTypeMap = _displayStore[objectType];
    if (displayTypeMap == null) return;
    displayTypeMap.remove(objectId);
    if (displayTypeMap.isEmpty) _displayStore.remove(objectType);
  }

  @override
  Future<void> applyBatch(
    Map<String, Map<String, ReminderScheduleRegistryMutation>> mutations,
  ) async {
    batchApplyCalls++;
    for (final typeEntry in mutations.entries) {
      for (final objectEntry in typeEntry.value.entries) {
        final mutation = objectEntry.value;
        if (mutation.remove || mutation.ids.isEmpty) {
          final typeMap = _store[typeEntry.key];
          typeMap?.remove(objectEntry.key);
          if (typeMap?.isEmpty == true) _store.remove(typeEntry.key);
          final displayTypeMap = _displayStore[typeEntry.key];
          displayTypeMap?.remove(objectEntry.key);
          if (displayTypeMap?.isEmpty == true) {
            _displayStore.remove(typeEntry.key);
          }
          continue;
        }
        _store.putIfAbsent(
          typeEntry.key,
          () => <String, Set<int>>{},
        )[objectEntry.key] = Set<int>.from(
          mutation.ids,
        );
        if (mutation.hasDisplay && mutation.display != null) {
          _displayStore.putIfAbsent(
            typeEntry.key,
            () => <String, ReminderScheduleDisplayInfo>{},
          )[objectEntry.key] = mutation.display!;
        }
      }
    }
  }
}

class _BatchAwareReminderScheduleRegistry implements ReminderScheduleRegistry {
  final ReminderScheduleRegistry delegate;
  ReminderReconciliationBatch? activeBatch;

  _BatchAwareReminderScheduleRegistry(this.delegate);

  @override
  Future<Map<String, Set<int>>> idsByObject(String objectType) async {
    final persisted = await delegate.idsByObject(objectType);
    return activeBatch?.overlayIds(objectType, persisted) ?? persisted;
  }

  @override
  Future<Map<String, ReminderScheduleDisplayInfo>> displayByObject(
    String objectType,
  ) async {
    final persisted = await delegate.displayByObject(objectType);
    return activeBatch?.overlayDisplays(objectType, persisted) ?? persisted;
  }

  @override
  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  }) async {
    final batch = activeBatch;
    if (batch == null) {
      await delegate.replaceObject(objectType, objectId, ids, display: display);
      return;
    }
    batch.stageReplace(objectType, objectId, ids, display: display);
  }

  @override
  Future<void> removeObject(String objectType, String objectId) async {
    final batch = activeBatch;
    if (batch == null) {
      await delegate.removeObject(objectType, objectId);
      return;
    }
    batch.stageRemove(objectType, objectId);
  }

  @override
  Future<void> applyBatch(
    Map<String, Map<String, ReminderScheduleRegistryMutation>> mutations,
  ) => delegate.applyBatch(mutations);

  Future<void> flushBatch(ReminderReconciliationBatch batch) {
    if (!identical(activeBatch, batch)) return Future<void>.value();
    return delegate.applyBatch(batch.registryMutations);
  }
}

@visibleForTesting
class ReminderReconciliationBatchMetrics {
  final int pendingSnapshotCalls;
  final int pendingFallbackCalls;
  final int pendingProbeFailures;
  final int registryMutationCount;
  final int registryFlushCalls;

  const ReminderReconciliationBatchMetrics({
    required this.pendingSnapshotCalls,
    required this.pendingFallbackCalls,
    required this.pendingProbeFailures,
    required this.registryMutationCount,
    required this.registryFlushCalls,
  });
}

class ReminderReconciliationBatch {
  final ReminderScheduler owner;
  final int accountChangeGeneration;
  final Map<ReminderPendingSink, Future<Set<int>>> _pendingSnapshots = {};
  final Set<ReminderPendingSink> _pendingSnapshotFailures = {};
  final Map<String, Map<String, ReminderScheduleRegistryMutation>>
  registryMutations = {};
  final Map<String, Map<String, Set<int>>> cancellationIds = {};
  var pendingSnapshotCalls = 0;
  var pendingFallbackCalls = 0;
  var pendingProbeFailures = 0;
  var registryMutationCount = 0;
  var registryFlushCalls = 0;

  ReminderReconciliationBatch(this.owner, this.accountChangeGeneration);

  bool snapshotFailed(ReminderPendingSink sink) =>
      _pendingSnapshotFailures.contains(sink);

  Future<Set<int>> pendingIds(ReminderPendingSink sink) {
    final existing = _pendingSnapshots[sink];
    if (existing != null) return existing;
    final future = () async {
      pendingSnapshotCalls++;
      try {
        return (await sink.pendingIds()).toSet();
      } catch (_) {
        pendingProbeFailures++;
        _pendingSnapshotFailures.add(sink);
        rethrow;
      }
    }();
    _pendingSnapshots[sink] = future;
    return future.catchError((Object error, StackTrace stack) {
      _pendingSnapshots.remove(sink);
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<Set<int>> fallbackPendingIds(ReminderPendingSink sink) async {
    pendingFallbackCalls++;
    return (await sink.pendingIds()).toSet();
  }

  Map<String, Set<int>> overlayIds(
    String objectType,
    Map<String, Set<int>> persisted,
  ) {
    final result = {
      for (final entry in persisted.entries)
        entry.key: Set<int>.from(entry.value),
    };
    final mutations = registryMutations[objectType];
    if (mutations == null) return result;
    for (final entry in mutations.entries) {
      final mutation = entry.value;
      if (mutation.remove || mutation.ids.isEmpty) {
        result.remove(entry.key);
      } else {
        result[entry.key] = Set<int>.from(mutation.ids);
      }
    }
    return result;
  }

  Map<String, ReminderScheduleDisplayInfo> overlayDisplays(
    String objectType,
    Map<String, ReminderScheduleDisplayInfo> persisted,
  ) {
    final result = Map<String, ReminderScheduleDisplayInfo>.from(persisted);
    final mutations = registryMutations[objectType];
    if (mutations == null) return result;
    for (final entry in mutations.entries) {
      final mutation = entry.value;
      if (mutation.remove || mutation.ids.isEmpty) {
        result.remove(entry.key);
      } else if (mutation.hasDisplay && mutation.display != null) {
        result[entry.key] = mutation.display!;
      }
    }
    return result;
  }

  void stageReplace(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  }) {
    final normalized = ids.where((id) => id != 0).toSet();
    cancellationIds
        .putIfAbsent(objectType, () => <String, Set<int>>{})
        .putIfAbsent(objectId, () => <int>{})
        .addAll(normalized);
    final typeMap = registryMutations.putIfAbsent(
      objectType,
      () => <String, ReminderScheduleRegistryMutation>{},
    );
    typeMap[objectId] = normalized.isEmpty
        ? const ReminderScheduleRegistryMutation.remove()
        : ReminderScheduleRegistryMutation.replace(
            normalized,
            display: display,
          );
    registryMutationCount++;
  }

  void stageRemove(String objectType, String objectId) {
    final typeMap = registryMutations.putIfAbsent(
      objectType,
      () => <String, ReminderScheduleRegistryMutation>{},
    );
    typeMap[objectId] = const ReminderScheduleRegistryMutation.remove();
    registryMutationCount++;
  }

  Future<void> flush() async {
    if (!owner._canRunAccountGeneration(accountChangeGeneration)) {
      if (owner._schedulingSuspendedForAccountChange) {
        await owner._retainInterruptedBatchOwnership(cancellationIds);
      }
      return;
    }
    if (registryMutations.isEmpty) return;
    registryFlushCalls++;
    await owner._batchRegistry.flushBatch(this);
  }

  ReminderReconciliationBatchMetrics metrics() =>
      ReminderReconciliationBatchMetrics(
        pendingSnapshotCalls: pendingSnapshotCalls,
        pendingFallbackCalls: pendingFallbackCalls,
        pendingProbeFailures: pendingProbeFailures,
        registryMutationCount: registryMutationCount,
        registryFlushCalls: registryFlushCalls,
      );
}

class _ResolvedRule {
  final String objectType;
  final String objectId;
  final String ruleId;
  final ReminderKind kind;
  final _DispatchMode mode;
  final ReminderRuleType ruleType;
  final String title;
  final String body;
  final String payload;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;
  final DateTime? when;
  final int? hour;
  final int? minute;
  final List<int> weekdays;
  final String scope;
  final String quietHoursDigest;

  const _ResolvedRule({
    required this.objectType,
    required this.objectId,
    required this.ruleId,
    required this.kind,
    required this.mode,
    required this.ruleType,
    required this.title,
    required this.body,
    required this.payload,
    required this.fullScreen,
    required this.vibrate,
    required this.snoozeMinutes,
    required this.repeatCount,
    required this.scope,
    this.quietHoursDigest = '',
    this.when,
    this.hour,
    this.minute,
    this.weekdays = const <int>[],
  });

  String get key => '$objectType:$objectId:$ruleId';

  // These rule families keep verbatim user content in body. Presentation titles
  // can change with language or branding without changing the delivery intent.
  String get intentFingerprint => jsonEncode([
    objectType,
    objectId,
    ruleId,
    kind.name,
    mode.name,
    ruleType.name,
    scope,
    quietHoursDigest,
    body,
    payload,
    fullScreen,
    vibrate,
    snoozeMinutes,
    repeatCount,
    when?.toIso8601String(),
    hour,
    minute,
    weekdays,
  ]);

  String get fingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      kind.index,
      mode.name,
      ruleType.index,
      scope,
      quietHoursDigest,
      title,
      body,
      payload,
      fullScreen ? 'fs1' : 'fs0',
      vibrate ? 'v1' : 'v0',
      snoozeMinutes,
      repeatCount,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }

  String get deliveryFingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      kind.index,
      mode.name,
      scope,
      quietHoursDigest,
      body,
      payload,
      fullScreen ? 'fs1' : 'fs0',
      vibrate ? 'v1' : 'v0',
      snoozeMinutes,
      repeatCount,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }

  String get logicalDeliveryFingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      objectType,
      objectId,
      mode.name,
      scope,
      body,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }
}

/// 根据 todo / habit / anniversary / goal 数据幂等地同步本地通知 / 闹钟队列。
///
/// 每次数据变化时由 `main.dart` 调用对应的 `syncXxx` 或 [resyncAll]。服务
/// 内部保证：
/// 1. 先取消自己管理过的 id（同时清理 push 与 alarm 两条通道，防止 `kind`
///    由 `push` 翻转到 `alarm` 时出现遗留调度）；
/// 2. 再按最新数据通过 [_dispatch] 路由到 `NotificationService`（push）或
///    `AlarmService`（alarm）重新下发。
///
/// R4.1 / R4.4 / R4.5 / R4.7 / R4.8：本类是协调器，职责严格与
/// `NotificationService` 和 `AlarmService` 分离；两者互不直接通话。
class ReminderScheduler {
  static const int maxActiveAlarms = 380;

  static const List<String> _registryObjectTypes = <String>[
    'todo',
    'goal',
    'habit',
    'anniversary',
    'countdown',
    'course',
    'calendar_event',
  ];
  static const List<String> _blockingAlarmScheduleIssuePhrases = <String>[
    '闹钟提醒已降级注册',
    '精准闹钟权限未开启',
    '闹钟提醒通知权限未开启',
    '内置闹钟铃声注册失败',
    '内置重复闹钟铃声注册失败',
    '强提醒弹屏权限未开启',
    '强提醒渠道需要检查',
    '闹钟提醒注册失败',
    '重复闹钟注册失败',
    '闹钟兜底通知注册失败',
    '重复闹钟兜底通知注册失败',
    '闹钟兜底通知待触发队列需确认',
    '重复闹钟兜底通知待触发队列需确认',
  ];

  final ReminderNotificationSink notif;
  final ReminderAlarmSink alarm;
  final ReminderEmailSink email;
  final ReminderPopupSink popup;
  final ReminderScheduleRegistry registry;

  /// 上一轮已下发的 todo / goal rule → 通道与调度形态。
  final Map<String, Map<String, _ScheduledRule>> _scheduledTodoRules = {};
  final Map<String, Map<String, _ScheduledRule>> _scheduledGoalRules = {};
  final Map<String, String> _scheduledHabitScopes = {};
  final Map<String, String> _scheduledAnniversaryScopes = {};
  final Map<String, String> _scheduledCountdownScopes = {};
  final Map<String, String> _scheduledCourseScopes = {};
  final Map<String, String> _scheduledCalendarEventScopes = {};
  final Map<String, ReminderScheduleDisplayInfo> _registeredReminderDisplay =
      {};
  final Map<String, ReminderSyncIssueEntry> _todoScheduleFailures = {};
  final Map<int, DateTime> _budgetedAlarmTimes = <int, DateTime>{};
  final Map<int, ({String objectType, String objectId})> _budgetedAlarmOwners =
      <int, ({String objectType, String objectId})>{};
  QuietHoursPolicy _quietHours = const QuietHoursPolicy();
  Future<void> _syncQueue = Future<void>.value();
  ReminderReconciliationBatch? _activeBatch;
  Map<ReminderPendingSink, Future<Set<int>>>? _ephemeralPendingIds;
  ReminderReconciliationBatchMetrics? _lastBatchMetrics;
  int _accountChangeGeneration = 0;
  bool _schedulingSuspendedForAccountChange = false;
  final Map<String, Map<String, Set<int>>> _interruptedBatchIds = {};

  QuietHoursPolicy get quietHours => _quietHours;

  @visibleForTesting
  int get debugActiveBudgetCount => _budgetedAlarmTimes.length;

  void updateQuietHours(QuietHoursPolicy policy) {
    if (_quietHours == policy) return;
    _quietHours = policy;
  }

  /// [notif] 必传；[alarm] 默认取 `AlarmService.instance` 单例，便于测试时
  /// 注入 fake。[popup] 未注入时默认落到 [notif] 作为系统通知兜底，避免
  /// popup 规则被空实现缓存为“已调度”。[email] 默认 no-op，未配置邮件
  /// 服务时不会误发本地通知。各通道均以 sink 接口表达，便于属性测试注入。
  ReminderScheduler(
    this.notif, {
    ReminderAlarmSink? alarm,
    ReminderEmailSink? email,
    ReminderPopupSink? popup,
    ReminderScheduleRegistry? registry,
  }) : alarm = alarm ?? AlarmService.instance,
       email = email ?? const NoopReminderEmailSink(),
       popup = popup ?? NotificationFallbackReminderPopupSink(notif),
       registry = _BatchAwareReminderScheduleRegistry(
         registry ?? const SharedPreferencesReminderScheduleRegistry(),
       );

  @visibleForTesting
  int debugScheduledTodoRuleCount(String todoId) {
    return _scheduledTodoRules[todoId]?.length ?? 0;
  }

  @visibleForTesting
  ReminderReconciliationBatchMetrics? get debugLastBatchMetrics =>
      _lastBatchMetrics;

  _BatchAwareReminderScheduleRegistry get _batchRegistry =>
      registry as _BatchAwareReminderScheduleRegistry;

  Future<T?> runReconciliationBatch<T>(
    Future<T> Function(ReminderReconciliationBatch batch) action,
  ) {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return Future<T?>.value(null);
    return _runSerialized(() async {
      if (!_canRunAccountGeneration(generation)) return null;
      final batch = ReminderReconciliationBatch(this, generation);
      _activeBatch = batch;
      _batchRegistry.activeBatch = batch;
      try {
        if (notif is ReminderNotificationBatchSink) {
          return await (notif as ReminderNotificationBatchSink)
              .runNotificationBatch(() => action(batch));
        }
        return await action(batch);
      } finally {
        try {
          await batch.flush();
        } finally {
          _batchRegistry.activeBatch = null;
          _activeBatch = null;
          _lastBatchMetrics = batch.metrics();
        }
      }
    });
  }

  /// Prevents old-account reminder snapshots from being queued or committed.
  ///
  /// Call this synchronously after the pending cloud changes have been flushed
  /// and before the first asynchronous account cleanup step. Already-running
  /// work is allowed to finish; the serialized reset that follows cancels its
  /// registrations before the new account is resumed.
  void suspendForAccountChange() {
    if (_schedulingSuspendedForAccountChange) return;
    _accountChangeGeneration++;
    _schedulingSuspendedForAccountChange = true;
  }

  /// Re-enables reminder scheduling after the active account providers are safe.
  void resumeForActiveAccount() {
    _accountChangeGeneration++;
    _schedulingSuspendedForAccountChange = false;
  }

  bool _canRunAccountGeneration(int generation) {
    return !_schedulingSuspendedForAccountChange &&
        generation == _accountChangeGeneration;
  }

  Future<void> _retainInterruptedBatchOwnership(
    Map<String, Map<String, Set<int>>> idsByType,
  ) async {
    for (final type in idsByType.entries) {
      final retained = _interruptedBatchIds.putIfAbsent(
        type.key,
        () => <String, Set<int>>{},
      );
      for (final object in type.value.entries) {
        if (object.value.isEmpty) continue;
        retained.putIfAbsent(object.key, () => <int>{}).addAll(object.value);
      }
    }
    await _persistInterruptedBatchOwnership();
  }

  Future<void> _persistInterruptedBatchOwnership() async {
    if (_interruptedBatchIds.isEmpty) return;
    // Use the delegate so a stale batch cannot hide cancellation ownership
    // with its staged removals. Preserve IDs without committing old displays.
    final delegate = _batchRegistry.delegate;
    final mutations = <String, Map<String, ReminderScheduleRegistryMutation>>{};
    for (final type in _interruptedBatchIds.entries) {
      final persisted = await delegate.idsByObject(type.key);
      mutations[type.key] = {
        for (final object in type.value.entries)
          object.key: ReminderScheduleRegistryMutation.replace({
            ...persisted[object.key] ?? const <int>{},
            ...object.value,
          }),
      };
    }
    await delegate.applyBatch(mutations);
  }

  Future<void> _runSerializedForAccountGeneration(
    int generation,
    Future<void> Function() action,
  ) {
    if (!_canRunAccountGeneration(generation)) return Future<void>.value();
    return _runSerialized(() async {
      if (!_canRunAccountGeneration(generation)) return;
      final createdCache =
          _activeBatch == null && _ephemeralPendingIds == null;
      if (createdCache) {
        _ephemeralPendingIds = <ReminderPendingSink, Future<Set<int>>>{};
      }
      try {
        await action();
      } finally {
        if (createdCache) {
          _ephemeralPendingIds = null;
        }
      }
    });
  }

  Future<List<ReminderScheduleSnapshotEntry>> registeredRemindersSnapshot() {
    return _runSerialized(_registeredRemindersSnapshotLocked);
  }

  Future<List<ReminderScheduleSnapshotEntry>>
  _registeredRemindersSnapshotLocked() async {
    final result = <ReminderScheduleSnapshotEntry>[];
    for (final objectType in _registryObjectTypes) {
      final byObject = await registry.idsByObject(objectType);
      final persistedDisplays = await registry.displayByObject(objectType);
      for (final entry in byObject.entries) {
        final ids = entry.value.where((id) => id != 0).toList()..sort();
        if (ids.isEmpty) continue;
        final display = _snapshotDisplayFor(
          objectType,
          entry.key,
          persisted: persistedDisplays[entry.key],
        );
        result.add(
          ReminderScheduleSnapshotEntry(
            objectType: objectType,
            objectId: entry.key,
            ids: List<int>.unmodifiable(ids),
            acceptedIdSets: display.acceptedIdSets,
            title: display.title,
            subtitle: display.subtitle,
            kinds: display.kinds,
            displayCopy: display.displayCopy,
          ),
        );
      }
    }
    result.sort((a, b) {
      final typeCompare = _registryObjectTypes
          .indexOf(a.objectType)
          .compareTo(_registryObjectTypes.indexOf(b.objectType));
      if (typeCompare != 0) return typeCompare;
      return a.objectId.compareTo(b.objectId);
    });
    return List<ReminderScheduleSnapshotEntry>.unmodifiable(result);
  }

  ReminderScheduleDisplayInfo _snapshotDisplayFor(
    String objectType,
    String objectId, {
    ReminderScheduleDisplayInfo? persisted,
  }) {
    final stored = _registeredReminderDisplay['$objectType:$objectId'];
    if (stored != null) {
      return _withAcceptedIdSets(
        stored,
        persisted?.acceptedIdSets ?? const <Set<int>>[],
      );
    }
    if (persisted != null) return persisted;
    final scheduledRules = switch (objectType) {
      'todo' => _scheduledTodoRules[objectId],
      'goal' => _scheduledGoalRules[objectId],
      _ => null,
    };
    if (scheduledRules != null && scheduledRules.isNotEmpty) {
      return _displayFromScheduledRules(
        objectType,
        scheduledRules.values,
        _acceptedPendingIdSetsForScheduledRules(
          objectType,
          objectId,
          scheduledRules,
        ),
      );
    }
    final typeLabel = _objectTypeLabel(objectType);
    final subject = _subjectForType(objectType);
    return ReminderScheduleDisplayInfo(
      title: '$typeLabel提醒',
      subtitle: '$typeLabel · 已登记到系统提醒队列',
      displayCopy: subject == null
          ? null
          : ReminderScheduleDisplayCopy.registered(subject),
    );
  }

  ReminderScheduleSubject? _subjectForType(String objectType) {
    return switch (objectType) {
      'todo' => ReminderScheduleSubject.todo,
      'goal' => ReminderScheduleSubject.goal,
      'habit' => ReminderScheduleSubject.habit,
      'anniversary' => ReminderScheduleSubject.anniversary,
      'countdown' => ReminderScheduleSubject.countdown,
      _ => null,
    };
  }

  ReminderScheduleDisplayInfo _displayFromScheduledRules(
    String objectType,
    Iterable<_ScheduledRule> rules,
    List<Set<int>> acceptedIdSets,
  ) {
    final list = rules.toList(growable: false);
    final typeLabel = _objectTypeLabel(objectType);
    final subject = _subjectForType(objectType);
    final userTitle = list
        .map((rule) => rule.body)
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    final title = userTitle.isEmpty ? '$typeLabel提醒' : userTitle;
    final kinds = _kindsFromScheduledRules(list);
    final kindLabel = kinds.map(_kindLabel).toSet().join('、');
    final repeating = list.any((rule) => rule.mode == _DispatchMode.repeating);
    final cadence = repeating ? '重复提醒' : '一次提醒';
    return ReminderScheduleDisplayInfo(
      title: title,
      subtitle:
          '$typeLabel · $cadence · ${kindLabel.isEmpty ? '系统提醒' : kindLabel} · ${list.length} 条规则',
      kinds: kinds,
      acceptedIdSets: _normalizedAcceptedIdSets(acceptedIdSets),
      displayCopy: subject == null
          ? null
          : ReminderScheduleDisplayCopy.rules(
              subject,
              defaultTitle: userTitle.isEmpty,
              repeating: repeating,
              ruleCount: list.length,
            ),
    );
  }

  void _rememberReminderDisplay(
    String objectType,
    String objectId, {
    required String title,
    required String subtitle,
    Set<ReminderKind> kinds = const <ReminderKind>{},
    ReminderScheduleDisplayCopy? displayCopy,
  }) {
    final trimmedTitle = title.trim();
    _registeredReminderDisplay['$objectType:$objectId'] =
        ReminderScheduleDisplayInfo(
          title: trimmedTitle.isEmpty
              ? '${_objectTypeLabel(objectType)}提醒'
              : title,
          subtitle: subtitle.trim().isEmpty
              ? '${_objectTypeLabel(objectType)} · 已登记到系统提醒队列'
              : subtitle,
          kinds: Set<ReminderKind>.unmodifiable(
            kinds.where((kind) => kind != ReminderKind.off),
          ),
          acceptedIdSets: const <Set<int>>[],
          displayCopy: displayCopy,
        );
  }

  void _forgetReminderDisplay(String objectType, String objectId) {
    _registeredReminderDisplay.remove('$objectType:$objectId');
  }

  ReminderScheduleDisplayInfo? _registryDisplayFor(
    String objectType,
    String objectId, {
    Iterable<_ScheduledRule>? scheduledRules,
    Iterable<_ResolvedRule>? resolvedRules,
    List<Set<int>> acceptedIdSets = const <Set<int>>[],
  }) {
    final stored = _registeredReminderDisplay['$objectType:$objectId'];
    if (stored != null) {
      return _withAcceptedIdSets(stored, acceptedIdSets);
    }
    final scheduledList = scheduledRules?.toList(growable: false);
    if (scheduledList != null && scheduledList.isNotEmpty) {
      return _displayFromScheduledRules(
        objectType,
        scheduledList,
        acceptedIdSets,
      );
    }
    final resolvedList = resolvedRules?.toList(growable: false);
    if (resolvedList != null && resolvedList.isNotEmpty) {
      return _displayFromResolvedRules(
        objectType,
        resolvedList,
        acceptedIdSets,
      );
    }
    if (acceptedIdSets.isEmpty) return null;
    final subject = _subjectForType(objectType);
    return ReminderScheduleDisplayInfo(
      title: '${_objectTypeLabel(objectType)}提醒',
      subtitle: '${_objectTypeLabel(objectType)} · 已登记到系统提醒队列',
      acceptedIdSets: _normalizedAcceptedIdSets(acceptedIdSets),
      displayCopy: subject == null
          ? null
          : ReminderScheduleDisplayCopy.registered(subject),
    );
  }

  ReminderScheduleDisplayInfo _displayFromResolvedRules(
    String objectType,
    Iterable<_ResolvedRule> rules,
    List<Set<int>> acceptedIdSets,
  ) {
    final list = rules.toList(growable: false);
    final typeLabel = _objectTypeLabel(objectType);
    final subject = _subjectForType(objectType);
    final userTitle = list
        .map((rule) => rule.body)
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    final title = userTitle.isEmpty ? '$typeLabel提醒' : userTitle;
    final kinds = _kindsFromResolvedRules(list);
    final kindLabel = kinds.map(_kindLabel).toSet().join('、');
    final repeating = list.any((rule) => rule.mode == _DispatchMode.repeating);
    final cadence = repeating ? '重复提醒' : '一次提醒';
    return ReminderScheduleDisplayInfo(
      title: title,
      subtitle:
          '$typeLabel · $cadence · ${kindLabel.isEmpty ? '系统提醒' : kindLabel} · ${list.length} 条规则',
      kinds: kinds,
      acceptedIdSets: _normalizedAcceptedIdSets(acceptedIdSets),
      displayCopy: subject == null
          ? null
          : ReminderScheduleDisplayCopy.rules(
              subject,
              defaultTitle: userTitle.isEmpty,
              repeating: repeating,
              ruleCount: list.length,
            ),
    );
  }

  ReminderScheduleDisplayInfo _withAcceptedIdSets(
    ReminderScheduleDisplayInfo display,
    List<Set<int>> acceptedIdSets,
  ) {
    final normalized = _normalizedAcceptedIdSets(acceptedIdSets);
    if (normalized.isEmpty) return display;
    return ReminderScheduleDisplayInfo(
      title: display.title,
      subtitle: display.subtitle,
      kinds: display.kinds,
      acceptedIdSets: normalized,
      displayCopy: display.displayCopy,
    );
  }

  List<Set<int>> _normalizedAcceptedIdSets(Iterable<Set<int>> groups) {
    final seen = <String>{};
    final result = <Set<int>>[];
    for (final group in groups) {
      final ids = group.where((id) => id != 0).toList()..sort();
      if (ids.isEmpty) continue;
      final signature = ids.join(',');
      if (!seen.add(signature)) continue;
      result.add(Set<int>.unmodifiable(ids));
    }
    return result.isEmpty
        ? const <Set<int>>[]
        : List<Set<int>>.unmodifiable(result);
  }

  List<Set<int>> _combineAcceptedIdSetAlternatives(
    Iterable<List<Set<int>>> alternativesByRule,
  ) {
    var sawRule = false;
    var combinations = <Set<int>>[<int>{}];
    for (final rawAlternatives in alternativesByRule) {
      final alternatives = _normalizedAcceptedIdSets(rawAlternatives);
      if (alternatives.isEmpty) return const <Set<int>>[];
      sawRule = true;
      final next = <Set<int>>[];
      for (final combination in combinations) {
        for (final alternative in alternatives) {
          next.add(<int>{...combination, ...alternative});
        }
      }
      combinations = next;
    }
    if (!sawRule) return const <Set<int>>[];
    return _normalizedAcceptedIdSets(combinations);
  }

  Set<ReminderKind> _kindsFromScheduledRules(Iterable<_ScheduledRule> rules) {
    final kinds = <ReminderKind>{
      for (final rule in rules)
        if (rule.kind != ReminderKind.off) rule.kind,
    };
    return kinds.isEmpty ? const <ReminderKind>{} : Set.unmodifiable(kinds);
  }

  Set<ReminderKind> _kindsFromResolvedRules(Iterable<_ResolvedRule> rules) {
    final kinds = <ReminderKind>{
      for (final rule in rules)
        if (rule.kind != ReminderKind.off) rule.kind,
    };
    return kinds.isEmpty ? const <ReminderKind>{} : Set.unmodifiable(kinds);
  }

  bool _kindUsesSystemPendingQueue(ReminderKind kind) {
    return kind == ReminderKind.push || kind == ReminderKind.alarm;
  }

  List<Set<int>> _acceptedPendingIdSetsForResolvedRules(
    Iterable<_ResolvedRule> rules,
  ) {
    return _combineAcceptedIdSetAlternatives([
      for (final rule in rules)
        if (_kindUsesSystemPendingQueue(rule.kind))
          _acceptedPendingIdSetsForRule(rule),
    ]);
  }

  List<Set<int>> _acceptedPendingIdSetsForScheduledRules(
    String objectType,
    String objectId,
    Map<String, _ScheduledRule> rules,
  ) {
    return _combineAcceptedIdSetAlternatives([
      for (final entry in rules.entries)
        if (_kindUsesSystemPendingQueue(entry.value.kind))
          _acceptedPendingIdSetsForScheduledRule(
            objectType,
            objectId,
            entry.key,
            entry.value,
          ),
    ]);
  }

  List<Set<int>> _acceptedPendingIdSetsForScheduledRule(
    String objectType,
    String objectId,
    String ruleId,
    _ScheduledRule rule,
  ) {
    final base = _idFor('$objectType:$objectId:$ruleId');
    if (rule.mode == _DispatchMode.once) {
      return <Set<int>>[
        <int>{base},
      ];
    }
    final weekdays = _weekdaysFromScope(rule.scope);
    return _acceptedRepeatingPendingIdSets(
      kind: rule.kind,
      base: base,
      weekdays: weekdays,
    );
  }

  Future<void> _replaceRegistryObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    Iterable<_ScheduledRule>? scheduledRules,
    Iterable<_ResolvedRule>? resolvedRules,
    List<Set<int>> acceptedIdSets = const <Set<int>>[],
  }) {
    return registry.replaceObject(
      objectType,
      objectId,
      ids,
      display: _registryDisplayFor(
        objectType,
        objectId,
        scheduledRules: scheduledRules,
        resolvedRules: resolvedRules,
        acceptedIdSets: acceptedIdSets,
      ),
    );
  }

  String _objectTypeLabel(String objectType) {
    return switch (objectType) {
      'todo' => '待办',
      'goal' => '目标',
      'habit' => '日常',
      'anniversary' => '纪念日',
      'countdown' => '倒数日',
      'course' => '课程',
      'calendar_event' => '日程',
      _ => '事项',
    };
  }

  String _kindLabel(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.push => '普通通知',
      ReminderKind.popup => '弹出提醒',
      ReminderKind.alarm => '闹钟提醒',
      ReminderKind.email => '邮件提醒',
      ReminderKind.off => '关闭',
    };
  }

  String _timeLabel(int? hour, int? minute) {
    if (!_validTime(hour, minute)) return '时间未设置';
    return '${hour!.toString().padLeft(2, '0')}:${minute!.toString().padLeft(2, '0')}';
  }

  String _weekdaysLabel(List<int> weekdays) {
    if (weekdays.isEmpty || weekdays.length == 7) return '每天';
    const labels = <int, String>{
      1: '周一',
      2: '周二',
      3: '周三',
      4: '周四',
      5: '周五',
      6: '周六',
      7: '周日',
    };
    return weekdays
        .map((day) => labels[day] ?? '')
        .where((v) => v.isNotEmpty)
        .join('、');
  }

  String _dateTimeLabel(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  void _rememberHabitReminderDisplay(Habit habit) {
    final rule = _effectiveHabitPlan(habit).primaryRule;
    if (rule == null) return;
    final weekdays = _habitWeekdays(habit, rule);
    final kinds = _enabledHabitRules(habit)
        .map((rule) => rule.kind)
        .where((kind) => kind != ReminderKind.off)
        .toSet();
    _rememberReminderDisplay(
      'habit',
      habit.id,
      title: habit.name,
      subtitle:
          '日常 · ${_kindLabel(rule.kind)} · ${_weekdaysLabel(weekdays)} ${_timeLabel(rule.hour, rule.minute)}',
      kinds: kinds,
      displayCopy: ReminderScheduleDisplayCopy.habit(
        defaultTitle: habit.name.trim().isEmpty,
        primaryKind: rule.kind,
        weekdays: weekdays,
        hour: _validTime(rule.hour, rule.minute) ? rule.hour : null,
        minute: _validTime(rule.hour, rule.minute) ? rule.minute : null,
      ),
    );
  }

  void _rememberAnniversaryReminderDisplay(
    Anniversary item,
    DateTime remindAt,
  ) {
    _rememberReminderDisplay(
      'anniversary',
      item.id,
      title: item.title,
      subtitle:
          '纪念日 · ${_kindLabel(item.reminderKind)} · ${_dateTimeLabel(remindAt)}',
      kinds: item.reminderKind == ReminderKind.off
          ? const <ReminderKind>{}
          : <ReminderKind>{item.reminderKind},
      displayCopy:
          item.reminderKind == ReminderKind.off ||
              remindAt.year < 1 ||
              remindAt.year > 9999
          ? null
          : ReminderScheduleDisplayCopy.dated(
              ReminderScheduleSubject.anniversary,
              defaultTitle: item.title.trim().isEmpty,
              primaryKind: item.reminderKind,
              at: remindAt,
            ),
    );
  }

  void _rememberCountdownReminderDisplay(
    CountdownItem item,
    DateTime remindAt,
  ) {
    _rememberReminderDisplay(
      'countdown',
      item.id,
      title: item.title,
      subtitle:
          '倒数日 · ${_kindLabel(item.reminderKind)} · ${_dateTimeLabel(remindAt)}',
      kinds: item.reminderKind == ReminderKind.off
          ? const <ReminderKind>{}
          : <ReminderKind>{item.reminderKind},
      displayCopy:
          item.reminderKind == ReminderKind.off ||
              remindAt.year < 1 ||
              remindAt.year > 9999
          ? null
          : ReminderScheduleDisplayCopy.dated(
              ReminderScheduleSubject.countdown,
              defaultTitle: item.title.trim().isEmpty,
              primaryKind: item.reminderKind,
              at: remindAt,
            ),
    );
  }

  /// Clears scheduler-owned in-memory state during account cleanup.
  ///
  /// Platform notifications and alarms may already have been removed by their
  /// services, but popup timers and this scheduler's rule cache live in memory.
  /// If they survive an account switch, a same-id/same-rule reminder from the
  /// next account can be treated as already scheduled, especially for popup
  /// reminders which do not expose a system pending queue.
  Future<void> resetInMemoryState() {
    suspendForAccountChange();
    return _runSerialized(_resetInMemoryStateLocked);
  }

  Future<void> _resetInMemoryStateLocked() async {
    // A failed persistence attempt retains the memory ledger and blocks the
    // transition. The next reset retries it before cancelling any ownership.
    await _persistInterruptedBatchOwnership();
    final failures = <String>[];
    final failedObjectKeys = <String>{};

    Future<void> cancelObjects(
      String objectType,
      Iterable<String> knownIds,
    ) async {
      var registryReadable = true;
      Map<String, Set<int>> persisted;
      try {
        persisted = await registry.idsByObject(objectType);
      } catch (e, st) {
        registryReadable = false;
        persisted = <String, Set<int>>{};
        debugPrint(
          '[ReminderScheduler] reset registry read failed for '
          '$objectType: $e\n$st',
        );
        failures.add('$objectType reminder registry could not be read: $e');
      }
      final interrupted =
          _interruptedBatchIds[objectType] ?? const <String, Set<int>>{};
      final objectIds = <String>{
        ...persisted.keys,
        ...knownIds,
        ...interrupted.keys,
      };
      for (final objectId in objectIds) {
        final ids = <int>{
          ...persisted[objectId] ?? const <int>{},
          ...interrupted[objectId] ?? const <int>{},
        };
        switch (objectType) {
          case 'todo':
            ids.addAll(
              _registryIdsForScheduledRules(
                'todo',
                objectId,
                _scheduledTodoRules[objectId] ??
                    const <String, _ScheduledRule>{},
              ),
            );
            // Also sweep the legacy owner id in case it predates the registry.
            ids.add(_idFor('todo_$objectId'));
            break;
          case 'goal':
            ids.addAll(
              _registryIdsForScheduledRules(
                'goal',
                objectId,
                _scheduledGoalRules[objectId] ??
                    const <String, _ScheduledRule>{},
              ),
            );
            ids.add(_idFor('goal_$objectId'));
            break;
          case 'habit':
            ids.add(_idFor('habit_$objectId'));
            break;
          case 'anniversary':
            ids
              ..add(_idFor('anni_$objectId'))
              ..add(_idFor('anni_alarm_$objectId'));
            break;
          case 'countdown':
            ids.add(_idFor('countdown:$objectId:due'));
            break;
          case 'course':
            ids.add(_idFor('course:$objectId:next'));
            break;
          case 'calendar_event':
            ids.add(_idFor('calendar_event:$objectId'));
            break;
        }

        var cancelled = await _cancelIds(objectType, objectId, ids);
        cancelled = switch (objectType) {
          'todo' => await _cancelTodoLegacy(objectId) && cancelled,
          'goal' => await _cancelGoalLegacy(objectId) && cancelled,
          'habit' => await _cancelHabit(objectId) && cancelled,
          'anniversary' => await _cancelAnniversary(objectId) && cancelled,
          'countdown' => await _cancelCountdown(objectId) && cancelled,
          'course' => await _cancelCourse(objectId) && cancelled,
          'calendar_event' => await _cancelCalendarEvent(objectId) && cancelled,
          _ => cancelled,
        };
        if (!cancelled) {
          failedObjectKeys.add('$objectType:$objectId');
          failures.add('$objectType:$objectId reminder cancellation failed');
          continue;
        }
        if (!registryReadable) {
          failedObjectKeys.add('$objectType:$objectId');
          continue;
        }

        try {
          await registry.removeObject(objectType, objectId);
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] reset registry cleanup failed for '
            '$objectType:$objectId: $e\n$st',
          );
          failedObjectKeys.add('$objectType:$objectId');
          failures.add('$objectType:$objectId registry cleanup failed: $e');
          continue;
        }
        _interruptedBatchIds[objectType]?.remove(objectId);
        if (_interruptedBatchIds[objectType]?.isEmpty == true) {
          _interruptedBatchIds.remove(objectType);
        }

        switch (objectType) {
          case 'todo':
            _scheduledTodoRules.remove(objectId);
            break;
          case 'goal':
            _scheduledGoalRules.remove(objectId);
            break;
          case 'habit':
            _scheduledHabitScopes.remove(objectId);
            break;
          case 'anniversary':
            _scheduledAnniversaryScopes.remove(objectId);
            break;
          case 'countdown':
            _scheduledCountdownScopes.remove(objectId);
            break;
          case 'course':
            _scheduledCourseScopes.remove(objectId);
            break;
          case 'calendar_event':
            _scheduledCalendarEventScopes.remove(objectId);
            break;
        }
      }
    }

    await cancelObjects('todo', _scheduledTodoRules.keys);
    await cancelObjects('goal', _scheduledGoalRules.keys);
    await cancelObjects('habit', _scheduledHabitScopes.keys);
    await cancelObjects('anniversary', _scheduledAnniversaryScopes.keys);
    await cancelObjects('countdown', _scheduledCountdownScopes.keys);
    await cancelObjects('course', _scheduledCourseScopes.keys);
    await cancelObjects('calendar_event', _scheduledCalendarEventScopes.keys);

    _registeredReminderDisplay.removeWhere(
      (objectKey, _) => !failedObjectKeys.contains(objectKey),
    );
    _budgetedAlarmTimes.clear();
    _budgetedAlarmOwners.clear();
    if (failures.isNotEmpty) {
      throw ReminderSchedulerResetException(
        List<String>.unmodifiable(failures),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 公共 API
  // -------------------------------------------------------------------------

  /// 按最新的 [todos] 幂等地重新同步待办提醒。
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    final snapshot = todos.toList(growable: false);
    Future<void> action() async {
      _todoScheduleFailures.clear();
      await _syncTodosLocked(
        snapshot,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
    }

    if (batch != null) {
      if (!identical(batch, _activeBatch)) {
        throw StateError('Reminder reconciliation batch is not active');
      }
      if (batch.accountChangeGeneration != generation ||
          !_canRunAccountGeneration(generation)) {
        return;
      }
      await action();
      return;
    }
    await _runSerializedForAccountGeneration(generation, action);
  }

  Future<void> syncSingleTodo(
    TodoItem todo, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    await _runSerializedForAccountGeneration(generation, () async {
      _todoScheduleFailures.remove(todo.id);
      final persisted =
          (await registry.idsByObject('todo'))[todo.id] ?? const <int>{};
      if (todo.isCompleted) {
        final prior = _scheduledTodoRules[todo.id];
        final cancelledPrior = prior == null
            ? true
            : await _cancelRuleObjects('todo', todo.id, prior.keys);
        final legacyOk = await _cancelTodoLegacy(todo.id);
        final staleCancelled = persisted.isEmpty
            ? true
            : await _cancelIds('todo', todo.id, persisted, blocking: false);
        if (cancelledPrior && legacyOk && staleCancelled) {
          _scheduledTodoRules.remove(todo.id);
          _forgetReminderDisplay('todo', todo.id);
          await registry.removeObject('todo', todo.id);
        }
        return;
      }

      final resolved = _resolveTodoRules(
        todo,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      if (resolved.isEmpty) {
        _recordUnresolvedTodoReminderIssue(todo);
        final failure = _unresolvedTodoReminderFailureSummary(todo);
        final cancelled = await _cancelCurrentTodoPlan(todo);
        if (cancelled) {
          _scheduledTodoRules.remove(todo.id);
          _forgetReminderDisplay('todo', todo.id);
        }
        if (failure != null) {
          throw ReminderScheduleSyncException(
            [failure.raw],
            issueCopy: ReminderSyncIssue([failure]),
          );
        }
        return;
      }

      final nextRules = <String, _ResolvedRule>{
        for (final rule in resolved) rule.ruleId: rule,
      };
      final wantedIds = {
        for (final rule in nextRules.values) ..._registryIdsForRule(rule),
      };
      final staleIds = persisted.difference(wantedIds);
      final blockedRegistryIds = <int>{};
      if (staleIds.isNotEmpty) {
        final ok = await _cancelIds('todo', todo.id, staleIds, blocking: false);
        if (!ok) blockedRegistryIds.addAll(staleIds);
      }

      final priorRules =
          _scheduledTodoRules[todo.id] ?? const <String, _ScheduledRule>{};
      final kept = <String, _ScheduledRule>{};
      final failures = <ReminderSyncIssueEntry>[];
      await _cancelTodoLegacy(todo.id, blocking: false);

      for (final priorEntry in priorRules.entries) {
        if (!nextRules.containsKey(priorEntry.key)) {
          final cancelled = await _cancelRule('todo', todo.id, priorEntry.key);
          if (!cancelled) kept[priorEntry.key] = priorEntry.value;
        }
      }
      for (final nextRule in nextRules.values) {
        final prior = priorRules[nextRule.ruleId];
        final changed = prior != null && !_sameScheduledRule(prior, nextRule);
        if (changed) {
          await _cancelRule(
            'todo',
            todo.id,
            nextRule.ruleId,
            blocking: false,
            includeEmail: !_isLocalPresentationChange(prior, nextRule),
          );
        } else if (prior != null && await _scheduledRuleStillPending(nextRule)) {
          _recordRuleBudget(nextRule);
          kept[nextRule.ruleId] = prior;
          continue;
        } else if (prior != null) {
          final cancelled = await _cancelRule('todo', todo.id, nextRule.ruleId);
          if (!cancelled) {
            kept[nextRule.ruleId] = prior;
            continue;
          }
        }
        final budgetResult = await _prepareRuleDispatchForBudget(nextRule);
        if (budgetResult == _BudgetDecision.skip) continue;
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _scheduledFromResolved(nextRule);
        } else {
          _releaseBudgetIds(_registryIdsForRule(nextRule));
          _recordTodoRuleDispatchFailure(nextRule);
          _recordRuleScheduleFailure(nextRule);
          failures.add(_ruleScheduleFailureEntry(nextRule));
        }
      }

      if (kept.isNotEmpty) {
        _scheduledTodoRules[todo.id] = kept;
        await _replaceRegistryObject(
          'todo',
          todo.id,
          {
            ...blockedRegistryIds,
            ..._registryIdsForScheduledRules('todo', todo.id, kept),
          },
          scheduledRules: kept.values,
          acceptedIdSets: _acceptedPendingIdSetsForScheduledRules(
            'todo',
            todo.id,
            kept,
          ),
        );
      } else {
        _scheduledTodoRules.remove(todo.id);
        _forgetReminderDisplay('todo', todo.id);
        if (blockedRegistryIds.isEmpty) {
          await registry.removeObject('todo', todo.id);
        }
      }
      if (failures.isNotEmpty) {
        throw ReminderScheduleSyncException(
          failures.map((e) => e.raw).toList(growable: false),
          issueCopy: ReminderSyncIssue(failures),
        );
      }
    });
  }

  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) => ReminderTodoFailureFuture(
    _syncTodosAndGetTodoIssue(
      todos,
      todoId,
      allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
    ),
  );

  Future<ReminderSyncIssue?> _syncTodosAndGetTodoIssue(
    Iterable<TodoItem> todos,
    String todoId, {
    required bool allowJustMissedOneShotReminders,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return null;
    final snapshot = todos.toList(growable: false);
    ReminderSyncIssue? failure;
    await _runSerializedForAccountGeneration(generation, () async {
      _todoScheduleFailures.remove(todoId);
      try {
        await _syncTodosLocked(
          snapshot,
          allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
        );
      } on ReminderScheduleSyncException {
        // 单对象反馈只报告目标待办；其他规则的失败已写入诊断。
      }
      if (_canRunAccountGeneration(generation)) {
        final entry = _todoScheduleFailures[todoId];
        failure = entry == null ? null : ReminderSyncIssue([entry]);
      }
    });
    return failure;
  }

  Future<void> _syncTodosLocked(
    Iterable<TodoItem> todos, {
    required bool allowJustMissedOneShotReminders,
  }) async {
    final todoSnapshot = todos.toList(growable: false);
    final wanted = <String, Map<String, _ResolvedRule>>{};
    final scheduleFailures = <ReminderSyncIssueEntry>[];
    for (final t in todoSnapshot) {
      if (t.isCompleted) {
        await _cancelCurrentTodoPlan(t);
        continue;
      }
      final resolved = _resolveTodoRules(
        t,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      if (resolved.isEmpty) {
        _recordUnresolvedTodoReminderIssue(t);
        final failure = _unresolvedTodoReminderFailureSummary(t);
        if (failure != null) {
          scheduleFailures.add(failure);
        }
        await _cancelCurrentTodoPlan(t);
        continue;
      }
      wanted[t.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    final blockedRegistryIds = await _sweepRuleRegistry(
      objectType: 'todo',
      wanted: wanted,
    );
    await _syncRuleObjects(
      objectType: 'todo',
      wanted: wanted,
      scheduled: _scheduledTodoRules,
      cancelLegacy: _cancelTodoLegacy,
      blockedRegistryIdsByObject: blockedRegistryIds,
    );
    if (scheduleFailures.isNotEmpty) {
      throw ReminderScheduleSyncException(
        List<String>.unmodifiable(scheduleFailures.map((entry) => entry.raw)),
        issueCopy: ReminderSyncIssue(scheduleFailures),
      );
    }
  }

  void _recordUnresolvedTodoReminderIssue(TodoItem todo) {
    final preflight = preflightTodoReminderPlan(todo);
    if (!preflight.hasEnabledPlan || preflight.ok) return;
    final blocking = preflight.blockingIssue;
    final issue =
        blocking ?? (preflight.issues.isEmpty ? null : preflight.issues.first);
    if (issue == null) return;
    _todoScheduleFailures[todo.id] = ReminderSyncIssueEntry(
      issue.message,
      copy: issue.copy == null
          ? null
          : ReminderIssueCopy.preflight(issue.copy!),
      rawTitle: issue.title,
      rawMessage: issue.message,
    );
    final copySink = notif is ReminderScheduleIssueCopySink
        ? notif as ReminderScheduleIssueCopySink
        : null;
    if (copySink != null && issue.copy != null) {
      copySink.recordReminderScheduleIssueWithCopy(
        title: issue.title,
        message: issue.message,
        copy: ReminderIssueCopy.preflight(issue.copy!),
        scheduledTime: issue.scheduledTime,
        relatedId: todo.id,
        blocking: issue.blocking,
      );
      return;
    }
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: issue.title,
      message: issue.message,
      scheduledTime: issue.scheduledTime,
      relatedId: todo.id,
      blocking: issue.blocking,
    );
  }

  ReminderSyncIssueEntry? _unresolvedTodoReminderFailureSummary(TodoItem todo) {
    final preflight = preflightTodoReminderPlan(todo);
    if (!preflight.hasEnabledPlan || preflight.ok) return null;
    final blocking = preflight.blockingIssue;
    final issue =
        blocking ?? (preflight.issues.isEmpty ? null : preflight.issues.first);
    if (issue == null) return null;
    return ReminderSyncIssueEntry(
      '${issue.title}：${issue.message}',
      copy: issue.copy == null
          ? null
          : ReminderIssueCopy.preflight(issue.copy!),
      includeTitle: true,
      rawTitle: issue.title,
      rawMessage: issue.message,
    );
  }

  bool _recordAlarmScheduleIssue({
    required String relatedId,
    DateTime? scheduledTime,
    bool blocking = false,
    Set<int>? alarmIds,
  }) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null || alarm is! AlarmService) return false;
    final alarmService = alarm as AlarmService;
    final issue = alarmService.lastScheduleIssue;
    if (issue == null) return false;
    if (!_alarmScheduleIssueMatches(issue, alarmIds)) return false;
    final effectiveBlocking =
        blocking ||
        _isAlarmScheduleIssueBlocking(
          title: issue.title,
          message: issue.message,
        );
    issueSink.recordReminderScheduleIssue(
      title: issue.title,
      message: issue.message,
      scheduledTime: issue.scheduledTime ?? scheduledTime,
      relatedId: relatedId,
      blocking: effectiveBlocking,
    );
    alarmService.clearScheduleIssue(
      ids: alarmIds == null || alarmIds.isEmpty ? null : alarmIds,
    );
    return effectiveBlocking;
  }

  bool _alarmScheduleIssueMatches(
    AlarmScheduleIssue issue,
    Set<int>? alarmIds,
  ) {
    if (alarmIds == null || alarmIds.isEmpty) return true;
    final issueId = issue.id;
    return issueId != null && alarmIds.contains(issueId);
  }

  String _issueRelatedIdForPayload(_DispatchPayload payload) {
    return _relatedIdFromReminderPayload(payload.payload) ??
        payload.id.toString();
  }

  String? _relatedIdFromReminderPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.scheme != 'duoyi' || uri.pathSegments.isEmpty) {
      return null;
    }
    return switch (uri.host) {
      'todo' ||
      'habit' ||
      'anniversary' ||
      'countdown' ||
      'goal' ||
      'location' => uri.pathSegments.first,
      _ => null,
    };
  }

  String? _relatedIdFromIssueLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return null;
    final fromPayload = _relatedIdFromReminderPayload(trimmed);
    if (fromPayload != null) return fromPayload;
    final normalized = trimmed.startsWith('email:')
        ? trimmed.substring('email:'.length)
        : trimmed;
    final match = RegExp(
      r'^(todo|habit|anniversary|countdown|goal|location)(?:\s+[A-Za-z_]+)*:([^:#\s)]+)',
    ).firstMatch(normalized);
    return match?.group(2);
  }

  Set<int> _alarmIssueIdsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    return <int>{base, ..._expectedPendingIdsForRule(rule)};
  }

  Set<int> _alarmIssueIdsForRepeating(int base, List<int> weekdays) {
    return <int>{base, ..._expectedRepeatingPendingIds(base, weekdays)};
  }

  void _recordRuleScheduleFailure(_ResolvedRule rule) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: _ruleScheduleFailureTitle(rule),
      message: _ruleScheduleFailureMessage(rule),
      scheduledTime: rule.when,
      relatedId: rule.objectId,
      blocking: true,
    );
  }

  String _ruleScheduleFailureTitle(_ResolvedRule rule) {
    return switch (rule.objectType) {
      'todo' => '待办提醒注册失败',
      'goal' => '目标提醒注册失败',
      _ => '提醒注册失败',
    };
  }

  String _ruleScheduleFailureMessage(_ResolvedRule rule) {
    final target = rule.body.trim().isEmpty ? '该提醒' : '“${rule.body}”';
    final channel = _kindLabel(rule.kind);
    final hint = switch (rule.kind) {
      ReminderKind.popup => '请保持应用前台运行，或开启系统通知权限以便后台兜底。',
      ReminderKind.alarm => '请检查通知权限、精准闹钟权限、全屏提醒权限和强提醒渠道。',
      ReminderKind.push => '请检查系统通知权限和通知渠道。',
      ReminderKind.email => '请检查邮件提醒服务配置。',
      ReminderKind.off => '请重新启用提醒方式。',
    };
    return '$target 的$channel未注册成功。$hint';
  }

  String _ruleScheduleFailureSummary(_ResolvedRule rule) {
    return '${_ruleScheduleFailureTitle(rule)}：${_ruleScheduleFailureMessage(rule)}';
  }

  ReminderSyncIssueEntry _ruleScheduleFailureEntry(_ResolvedRule rule) =>
      ReminderSyncIssueEntry(
        _ruleScheduleFailureSummary(rule),
        notice: ReminderSyncIssueNotice.ruleNotRegistered,
        kind: rule.kind,
        target: rule.body,
        object: switch (rule.objectType) {
          'todo' => ReminderSyncObject.task,
          'goal' => ReminderSyncObject.goal,
          _ => ReminderSyncObject.reminder,
        },
      );

  void _recordSingleScheduleFailure({
    required String title,
    required String target,
    required ReminderKind kind,
    DateTime? scheduledTime,
    String? relatedId,
  }) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: title,
      message: _singleScheduleFailureMessage(target: target, kind: kind),
      scheduledTime: scheduledTime,
      relatedId: relatedId,
      blocking: true,
    );
  }

  String _singleScheduleFailureSummary({
    required String title,
    required String target,
    required ReminderKind kind,
  }) {
    return '$title：${_singleScheduleFailureMessage(target: target, kind: kind)}';
  }

  String _singleScheduleFailureMessage({
    required String target,
    required ReminderKind kind,
  }) {
    final name = target.trim().isEmpty ? '该提醒' : '“${target.trim()}”';
    final channel = _kindLabel(kind);
    final hint = switch (kind) {
      ReminderKind.popup => '请保持应用前台运行，或开启系统通知权限以便后台兜底。',
      ReminderKind.alarm => '请检查通知权限、精准闹钟权限、全屏提醒权限和强提醒渠道。',
      ReminderKind.push => '请检查系统通知权限和通知渠道。',
      ReminderKind.email => '请检查邮件提醒服务配置。',
      ReminderKind.off => '请重新启用提醒方式。',
    };
    return '$name 的$channel未注册成功。$hint';
  }

  void _recordHabitScheduleFailure(Habit habit) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: '习惯提醒注册失败',
      message: _habitScheduleFailureMessage(habit),
      relatedId: habit.id,
      blocking: true,
    );
  }

  String _habitScheduleFailureMessage(Habit habit) {
    final name = habit.name.trim().isEmpty ? '该习惯' : '“${habit.name}”';
    final kinds = _enabledHabitRules(
      habit,
    ).map((rule) => _kindLabel(rule.kind)).toSet().join('、');
    final channel = kinds.isEmpty ? '提醒' : kinds;
    return '$name 的$channel未完整注册。请检查通知权限、前台弹出兜底、精准闹钟或全屏提醒权限后重新保存。';
  }

  String _habitScheduleFailureSummary(Habit habit) {
    return '习惯提醒注册失败：${_habitScheduleFailureMessage(habit)}';
  }

  bool _isAlarmScheduleIssueBlocking({required String title, String? message}) {
    final text = '$title\n${message ?? ''}';
    return _blockingAlarmScheduleIssuePhrases.any(text.contains);
  }

  /// 按最新的 [habits] 幂等地重新同步习惯提醒。
  ///
  /// 习惯提醒按用户选择走通知、应用内弹窗或柔和强提醒闹钟。闹钟权限不足时
  /// 降级为普通 push，确保不会静默丢提醒。
  Future<void> syncHabits(
    Iterable<Habit> habits, {
    ReminderReconciliationBatch? batch,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    final snapshot = habits.toList(growable: false);
    Future<void> action() => _syncHabitsLocked(snapshot);
    if (batch != null) {
      if (!identical(batch, _activeBatch)) {
        throw StateError('Reminder reconciliation batch is not active');
      }
      if (batch.accountChangeGeneration != generation ||
          !_canRunAccountGeneration(generation)) {
        return;
      }
      await action();
      return;
    }
    await _runSerializedForAccountGeneration(generation, action);
  }

  /// Incrementally updates reminder scheduling for one [habit] without scanning
  /// or cancelling unrelated habits.
  Future<void> syncSingleHabit(Habit habit) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    await _runSerializedForAccountGeneration(generation, () async {
      final plan = _effectiveHabitPlan(habit);
      final rule = plan.primaryRule;
      if (!plan.enabled ||
          rule == null ||
          !rule.enabled ||
          rule.kind == ReminderKind.off) {
        final baseId = _idFor('habit_${habit.id}');
        final storedIds =
            (await registry.idsByObject('habit'))[habit.id] ?? const <int>{};
        final extraIds = storedIds.where((id) => id != baseId).toSet();
        final cancelled = await _cancelHabit(habit.id);
        final extraCancelled = extraIds.isEmpty
            ? true
            : await _cancelIds('habit', habit.id, extraIds, blocking: false);
        if (cancelled && extraCancelled) {
          _scheduledHabitScopes.remove(habit.id);
          _forgetReminderDisplay('habit', habit.id);
          await registry.removeObject('habit', habit.id);
        }
        return;
      }

      final wantedIds = _habitRegistryIds(habit);
      final storedIds =
          (await registry.idsByObject('habit'))[habit.id] ?? const <int>{};
      final staleIds = storedIds.difference(wantedIds);
      final blockedRegistryIds = <int>{};
      if (staleIds.isNotEmpty) {
        final ok = await _cancelIds(
          'habit',
          habit.id,
          staleIds,
          blocking: false,
        );
        if (!ok) blockedRegistryIds.addAll(staleIds);
      }

      final scope = _habitScopeWithQuietHours(habit);
      if (!_scheduledHabitScopes.containsKey(habit.id)) {
        final swept = await _cancelHabit(habit.id);
        if (!swept) return;
      } else if (_scheduledHabitScopes[habit.id] == scope) {
        if (await _habitStillPending(habit)) {
          _recordHabitBudget(habit);
          _rememberHabitReminderDisplay(habit);
          await _replaceRegistryObject('habit', habit.id, {
            ...blockedRegistryIds,
            ...wantedIds,
          }, acceptedIdSets: _habitAcceptedPendingIdSets(habit));
          return;
        }
        final cancelled = await _cancelHabit(habit.id);
        if (!cancelled) return;
        _scheduledHabitScopes.remove(habit.id);
        _forgetReminderDisplay('habit', habit.id);
        await registry.removeObject('habit', habit.id);
      } else {
        final cancelled = await _cancelHabit(habit.id);
        if (!cancelled) return;
        _scheduledHabitScopes.remove(habit.id);
      }

      final budgetOk = await _reserveHabitBudget(habit);
      if (!budgetOk) return;
      final scheduled = await _scheduleHabit(habit);
      if (scheduled) {
        _rememberHabitReminderDisplay(habit);
        _scheduledHabitScopes[habit.id] = scope;
        await _replaceRegistryObject('habit', habit.id, {
          ...blockedRegistryIds,
          ...wantedIds,
        }, acceptedIdSets: _habitAcceptedPendingIdSets(habit));
      } else {
        _releaseBudgetIds(wantedIds);
        _recordHabitScheduleFailure(habit);
        throw ReminderScheduleSyncException([_habitScheduleFailureSummary(habit)]);
      }
    });
  }

  Future<void> _syncHabitsLocked(Iterable<Habit> habits) async {
    final wanted = <String, Habit>{};
    final handledInactiveHabitIds = <String>{};
    final scheduleFailures = <String>[];
    for (final h in habits) {
      final plan = _effectiveHabitPlan(h);
      final rule = plan.primaryRule;
      if (!plan.enabled ||
          rule == null ||
          !rule.enabled ||
          rule.kind == ReminderKind.off) {
        handledInactiveHabitIds.add(h.id);
        // 多提醒时间习惯被关闭时，主 id 之外的派生 id 不在 wanted 内、也不会
        // 进入 sweep，需要在此显式清理，避免遗漏的提醒成为孤儿继续触发。
        final baseId = _idFor('habit_${h.id}');
        final storedIds =
            (await registry.idsByObject('habit'))[h.id] ?? const <int>{};
        final extraIds = storedIds.where((id) => id != baseId).toSet();
        final cancelled = await _cancelHabit(h.id);
        final extraCancelled = extraIds.isEmpty
            ? true
            : await _cancelIds('habit', h.id, extraIds, blocking: false);
        if (cancelled && extraCancelled) {
          _scheduledHabitScopes.remove(h.id);
          _forgetReminderDisplay('habit', h.id);
          await registry.removeObject('habit', h.id);
        }
        continue;
      }
      wanted[h.id] = h;
    }
    final scopes = <String, String>{};
    for (final h in wanted.values) {
      scopes[h.id] = _habitScopeWithQuietHours(h);
      _rememberHabitReminderDisplay(h);
    }
    final blockedHabitIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'habit',
      wantedIdsByObject: {
        for (final h in wanted.values) h.id: _habitRegistryIds(h),
      },
    );

    final blockedHabitIds = <String>{};
    for (final id in _scheduledHabitScopes.keys.toList()) {
      if (handledInactiveHabitIds.contains(id)) continue;
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledHabitScopes[id] != nextScope) {
        final cancelled = await _cancelHabit(id);
        if (cancelled) {
          _scheduledHabitScopes.remove(id);
          _forgetReminderDisplay('habit', id);
          await registry.removeObject('habit', id);
        } else {
          blockedHabitIds.add(id);
        }
      }
    }
    for (final h in wanted.values) {
      if (blockedHabitIds.contains(h.id)) continue;
      if (!_scheduledHabitScopes.containsKey(h.id)) {
        final swept = await _cancelHabit(h.id);
        if (!swept) continue;
      }
      final scope = scopes[h.id]!;
      final blockedRegistryIds =
          blockedHabitIdsFromRegistry[h.id] ?? const <int>{};
      if (_scheduledHabitScopes[h.id] == scope) {
        if (await _habitStillPending(h)) {
          _recordHabitBudget(h);
          _rememberHabitReminderDisplay(h);
          await _replaceRegistryObject('habit', h.id, {
            ...blockedRegistryIds,
            ..._habitRegistryIds(h),
          }, acceptedIdSets: _habitAcceptedPendingIdSets(h));
          continue;
        }
        final cancelled = await _cancelHabit(h.id);
        if (!cancelled) continue;
        _scheduledHabitScopes.remove(h.id);
        _forgetReminderDisplay('habit', h.id);
        await registry.removeObject('habit', h.id);
      }
      if (!await _reserveHabitBudget(h)) {
        continue;
      }
      final scheduled = await _scheduleHabit(h);
      if (scheduled) {
        _rememberHabitReminderDisplay(h);
        _scheduledHabitScopes[h.id] = scope;
      } else {
        _releaseBudgetIds(_habitRegistryIds(h));
        _recordHabitScheduleFailure(h);
        scheduleFailures.add(_habitScheduleFailureSummary(h));
      }
      // 即便部分规则调度失败（scheduled == false，scope 不落库以便下次重排），
      // 也要把这条习惯当前“应注册”的全部派生 id 写入 registry：否则已成功的
      // 那几条派生通知会成为不在册的孤儿，禁用习惯时只按 registry 清理就漏掉它们。
      if (scheduled || _habitRegistryIds(h).isNotEmpty) {
        await _replaceRegistryObject('habit', h.id, {
          ...blockedRegistryIds,
          ..._habitRegistryIds(h),
        }, acceptedIdSets: _habitAcceptedPendingIdSets(h));
      }
    }
    if (scheduleFailures.isNotEmpty) {
      throw ReminderScheduleSyncException(
        List<String>.unmodifiable(scheduleFailures),
      );
    }
  }

  /// 习惯当前生效（已启用、非 off）的全部提醒规则，支持多提醒时间。
  List<ReminderRule> _enabledHabitRules(Habit habit) {
    final plan = _effectiveHabitPlan(habit);
    if (!plan.enabled) return const <ReminderRule>[];
    return [
      for (final rule in plan.rules)
        if (rule.enabled && rule.kind != ReminderKind.off) rule,
    ];
  }

  /// 习惯某条提醒规则对应的系统通知基础 id。
  ///
  /// 第一条规则沿用历史 `habit_<id>`，保证既有单条提醒幂等；其余规则按规则
  /// 自身 id 派生独立基础 id，从而支持“每天 8 杯水”这类多提醒时间习惯。
  int _habitRuleId(String habitId, ReminderRule rule, int index) {
    if (index == 0) return _idFor('habit_$habitId');
    return _avoidReservedNotificationId(_idFor('habit_$habitId#${rule.id}'));
  }

  Future<bool> _scheduleHabit(Habit habit) async {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return false;
    // 单条提醒沿用历史路径，避免触动既有幂等 / 取消语义与测试基线。
    if (rules.length == 1) {
      return _scheduleHabitRule(
        habit,
        rules.single,
        _idFor('habit_${habit.id}'),
        isPrimary: true,
      );
    }
    // 多条提醒逐条注册到独立 id；任一失败都视为整体未完成，交由上层重排兜底。
    var allOk = true;
    for (var i = 0; i < rules.length; i++) {
      final ok = await _scheduleHabitRule(
        habit,
        rules[i],
        _habitRuleId(habit.id, rules[i], i),
        isPrimary: i == 0,
      );
      allOk = allOk && ok;
    }
    return allOk;
  }

  Future<bool> _scheduleHabitRule(
    Habit habit,
    ReminderRule rule,
    int id, {
    required bool isPrimary,
  }) async {
    final rawHour = rule.hour;
    final rawMinute = rule.minute;
    if (rawHour == null || rawMinute == null) return false;
    final rawWeekdays = _habitWeekdays(habit, rule);
    final adjusted = _applyQuietHoursToRepeating(
      rawHour,
      rawMinute,
      rawWeekdays,
      rule.kind,
    );
    final hour = adjusted.hour;
    final minute = adjusted.minute;
    final weekdays = adjusted.weekdays;
    final payload = 'duoyi://habit/${habit.id}?confirm=1';
    final title = _habitTitle();
    final body = ReminderDeliveryCopy.habit(
      habit.name,
    ).render(locale: I18n.current, strings: _strings).body;

    switch (rule.kind) {
      case ReminderKind.push:
        return _scheduleHabitPush(
          habit,
          hour,
          minute,
          weekdays,
          explicitId: isPrimary ? null : id,
        );
      case ReminderKind.popup:
        try {
          await popup.scheduleRepeating(
            id: id,
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            weekdays: weekdays.isEmpty ? null : weekdays,
            payload: payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] habit popup dispatch failed for ${habit.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.alarm:
        final alarmIds = _alarmIssueIdsForRepeating(id, weekdays);
        try {
          await alarm.scheduleDailyFullScreen(
            id: id,
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            weekdays: weekdays.isEmpty ? null : weekdays,
            payload: payload,
            fullScreen: rule.fullScreen,
            vibrate: rule.vibrate,
            snoozeMinutes: rule.snoozeMinutes,
            repeatCount: rule.repeatCount,
          );
          return !_recordAlarmScheduleIssue(
            relatedId: habit.id,
            alarmIds: alarmIds,
          );
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm permission denied for ${habit.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
            relatedId: habit.id,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: habit.id,
              alarmIds: alarmIds,
            );
          }
          await _scheduleHabitPush(
            habit,
            hour,
            minute,
            weekdays,
            explicitId: isPrimary ? null : id,
          );
          _recordAlarmScheduleIssue(
            relatedId: habit.id,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm notification permission denied for ${habit.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
            relatedId: habit.id,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: habit.id,
              alarmIds: alarmIds,
            );
          }
          await _scheduleHabitPush(
            habit,
            hour,
            minute,
            weekdays,
            explicitId: isPrimary ? null : id,
          );
          _recordAlarmScheduleIssue(
            relatedId: habit.id,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm queue handoff failed for ${habit.id}: $e',
          );
          _recordAlarmScheduleIssue(
            relatedId: habit.id,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] habit alarm dispatch failed for ${habit.id}: $e\n$st',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
            relatedId: habit.id,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: habit.id,
              alarmIds: alarmIds,
            );
          }
          await _scheduleHabitPush(
            habit,
            hour,
            minute,
            weekdays,
            explicitId: isPrimary ? null : id,
          );
          _recordAlarmScheduleIssue(
            relatedId: habit.id,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        }
      case ReminderKind.email:
      case ReminderKind.off:
        return false;
    }
  }

  Future<bool> _scheduleHabitPush(
    Habit habit,
    int hour,
    int minute,
    List<int> weekdays, {
    int? explicitId,
  }) async {
    try {
      if (explicitId == null) {
        await notif.scheduleHabitReminder(
          habitId: habit.id,
          habitName: habit.name,
          hour: hour,
          minute: minute,
          weekdays: weekdays.isEmpty ? null : weekdays,
        );
      } else {
        // 多提醒时间的非首条规则走通用 push 出口，使用独立 id 以免互相覆盖。
        await notif.scheduleDaily(
          id: explicitId,
          title: _habitTitle(),
          body: ReminderDeliveryCopy.habit(
            habit.name,
          ).render(locale: I18n.current, strings: _strings).body,
          hour: hour,
          minute: minute,
          weekdays: weekdays.isEmpty ? null : weekdays,
          payload: 'duoyi://habit/${habit.id}?confirm=1',
        );
      }
      return true;
    } on NotificationPermissionDeniedException catch (fallbackError) {
      debugPrint(
        '[ReminderScheduler] habit notification permission denied for ${habit.id}: $fallbackError',
      );
      return false;
    } catch (fallbackError, st) {
      debugPrint(
        '[ReminderScheduler] habit notification dispatch failed for ${habit.id}: $fallbackError\n$st',
      );
      return false;
    }
  }

  Future<bool> _cancelHabit(String habitId) async {
    final id = _idFor('habit_$habitId');
    var ok = true;
    ok =
        await _cancelSafely(
          'habit notification:$habitId',
          () => notif.cancelHabitReminder(habitId),
        ) &&
        ok;
    ok =
        await _cancelSafely('habit alarm:$habitId', () => alarm.cancel(id)) &&
        ok;
    ok =
        await _cancelSafely('habit popup:$habitId', () => popup.cancel(id)) &&
        ok;
    ok = await _cancelEmail(id, 'habit:$habitId') && ok;
    if (ok) _releaseBudgetIds(<int>{id});
    return ok;
  }

  Future<bool> _scheduleAnniversaryPushFallback(Anniversary item) async {
    try {
      await notif.scheduleAnniversary(
        annId: item.id,
        title: item.title,
        whenDate: item.nextOccurrence,
        daysBefore: item.remindDaysBefore,
        hour: item.remindHour,
        minute: item.remindMinute,
      );
      return true;
    } on NotificationPermissionDeniedException catch (fallbackError) {
      debugPrint(
        '[ReminderScheduler] anniversary fallback notification permission denied for ${item.id}: $fallbackError',
      );
      return false;
    } catch (fallbackError, st) {
      debugPrint(
        '[ReminderScheduler] anniversary fallback notification dispatch failed for ${item.id}: $fallbackError\n$st',
      );
      return false;
    }
  }

  /// 按最新的纪念日 [items] 幂等地重新同步提醒。
  ///
  /// 纪念日提醒按 `reminderKind` 路由到通知、弹出框、闹钟或关闭；闹钟失败时
  /// 可以注册普通通知兜底防漏，但仍按闹钟注册失败向上反馈。
  Future<void> syncAnniversaries(
    Iterable<Anniversary> items, {
    ReminderReconciliationBatch? batch,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    final snapshot = items.toList(growable: false);
    Future<void> action() => _syncAnniversariesLocked(snapshot);
    if (batch != null) {
      if (!identical(batch, _activeBatch)) {
        throw StateError('Reminder reconciliation batch is not active');
      }
      if (batch.accountChangeGeneration != generation ||
          !_canRunAccountGeneration(generation)) {
        return;
      }
      await action();
      return;
    }
    await _runSerializedForAccountGeneration(generation, action);
  }

  Future<void> _syncAnniversariesLocked(Iterable<Anniversary> items) async {
    final wanted = <String, Anniversary>{};
    final scheduleFailures = <String>[];
    for (final a in items) {
      if (!a.remind) {
        await _cancelAnniversary(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      final nextDate = a.nextOccurrence;
      if (nextDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        await _cancelAnniversary(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      if (a.reminderKind == ReminderKind.off) {
        await _cancelAnniversary(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      wanted[a.id] = a;
    }
    final scopes = <String, String>{};
    for (final a in wanted.values) {
      final remindAt = rollAnniversaryRemindAtForward(
        _anniversaryReminderAt(a),
        DateTime.now(),
      );
      if (!remindAt.isAfter(DateTime.now())) continue;
      final effectiveAt = _applyQuietHoursToOnceTime(remindAt, a.reminderKind);
      scopes[a.id] = _anniversaryScope(a, effectiveAt);
      _rememberAnniversaryReminderDisplay(a, effectiveAt);
    }
    final blockedAnniversaryIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'anniversary',
      wantedIdsByObject: {
        for (final a in wanted.values) a.id: _anniversaryRegistryIds(a),
      },
    );

    final blockedAnniversaryIds = <String>{};
    for (final id in _scheduledAnniversaryScopes.keys.toList()) {
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledAnniversaryScopes[id] != nextScope) {
        final cancelled = await _cancelAnniversary(id);
        if (cancelled) {
          _scheduledAnniversaryScopes.remove(id);
          _forgetReminderDisplay('anniversary', id);
          await registry.removeObject('anniversary', id);
        } else {
          blockedAnniversaryIds.add(id);
        }
      }
    }

    for (final a in wanted.values) {
      if (blockedAnniversaryIds.contains(a.id)) continue;
      if (!_scheduledAnniversaryScopes.containsKey(a.id)) {
        final swept = await _cancelAnniversary(a.id);
        if (!swept) continue;
      }
      // 周年提醒时刻已过（打开 app 时当年的提醒时刻已经过去）时，
      // 推进到下一年同一时刻再注册，避免该周年被跳过后整年漏提醒。
      final remindAt = rollAnniversaryRemindAtForward(
        _anniversaryReminderAt(a),
        DateTime.now(),
      );
      if (!remindAt.isAfter(DateTime.now())) {
        continue;
      }
      final effectiveAt = _applyQuietHoursToOnceTime(remindAt, a.reminderKind);
      final scope = scopes[a.id]!;
      final blockedRegistryIds =
          blockedAnniversaryIdsFromRegistry[a.id] ?? const <int>{};
      if (_scheduledAnniversaryScopes[a.id] == scope) {
        if (await _anniversaryStillPending(a)) {
          _recordBudgetIds(
            _anniversaryRegistryIds(a),
            effectiveAt,
            objectType: 'anniversary',
            objectId: a.id,
          );
          _rememberAnniversaryReminderDisplay(a, effectiveAt);
          await _replaceRegistryObject(
            'anniversary',
            a.id,
            {...blockedRegistryIds, ..._anniversaryRegistryIds(a)},
            acceptedIdSets: _anniversaryAcceptedPendingIdSets(a),
          );
          continue;
        }
        final cancelled = await _cancelAnniversary(a.id);
        if (!cancelled) continue;
        _scheduledAnniversaryScopes.remove(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
      }

      if (!await _tryReserveBudgetIds(
        _anniversaryRegistryIds(a),
        effectiveAt,
        objectType: 'anniversary',
        objectId: a.id,
      )) {
        continue;
      }
      final scheduled = await _dispatchAnniversary(a, remindAt);
      if (scheduled) {
        _rememberAnniversaryReminderDisplay(a, effectiveAt);
        _scheduledAnniversaryScopes[a.id] = scope;
        await _replaceRegistryObject('anniversary', a.id, {
          ...blockedRegistryIds,
          ..._anniversaryRegistryIds(a),
        }, acceptedIdSets: _anniversaryAcceptedPendingIdSets(a));
      } else {
        _releaseBudgetIds(_anniversaryRegistryIds(a));
        _recordSingleScheduleFailure(
          title: '纪念日提醒注册失败',
          target: a.title,
          kind: a.reminderKind,
          scheduledTime: effectiveAt,
          relatedId: a.id,
        );
        scheduleFailures.add(
          _singleScheduleFailureSummary(
            title: '纪念日提醒注册失败',
            target: a.title,
            kind: a.reminderKind,
          ),
        );
      }
    }
    if (scheduleFailures.isNotEmpty) {
      throw ReminderScheduleSyncException(
        List<String>.unmodifiable(scheduleFailures),
      );
    }
  }

  /// 按最新的倒数日 [items] 幂等地同步到期提醒。
  Future<void> syncCountdowns(
    Iterable<CountdownItem> items, {
    ReminderReconciliationBatch? batch,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    final snapshot = items.toList(growable: false);
    Future<void> action() => _syncCountdownsLocked(snapshot);
    if (batch != null) {
      if (!identical(batch, _activeBatch)) {
        throw StateError('Reminder reconciliation batch is not active');
      }
      if (batch.accountChangeGeneration != generation ||
          !_canRunAccountGeneration(generation)) {
        return;
      }
      await action();
      return;
    }
    await _runSerializedForAccountGeneration(generation, action);
  }

  Future<void> _syncCountdownsLocked(Iterable<CountdownItem> items) async {
    final now = DateTime.now();
    final wanted = <String, CountdownItem>{};
    final scopes = <String, String>{};
    final scheduleFailures = <String>[];
    for (final item in items) {
      if (!item.remind || item.reminderKind == ReminderKind.off) {
        await _cancelCountdown(item.id);
        _forgetReminderDisplay('countdown', item.id);
        await registry.removeObject('countdown', item.id);
        continue;
      }
      final when = _countdownReminderAt(item);
      if (!when.isAfter(now)) {
        await _cancelCountdown(item.id);
        _forgetReminderDisplay('countdown', item.id);
        await registry.removeObject('countdown', item.id);
        continue;
      }
      wanted[item.id] = item;
      final adjustedWhen = _applyQuietHoursToOnceTime(when, item.reminderKind);
      scopes[item.id] = _countdownScope(item, adjustedWhen);
      _rememberCountdownReminderDisplay(item, adjustedWhen);
    }
    final blockedCountdownIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'countdown',
      wantedIdsByObject: {
        for (final item in wanted.values) item.id: _countdownRegistryIds(item),
      },
    );

    final blockedCountdownIds = <String>{};
    for (final id in _scheduledCountdownScopes.keys.toList()) {
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledCountdownScopes[id] != nextScope) {
        final cancelled = await _cancelCountdown(id);
        if (cancelled) {
          _scheduledCountdownScopes.remove(id);
          _forgetReminderDisplay('countdown', id);
          await registry.removeObject('countdown', id);
        } else {
          blockedCountdownIds.add(id);
        }
      }
    }

    final sortedCountdowns = wanted.values.toList(growable: false)
      ..sort(
        (a, b) => _applyQuietHoursToOnceTime(
          _countdownReminderAt(a),
          a.reminderKind,
        ).compareTo(
          _applyQuietHoursToOnceTime(_countdownReminderAt(b), b.reminderKind),
        ),
      );
    for (final item in sortedCountdowns) {
      if (blockedCountdownIds.contains(item.id)) continue;
      if (!_scheduledCountdownScopes.containsKey(item.id)) {
        final swept = await _cancelCountdown(item.id);
        if (!swept) continue;
      }
      final when = _applyQuietHoursToOnceTime(
        _countdownReminderAt(item),
        item.reminderKind,
      );
      final scope = scopes[item.id]!;
      final blockedRegistryIds =
          blockedCountdownIdsFromRegistry[item.id] ?? const <int>{};
      if (_scheduledCountdownScopes[item.id] == scope) {
        if (await _countdownStillPending(item)) {
          _recordBudgetIds(
            _countdownRegistryIds(item),
            when,
            objectType: 'countdown',
            objectId: item.id,
          );
          _rememberCountdownReminderDisplay(item, when);
          await _replaceRegistryObject(
            'countdown',
            item.id,
            {...blockedRegistryIds, ..._countdownRegistryIds(item)},
            acceptedIdSets: _countdownAcceptedPendingIdSets(item),
          );
          continue;
        }
        final cancelled = await _cancelCountdown(item.id);
        if (!cancelled) continue;
        _scheduledCountdownScopes.remove(item.id);
        _forgetReminderDisplay('countdown', item.id);
        await registry.removeObject('countdown', item.id);
      }
      if (!await _tryReserveBudgetIds(
        _countdownRegistryIds(item),
        when,
        objectType: 'countdown',
        objectId: item.id,
      )) {
        continue;
      }
      final copy =
          ReminderDeliveryCopy.countdown(item.title, item.daysRemaining).render(
            locale: item.reminderKind == ReminderKind.email
                ? AppLocale.zh
                : I18n.current,
            strings: _strings,
          );
      final scheduled = await _dispatch(
        kind: item.reminderKind,
        payload: _DispatchPayload(
          id: _idFor('countdown:${item.id}:due'),
          title: copy.title,
          body: copy.body,
          when: when,
          payload: 'duoyi://countdown/${item.id}',
          fullScreen: item.reminderKind == ReminderKind.alarm,
        ),
      );
      if (scheduled) {
        _rememberCountdownReminderDisplay(item, when);
        _scheduledCountdownScopes[item.id] = scope;
        await _replaceRegistryObject(
          'countdown',
          item.id,
          {...blockedRegistryIds, ..._countdownRegistryIds(item)},
          acceptedIdSets: _countdownAcceptedPendingIdSets(item),
        );
      } else {
        _releaseBudgetIds(_countdownRegistryIds(item));
        _recordSingleScheduleFailure(
          title: '倒数日提醒注册失败',
          target: item.title,
          kind: item.reminderKind,
          scheduledTime: when,
          relatedId: item.id,
        );
        scheduleFailures.add(
          _singleScheduleFailureSummary(
            title: '倒数日提醒注册失败',
            target: item.title,
            kind: item.reminderKind,
          ),
        );
      }
    }
    if (scheduleFailures.isNotEmpty) {
      throw ReminderScheduleSyncException(
        List<String>.unmodifiable(scheduleFailures),
      );
    }
  }

  /// Syncs upcoming class reminders for [courses] under [settings].
  Future<void> syncCourses(
    Iterable<CourseItem> courses, {
    required ScheduleSettings settings,
    ReminderReconciliationBatch? batch,
    DateTime? now,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    final snapshot = courses.toList(growable: false);
    Future<void> action() =>
        _syncCoursesLocked(snapshot, settings: settings, now: now);
    if (batch != null) {
      if (!identical(batch, _activeBatch)) {
        throw StateError('Reminder reconciliation batch is not active');
      }
      if (batch.accountChangeGeneration != generation ||
          !_canRunAccountGeneration(generation)) {
        return;
      }
      await action();
      return;
    }
    await _runSerializedForAccountGeneration(generation, action);
  }

  Future<void> _syncCoursesLocked(
    Iterable<CourseItem> courses, {
    required ScheduleSettings settings,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final wanted = <String, ({CourseItem course, DateTime remindAt, DateTime classStart})>{};
    final handledInactiveIds = <String>{};
    final scheduleFailures = <String>[];

    for (final course in courses) {
      if (course.reminderMinutes <= 0) {
        handledInactiveIds.add(course.id);
        if (await _cancelCourse(course.id)) {
          _scheduledCourseScopes.remove(course.id);
          _forgetReminderDisplay('course', course.id);
          await registry.removeObject('course', course.id);
        }
        continue;
      }
      final occurrence = _nextCourseOccurrence(course, settings, effectiveNow);
      if (occurrence == null) {
        handledInactiveIds.add(course.id);
        if (await _cancelCourse(course.id)) {
          _scheduledCourseScopes.remove(course.id);
          _forgetReminderDisplay('course', course.id);
          await registry.removeObject('course', course.id);
        }
        continue;
      }
      final remindAt = _applyQuietHoursToOnceTime(
        occurrence.remindAt,
        ReminderKind.push,
      );
      if (!remindAt.isAfter(effectiveNow)) {
        handledInactiveIds.add(course.id);
        if (await _cancelCourse(course.id)) {
          _scheduledCourseScopes.remove(course.id);
          _forgetReminderDisplay('course', course.id);
          await registry.removeObject('course', course.id);
        }
        continue;
      }
      wanted[course.id] = (
        course: course,
        remindAt: remindAt,
        classStart: occurrence.classStart,
      );
    }

    final quietHoursTag = _quietHours.enabled ? '|qh:${_quietHours.digest}' : '';
    final scopes = <String, String>{};
    for (final entry in wanted.values) {
      final id = _idFor('course:${entry.course.id}:next');
      scopes[entry.course.id] =
          '$id|${entry.remindAt.millisecondsSinceEpoch}|${entry.course.name}|${entry.course.location}|${entry.course.reminderMinutes}$quietHoursTag';
      _rememberCourseReminderDisplay(entry.course, entry.remindAt);
    }

    final blockedFromRegistry = await _sweepSingleRegistry(
      objectType: 'course',
      wantedIdsByObject: {
        for (final course in wanted.values.map((e) => e.course))
          course.id: <int>{_idFor('course:${course.id}:next')},
      },
    );

    final blockedIds = <String>{};
    for (final id in _scheduledCourseScopes.keys.toList()) {
      if (handledInactiveIds.contains(id)) continue;
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledCourseScopes[id] != nextScope) {
        if (await _cancelCourse(id)) {
          _scheduledCourseScopes.remove(id);
          _forgetReminderDisplay('course', id);
          await registry.removeObject('course', id);
        } else {
          blockedIds.add(id);
        }
      }
    }

    final ordered = wanted.values.toList(growable: false)
      ..sort((a, b) => a.remindAt.compareTo(b.remindAt));
    for (final entry in ordered) {
      final course = entry.course;
      if (blockedIds.contains(course.id)) continue;
      final id = _idFor('course:${course.id}:next');
      if (!_scheduledCourseScopes.containsKey(course.id)) {
        final swept = await _cancelCourse(course.id);
        if (!swept) continue;
      }
      final scope = scopes[course.id]!;
      final blockedRegistryIds =
          blockedFromRegistry[course.id] ?? const <int>{};
      if (_scheduledCourseScopes[course.id] == scope) {
        if (await _sinkStillPending(
          label: 'course:${course.id}',
          kind: ReminderKind.push,
          expected: <int>{id},
          relatedId: course.id,
        )) {
          _recordBudgetIds(
            <int>{id},
            entry.remindAt,
            objectType: 'course',
            objectId: course.id,
          );
          _rememberCourseReminderDisplay(course, entry.remindAt);
          await _replaceRegistryObject('course', course.id, {
            ...blockedRegistryIds,
            id,
          });
          continue;
        }
        final cancelled = await _cancelCourse(course.id);
        if (!cancelled) continue;
        _scheduledCourseScopes.remove(course.id);
        _forgetReminderDisplay('course', course.id);
        await registry.removeObject('course', course.id);
      }

      if (!await _tryReserveBudgetIds(
        <int>{id},
        entry.remindAt,
        objectType: 'course',
        objectId: course.id,
      )) {
        continue;
      }

      final title = I18n.current == AppLocale.en
          ? 'Course · ${course.name}'
          : '课程提醒 · ${course.name}';
      final timeText = _timeLabel(
        entry.classStart.hour,
        entry.classStart.minute,
      );
      final loc = course.location.trim();
      final body = loc.isNotEmpty ? '$timeText · $loc' : '${course.name} · $timeText';
      final scheduled = await _dispatch(
        kind: ReminderKind.push,
        payload: _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: entry.remindAt,
          payload: 'duoyi://course/${course.id}',
        ),
      );
      if (scheduled) {
        _rememberCourseReminderDisplay(course, entry.remindAt);
        _scheduledCourseScopes[course.id] = scope;
        await _replaceRegistryObject('course', course.id, {
          ...blockedRegistryIds,
          id,
        });
      } else {
        _releaseBudgetIds(<int>{id});
        _recordSingleScheduleFailure(
          title: '课程提醒注册失败',
          target: course.name,
          kind: ReminderKind.push,
          scheduledTime: entry.remindAt,
          relatedId: course.id,
        );
        scheduleFailures.add(
          _singleScheduleFailureSummary(
            title: '课程提醒注册失败',
            target: course.name,
            kind: ReminderKind.push,
          ),
        );
      }
    }
    if (scheduleFailures.isNotEmpty) {
      throw ReminderScheduleSyncException(
        List<String>.unmodifiable(scheduleFailures),
      );
    }
  }

  /// Syncs upcoming reminders for local [CalendarEvent]s.
  Future<void> syncCalendarEvents(
    Iterable<CalendarEvent> events, {
    ReminderReconciliationBatch? batch,
    DateTime? now,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    final snapshot = events.toList(growable: false);
    Future<void> action() => _syncCalendarEventsLocked(snapshot, now: now);
    if (batch != null) {
      if (!identical(batch, _activeBatch)) {
        throw StateError('Reminder reconciliation batch is not active');
      }
      if (batch.accountChangeGeneration != generation ||
          !_canRunAccountGeneration(generation)) {
        return;
      }
      await action();
      return;
    }
    await _runSerializedForAccountGeneration(generation, action);
  }

  Future<void> _syncCalendarEventsLocked(
    Iterable<CalendarEvent> events, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final wanted = <String, ({CalendarEvent event, DateTime remindAt})>{};
    final handledInactiveIds = <String>{};
    final scheduleFailures = <String>[];

    for (final event in events) {
      final mins = event.reminderMinutes;
      if (mins == null || mins < 0) {
        handledInactiveIds.add(event.id);
        if (await _cancelCalendarEvent(event.id)) {
          _scheduledCalendarEventScopes.remove(event.id);
          _forgetReminderDisplay('calendar_event', event.id);
          await registry.removeObject('calendar_event', event.id);
        }
        continue;
      }
      final eventStart = _calendarEventStartAt(event);
      final rawRemindAt = eventStart.subtract(Duration(minutes: mins));
      final remindAt = _applyQuietHoursToOnceTime(
        rawRemindAt,
        ReminderKind.push,
      );
      if (!remindAt.isAfter(effectiveNow)) {
        handledInactiveIds.add(event.id);
        if (await _cancelCalendarEvent(event.id)) {
          _scheduledCalendarEventScopes.remove(event.id);
          _forgetReminderDisplay('calendar_event', event.id);
          await registry.removeObject('calendar_event', event.id);
        }
        continue;
      }
      wanted[event.id] = (event: event, remindAt: remindAt);
    }

    final quietHoursTag = _quietHours.enabled ? '|qh:${_quietHours.digest}' : '';
    final scopes = <String, String>{};
    for (final entry in wanted.values) {
      final event = entry.event;
      final id = _idFor('calendar_event:${event.id}');
      final detail = (event.note ?? event.subtitle ?? '').trim();
      scopes[event.id] =
          '$id|${entry.remindAt.millisecondsSinceEpoch}|${event.title}|$detail|${event.reminderMinutes}$quietHoursTag';
      _rememberCalendarEventReminderDisplay(event, entry.remindAt);
    }

    final blockedFromRegistry = await _sweepSingleRegistry(
      objectType: 'calendar_event',
      wantedIdsByObject: {
        for (final entry in wanted.values)
          entry.event.id: <int>{_idFor('calendar_event:${entry.event.id}')},
      },
    );

    final blockedIds = <String>{};
    for (final id in _scheduledCalendarEventScopes.keys.toList()) {
      if (handledInactiveIds.contains(id)) continue;
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledCalendarEventScopes[id] != nextScope) {
        if (await _cancelCalendarEvent(id)) {
          _scheduledCalendarEventScopes.remove(id);
          _forgetReminderDisplay('calendar_event', id);
          await registry.removeObject('calendar_event', id);
        } else {
          blockedIds.add(id);
        }
      }
    }

    final ordered = wanted.values.toList(growable: false)
      ..sort((a, b) => a.remindAt.compareTo(b.remindAt));
    for (final entry in ordered) {
      final event = entry.event;
      if (blockedIds.contains(event.id)) continue;
      final id = _idFor('calendar_event:${event.id}');
      if (!_scheduledCalendarEventScopes.containsKey(event.id)) {
        final swept = await _cancelCalendarEvent(event.id);
        if (!swept) continue;
      }
      final scope = scopes[event.id]!;
      final blockedRegistryIds =
          blockedFromRegistry[event.id] ?? const <int>{};
      if (_scheduledCalendarEventScopes[event.id] == scope) {
        if (await _sinkStillPending(
          label: 'calendar_event:${event.id}',
          kind: ReminderKind.push,
          expected: <int>{id},
          relatedId: event.id,
        )) {
          _recordBudgetIds(
            <int>{id},
            entry.remindAt,
            objectType: 'calendar_event',
            objectId: event.id,
          );
          _rememberCalendarEventReminderDisplay(event, entry.remindAt);
          await _replaceRegistryObject('calendar_event', event.id, {
            ...blockedRegistryIds,
            id,
          });
          continue;
        }
        final cancelled = await _cancelCalendarEvent(event.id);
        if (!cancelled) continue;
        _scheduledCalendarEventScopes.remove(event.id);
        _forgetReminderDisplay('calendar_event', event.id);
        await registry.removeObject('calendar_event', event.id);
      }

      if (!await _tryReserveBudgetIds(
        <int>{id},
        entry.remindAt,
        objectType: 'calendar_event',
        objectId: event.id,
      )) {
        continue;
      }

      final eventStart = _calendarEventStartAt(event);
      final dateParam =
          '${eventStart.year}-${eventStart.month.toString().padLeft(2, '0')}-${eventStart.day.toString().padLeft(2, '0')}';
      final title = I18n.current == AppLocale.en
          ? 'Schedule · ${event.title}'
          : '日程提醒 · ${event.title}';
      final noteText = event.note?.trim() ?? '';
      final subtitleText = event.subtitle?.trim() ?? '';
      final body = noteText.isNotEmpty
          ? noteText
          : subtitleText.isNotEmpty
          ? subtitleText
          : _timeLabel(eventStart.hour, eventStart.minute);
      final scheduled = await _dispatch(
        kind: ReminderKind.push,
        payload: _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: entry.remindAt,
          payload:
              'duoyi://calendar?date=$dateParam&eventId=${Uri.encodeComponent(event.id)}',
        ),
      );
      if (scheduled) {
        _rememberCalendarEventReminderDisplay(event, entry.remindAt);
        _scheduledCalendarEventScopes[event.id] = scope;
        await _replaceRegistryObject('calendar_event', event.id, {
          ...blockedRegistryIds,
          id,
        });
      } else {
        _releaseBudgetIds(<int>{id});
        _recordSingleScheduleFailure(
          title: '日程提醒注册失败',
          target: event.title,
          kind: ReminderKind.push,
          scheduledTime: entry.remindAt,
          relatedId: event.id,
        );
        scheduleFailures.add(
          _singleScheduleFailureSummary(
            title: '日程提醒注册失败',
            target: event.title,
            kind: ReminderKind.push,
          ),
        );
      }
    }
    if (scheduleFailures.isNotEmpty) {
      throw ReminderScheduleSyncException(
        List<String>.unmodifiable(scheduleFailures),
      );
    }
  }

  /// 按最新的 [goals] 幂等地重新同步目标提醒（支持多 rule）。
  Future<void> syncGoals(
    Iterable<GoalItem> goals, {
    ReminderReconciliationBatch? batch,
  }) async {
    final generation = _accountChangeGeneration;
    if (!_canRunAccountGeneration(generation)) return;
    final snapshot = goals.toList(growable: false);
    Future<void> action() => _syncGoalsLocked(snapshot);
    if (batch != null) {
      if (!identical(batch, _activeBatch)) {
        throw StateError('Reminder reconciliation batch is not active');
      }
      if (batch.accountChangeGeneration != generation ||
          !_canRunAccountGeneration(generation)) {
        return;
      }
      await action();
      return;
    }
    await _runSerializedForAccountGeneration(generation, action);
  }

  Future<void> _syncGoalsLocked(Iterable<GoalItem> goals) async {
    final wanted = <String, Map<String, _ResolvedRule>>{};
    for (final g in goals) {
      if (g.status != GoalStatus.active) {
        await _cancelCurrentGoalPlan(g);
        continue;
      }
      final resolved = _resolveGoalRules(g);
      if (resolved.isEmpty) {
        await _cancelCurrentGoalPlan(g);
        continue;
      }
      wanted[g.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    final blockedRegistryIds = await _sweepRuleRegistry(
      objectType: 'goal',
      wanted: wanted,
    );
    await _syncRuleObjects(
      objectType: 'goal',
      wanted: wanted,
      scheduled: _scheduledGoalRules,
      cancelLegacy: _cancelGoalLegacy,
      blockedRegistryIdsByObject: blockedRegistryIds,
    );
  }

  /// 时区变化、权限变化、应用冷启动时整轮重放（R4.7）。
  Future<void> resyncAll({
    required Iterable<TodoItem> todos,
    required Iterable<Habit> habits,
    required Iterable<Anniversary> annis,
    required Iterable<GoalItem> goals,
    Iterable<CountdownItem> countdowns = const <CountdownItem>[],
    Iterable<CourseItem>? courses,
    ScheduleSettings? courseSettings,
    Iterable<CalendarEvent>? calendarEvents,
  }) async {
    final todoSnapshot = todos.toList(growable: false);
    final habitSnapshot = habits.toList(growable: false);
    final anniversarySnapshot = annis.toList(growable: false);
    final goalSnapshot = goals.toList(growable: false);
    final countdownSnapshot = countdowns.toList(growable: false);
    final courseSnapshot = courses?.toList(growable: false);
    final calendarSnapshot = calendarEvents?.toList(growable: false);
    await runReconciliationBatch(
      (_) => _resyncAllLocked(
        todos: todoSnapshot,
        habits: habitSnapshot,
        annis: anniversarySnapshot,
        goals: goalSnapshot,
        countdowns: countdownSnapshot,
        courses: courseSnapshot,
        courseSettings: courseSettings,
        calendarEvents: calendarSnapshot,
      ),
    );
  }

  Future<void> _resyncAllLocked({
    required Iterable<TodoItem> todos,
    required Iterable<Habit> habits,
    required Iterable<Anniversary> annis,
    required Iterable<GoalItem> goals,
    required Iterable<CountdownItem> countdowns,
    Iterable<CourseItem>? courses,
    ScheduleSettings? courseSettings,
    Iterable<CalendarEvent>? calendarEvents,
  }) async {
    for (final id in _scheduledTodoRules.keys.toList()) {
      final rulesCancelled = await _cancelRuleObjects(
        'todo',
        id,
        _scheduledTodoRules[id]!.keys,
      );
      final legacyCancelled = await _cancelTodoLegacy(id);
      if (rulesCancelled && legacyCancelled) {
        _scheduledTodoRules.remove(id);
        await registry.removeObject('todo', id);
      }
    }
    for (final id in _scheduledGoalRules.keys.toList()) {
      final rulesCancelled = await _cancelRuleObjects(
        'goal',
        id,
        _scheduledGoalRules[id]!.keys,
      );
      final legacyCancelled = await _cancelGoalLegacy(id);
      if (rulesCancelled && legacyCancelled) {
        _scheduledGoalRules.remove(id);
        await registry.removeObject('goal', id);
      }
    }
    for (final id in _scheduledHabitScopes.keys.toList()) {
      if (await _cancelHabit(id)) {
        _scheduledHabitScopes.remove(id);
        await registry.removeObject('habit', id);
      }
    }
    for (final id in _scheduledAnniversaryScopes.keys.toList()) {
      if (await _cancelAnniversary(id)) {
        _scheduledAnniversaryScopes.remove(id);
        await registry.removeObject('anniversary', id);
      }
    }
    for (final id in _scheduledCountdownScopes.keys.toList()) {
      if (await _cancelCountdown(id)) {
        _scheduledCountdownScopes.remove(id);
        await registry.removeObject('countdown', id);
      }
    }
    if (courses != null && courseSettings != null) {
      for (final id in _scheduledCourseScopes.keys.toList()) {
        if (await _cancelCourse(id)) {
          _scheduledCourseScopes.remove(id);
          await registry.removeObject('course', id);
        }
      }
    }
    if (calendarEvents != null) {
      for (final id in _scheduledCalendarEventScopes.keys.toList()) {
        if (await _cancelCalendarEvent(id)) {
          _scheduledCalendarEventScopes.remove(id);
          await registry.removeObject('calendar_event', id);
        }
      }
    }

    await _syncTodosLocked(todos, allowJustMissedOneShotReminders: false);
    await _syncHabitsLocked(habits);
    await _syncAnniversariesLocked(annis);
    await _syncGoalsLocked(goals);
    await _syncCountdownsLocked(countdowns);
    if (courses != null && courseSettings != null) {
      await _syncCoursesLocked(courses, settings: courseSettings);
    }
    if (calendarEvents != null) {
      await _syncCalendarEventsLocked(calendarEvents);
    }
  }

  Future<T> _runSerialized<T>(Future<T> Function() action) {
    final run = _syncQueue.then((_) => action());
    _syncQueue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  // -------------------------------------------------------------------------
  // 内部：通道路由
  // -------------------------------------------------------------------------

  /// 按 [kind] 路由到 push、alarm 或 email。权限不足时记录并返回 false，
  /// 避免 ChangeNotifier 监听回调里出现未处理异步异常。
  void _recordDispatchIssue(
    _DispatchPayload payload,
    Object error, {
    required bool blocking,
    ReminderSyncIssueNotice? notice,
  }) {
    final relatedId =
        _relatedIdFromPayload(payload.payload) ?? payload.id.toString();
    if (blocking && payload.payload?.startsWith('duoyi://todo/') == true) {
      final typed = error is NotificationScheduleUnavailableException
          ? error
          : null;
      _todoScheduleFailures[relatedId] = ReminderSyncIssueEntry(
        error.toString(),
        copy: typed?.copy,
        includeTitle: true,
        rawTitle: typed?.title ?? '',
        rawMessage: typed?.message ?? '',
        notice: notice,
      );
    }
    // 规则重排统一写入既有诊断；此处只保留单待办的精确失败结果。
  }

  void _recordTodoRuleDispatchFailure(_ResolvedRule rule) {
    if (rule.objectType != 'todo') return;
    _todoScheduleFailures.putIfAbsent(
      rule.objectId,
      () => const ReminderSyncIssueEntry(
        '提醒调度器未能确认规则已注册到系统',
        notice: ReminderSyncIssueNotice.registrationUnconfirmed,
      ),
    );
  }

  String? _relatedIdFromPayload(String? payload) {
    final uri = payload == null ? null : Uri.tryParse(payload);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    return uri.pathSegments.first == 'todo' && uri.pathSegments.length > 1
        ? uri.pathSegments[1]
        : uri.pathSegments.first;
  }

  Future<bool> _schedulePushOnceWithResult({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    final notification = notif;
    final resultSink = notification is ReminderNotificationScheduleResultSink
        ? notification as ReminderNotificationScheduleResultSink
        : null;
    if (resultSink != null) {
      final scheduled = await resultSink.scheduleOnceWithResult(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      );
      if (!scheduled) {
        _recordDispatchIssue(
          _DispatchPayload(
            id: id,
            title: title,
            body: body,
            when: when,
            payload: payload,
          ),
          StateError('系统通知服务返回未注册'),
          blocking: true,
          notice: ReminderSyncIssueNotice.pushNotRegistered,
        );
      }
      return scheduled;
    }
    try {
      await notification.scheduleOnce(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      );
      return true;
    } on NotificationPermissionDeniedException catch (error) {
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint(
        '[ReminderScheduler] notification scheduling failed: $error\n$stackTrace',
      );
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    }
  }

  Future<bool> _schedulePushDailyWithResult({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    final notification = notif;
    final resultSink = notification is ReminderNotificationScheduleResultSink
        ? notification as ReminderNotificationScheduleResultSink
        : null;
    if (resultSink != null) {
      final scheduled = await resultSink.scheduleDailyWithResult(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: payload,
      );
      if (!scheduled) {
        _recordDispatchIssue(
          _DispatchPayload(
            id: id,
            title: title,
            body: body,
            when: DateTime.now(),
            payload: payload,
          ),
          StateError('系统重复通知服务返回未注册'),
          blocking: true,
          notice: ReminderSyncIssueNotice.repeatingPushNotRegistered,
        );
      }
      return scheduled;
    }
    try {
      await notification.scheduleDaily(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: payload,
      );
      return true;
    } on NotificationPermissionDeniedException catch (error) {
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: DateTime.now(),
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint(
        '[ReminderScheduler] daily notification scheduling failed: $error\n$stackTrace',
      );
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: DateTime.now(),
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    }
  }

  Future<bool> _dispatch({
    required ReminderKind kind,
    required _DispatchPayload payload,
  }) async {
    final effectiveKind =
        (kind == ReminderKind.alarm &&
            _quietHours.enabled &&
            !_quietHours.allowAlarms &&
            !_quietHours.deferUntilEnd &&
            _quietHours.isWithinQuietHours(payload.when))
        ? ReminderKind.push
        : kind;
    switch (effectiveKind) {
      case ReminderKind.popup:
        try {
          await popup.scheduleOnce(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] popup dispatch failed for ${payload.id}: $e\n$st',
          );
          _recordDispatchIssue(payload, e, blocking: true);
          return false;
        }
      case ReminderKind.push:
        try {
          return await _schedulePushOnceWithResult(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] push notification permission denied for ${payload.id}: $e',
          );
          _recordDispatchIssue(payload, e, blocking: true);
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] push notification dispatch failed for ${payload.id}: $e\n$st',
          );
          _recordDispatchIssue(payload, e, blocking: true);
          return false;
        }
      case ReminderKind.alarm:
        final relatedId = _issueRelatedIdForPayload(payload);
        final alarmIds = <int>{payload.id};
        try {
          await alarm.scheduleFullScreen(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
            fullScreen: payload.fullScreen,
            vibrate: payload.vibrate,
            snoozeMinutes: payload.snoozeMinutes,
            repeatCount: payload.repeatCount,
          );
          return !_recordAlarmScheduleIssue(
            relatedId: relatedId,
            scheduledTime: payload.when,
            alarmIds: alarmIds,
          );
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm permission denied for ${payload.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
            relatedId: relatedId,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              alarmIds: alarmIds,
            );
          }
          try {
            await notif.scheduleOnce(
              id: payload.id,
              title: payload.title,
              body: payload.body,
              when: payload.when,
              payload: _fallbackPayload(payload.payload),
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification permission denied for ${payload.id}: $fallbackError',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification dispatch failed for ${payload.id}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${payload.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
            relatedId: relatedId,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              alarmIds: alarmIds,
            );
          }
          _recordAlarmScheduleIssue(
            relatedId: relatedId,
            scheduledTime: payload.when,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm queue handoff failed for ${payload.id}: $e',
          );
          _recordAlarmScheduleIssue(
            relatedId: relatedId,
            scheduledTime: payload.when,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] alarm dispatch failed for ${payload.id}: $e\n$st',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
            relatedId: relatedId,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              alarmIds: alarmIds,
            );
          }
          try {
            await notif.scheduleOnce(
              id: payload.id,
              title: payload.title,
              body: payload.body,
              when: payload.when,
              payload: _fallbackPayload(payload.payload),
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification permission denied for ${payload.id}: $fallbackError',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification dispatch failed for ${payload.id}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              scheduledTime: payload.when,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          }
        }
      case ReminderKind.email:
        try {
          await email.scheduleOnce(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] email dispatch failed for ${payload.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  Future<bool> _dispatchRepeating(_ResolvedRule rule) async {
    final effectiveKind =
        (rule.kind == ReminderKind.alarm &&
            _quietHours.enabled &&
            !_quietHours.allowAlarms &&
            !_quietHours.deferUntilEnd &&
            rule.hour != null &&
            rule.minute != null &&
            _quietHours.isMinutesInQuietWindow(rule.hour! * 60 + rule.minute!))
        ? ReminderKind.push
        : rule.kind;
    switch (effectiveKind) {
      case ReminderKind.popup:
        try {
          await popup.scheduleRepeating(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating popup dispatch failed for ${rule.key}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.push:
        try {
          return await _schedulePushDailyWithResult(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] repeating push permission denied for ${rule.key}: $e',
          );
          return false;
        }
      case ReminderKind.alarm:
        final relatedId = rule.objectId;
        final alarmIds = _alarmIssueIdsForRule(rule);
        try {
          await alarm.scheduleDailyFullScreen(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
            fullScreen: rule.fullScreen,
            vibrate: rule.vibrate,
            snoozeMinutes: rule.snoozeMinutes,
            repeatCount: rule.repeatCount,
          );
          return !_recordAlarmScheduleIssue(
            relatedId: relatedId,
            alarmIds: alarmIds,
          );
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm permission denied for ${rule.key}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
            relatedId: relatedId,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: relatedId,
              alarmIds: alarmIds,
            );
          }
          try {
            await notif.scheduleDaily(
              id: _idFor(rule.key),
              title: rule.title,
              body: rule.body,
              hour: rule.hour!,
              minute: rule.minute!,
              weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
              payload: _fallbackPayload(rule.payload),
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback permission denied for ${rule.key}: $fallbackError',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback dispatch failed for ${rule.key}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${rule.key}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
            relatedId: relatedId,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: relatedId,
              alarmIds: alarmIds,
            );
          }
          _recordAlarmScheduleIssue(
            relatedId: relatedId,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] repeating alarm queue handoff failed for ${rule.key}: $e',
          );
          _recordAlarmScheduleIssue(
            relatedId: relatedId,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating alarm dispatch failed for ${rule.key}: $e\n$st',
          );
          final id = _idFor(rule.key);
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
            relatedId: relatedId,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: relatedId,
              alarmIds: alarmIds,
            );
          }
          try {
            await notif.scheduleDaily(
              id: id,
              title: rule.title,
              body: rule.body,
              hour: rule.hour!,
              minute: rule.minute!,
              weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
              payload: _fallbackPayload(rule.payload),
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback permission denied for ${rule.key}: $fallbackError',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback dispatch failed for ${rule.key}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(
              relatedId: relatedId,
              blocking: true,
              alarmIds: alarmIds,
            );
            return false;
          }
        }
      case ReminderKind.email:
        try {
          await email.scheduleRepeating(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating email dispatch failed for ${rule.key}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  // -------------------------------------------------------------------------
  // 内部：取消
  // -------------------------------------------------------------------------

  Future<bool> _cancelTodo(String todoId, {bool blocking = true}) async {
    // 双通道清理：即便本地记录的是 push，用户从 alarm 切过来时也能扫到尾巴。
    var ok = true;
    ok =
        await _cancelSafely(
          'todo notification legacy:$todoId',
          () => notif.cancelTodoReminder(todoId),
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'todo alarm legacy:$todoId',
          () => alarm.cancel(_idFor('todo_$todoId')),
          blocking: blocking,
        ) &&
        ok;
    return ok;
  }

  Future<bool> _cancelGoal(String goalId, {bool blocking = true}) async {
    final id = _idFor('goal_$goalId');
    var ok = true;
    ok =
        await _cancelSafely(
          'goal notification:$goalId',
          () => notif.cancel(id),
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'goal alarm:$goalId',
          () => alarm.cancel(id),
          blocking: blocking,
        ) &&
        ok;
    return ok;
  }

  Future<bool> _cancelTodoLegacy(String todoId, {bool blocking = true}) =>
      _cancelTodo(todoId, blocking: blocking);

  Future<bool> _cancelGoalLegacy(String goalId, {bool blocking = true}) =>
      _cancelGoal(goalId, blocking: blocking);

  Future<bool> _cancelAnniversary(String annId) async {
    var ok = true;
    ok =
        await _cancelSafely(
          'anniversary notification:$annId',
          () => notif.cancelAnniversary(annId),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'anniversary alarm:$annId',
          () => alarm.cancel(_idFor('anni_alarm_$annId')),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'anniversary popup:$annId',
          () => popup.cancel(_idFor('anni_$annId')),
        ) &&
        ok;
    ok = await _cancelEmail(_idFor('anni_$annId'), 'anniversary:$annId') && ok;
    if (ok) {
      _releaseBudgetIds(<int>{
        _idFor('anni_$annId'),
        _idFor('anni_alarm_$annId'),
      });
    }
    return ok;
  }

  Future<bool> _cancelCountdown(String countdownId) async {
    final id = _idFor('countdown:$countdownId:due');
    var ok = true;
    ok =
        await _cancelSafely(
          'countdown notification:$countdownId',
          () => notif.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'countdown alarm:$countdownId',
          () => alarm.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'countdown popup:$countdownId',
          () => popup.cancel(id),
        ) &&
        ok;
    ok = await _cancelEmail(id, 'countdown:$countdownId') && ok;
    if (ok) _releaseBudgetIds(<int>{id});
    return ok;
  }

  Future<bool> _cancelCourse(String courseId) async {
    final id = _idFor('course:$courseId:next');
    var ok = true;
    ok =
        await _cancelSafely(
          'course notification:$courseId',
          () => notif.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'course alarm:$courseId',
          () => alarm.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'course popup:$courseId',
          () => popup.cancel(id),
        ) &&
        ok;
    if (ok) _releaseBudgetIds(<int>{id});
    return ok;
  }

  Future<bool> _cancelCalendarEvent(String eventId) async {
    final id = _idFor('calendar_event:$eventId');
    var ok = true;
    ok =
        await _cancelSafely(
          'calendar_event notification:$eventId',
          () => notif.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'calendar_event alarm:$eventId',
          () => alarm.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'calendar_event popup:$eventId',
          () => popup.cancel(id),
        ) &&
        ok;
    if (ok) _releaseBudgetIds(<int>{id});
    return ok;
  }

  Future<bool> _cancelRuleObjects(
    String objectType,
    String objectId,
    Iterable<String> ruleIds, {
    bool blocking = true,
  }) async {
    var ok = true;
    for (final ruleId in ruleIds) {
      ok =
          await _cancelRule(objectType, objectId, ruleId, blocking: blocking) &&
          ok;
    }
    return ok;
  }

  Future<Map<String, Set<int>>> _sweepRuleRegistry({
    required String objectType,
    required Map<String, Map<String, _ResolvedRule>> wanted,
  }) async {
    final persisted = await registry.idsByObject(objectType);
    final blocked = <String, Set<int>>{};
    for (final entry in persisted.entries) {
      final objectId = entry.key;
      final wantedRules = wanted[objectId] ?? const <String, _ResolvedRule>{};
      final wantedIds = {
        for (final rule in wantedRules.values) ..._registryIdsForRule(rule),
      };
      final staleIds = entry.value.difference(wantedIds);
      if (staleIds.isEmpty) continue;
      final cancelled = await _cancelIds(
        objectType,
        objectId,
        staleIds,
        blocking: false,
      );
      if (cancelled) {
        if (wantedIds.isEmpty) {
          await registry.removeObject(objectType, objectId);
        } else {
          await _replaceRegistryObject(
            objectType,
            objectId,
            wantedIds,
            resolvedRules: wantedRules.values,
            acceptedIdSets: _acceptedPendingIdSetsForResolvedRules(
              wantedRules.values,
            ),
          );
        }
      } else {
        blocked[objectId] = staleIds;
      }
    }
    return blocked;
  }

  Future<Map<String, Set<int>>> _sweepSingleRegistry({
    required String objectType,
    required Map<String, Set<int>> wantedIdsByObject,
  }) async {
    final persisted = await registry.idsByObject(objectType);
    final blocked = <String, Set<int>>{};
    for (final entry in persisted.entries) {
      final objectId = entry.key;
      final wantedIds = wantedIdsByObject[objectId] ?? const <int>{};
      final staleIds = entry.value.difference(wantedIds);
      if (staleIds.isEmpty) continue;
      final cancelled = await _cancelIds(
        objectType,
        objectId,
        staleIds,
        blocking: false,
      );
      if (cancelled) {
        if (wantedIds.isEmpty) {
          await registry.removeObject(objectType, objectId);
        } else {
          await _replaceRegistryObject(objectType, objectId, wantedIds);
        }
      } else {
        blocked[objectId] = staleIds;
      }
    }
    return blocked;
  }

  Future<bool> _cancelCurrentTodoPlan(TodoItem todo) async {
    final plan = _effectiveTodoPlan(todo);
    var ok = await _cancelTodoLegacy(todo.id);
    if (plan.rules.isNotEmpty) {
      ok =
          await _cancelRuleObjects(
            'todo',
            todo.id,
            plan.rules.map((rule) => rule.id),
          ) &&
          ok;
    }
    if (ok) await registry.removeObject('todo', todo.id);
    return ok;
  }

  Future<bool> _cancelCurrentGoalPlan(GoalItem goal) async {
    final plan = goal.reminderPlan.enabled && goal.reminderPlan.rules.isNotEmpty
        ? goal.reminderPlan
        : goal.reminder.enabled
        ? ReminderPlan.fromLegacy(goal.reminder)
        : const ReminderPlan.disabled();
    var ok = await _cancelGoalLegacy(goal.id);
    if (plan.rules.isNotEmpty) {
      ok =
          await _cancelRuleObjects(
            'goal',
            goal.id,
            plan.rules.map((rule) => rule.id),
          ) &&
          ok;
    }
    if (ok) await registry.removeObject('goal', goal.id);
    return ok;
  }

  Future<bool> _cancelIds(
    String objectType,
    String objectId,
    Iterable<int> ids, {
    bool blocking = true,
  }) async {
    final uniqueIds = ids.where((id) => id != 0).toSet();
    var ok = true;
    for (final id in uniqueIds) {
      ok =
          await _cancelSafely(
            '$objectType notification registry:$objectId ($id)',
            () => notif.cancel(id),
            blocking: blocking,
          ) &&
          ok;
      ok =
          await _cancelSafely(
            '$objectType alarm registry:$objectId ($id)',
            () => alarm.cancel(id),
            blocking: blocking,
          ) &&
          ok;
      ok =
          await _cancelSafely(
            '$objectType popup registry:$objectId ($id)',
            () => popup.cancel(id),
            blocking: blocking,
          ) &&
          ok;
      ok =
          await _cancelEmail(
            id,
            '$objectType:$objectId registry',
            blocking: blocking,
          ) &&
          ok;
    }
    if (ok) {
      _releaseBudgetIds(uniqueIds);
    }
    return ok;
  }

  Future<bool> _cancelRule(
    String objectType,
    String objectId,
    String ruleId, {
    bool blocking = true,
    bool includeEmail = true,
  }) async {
    final intId = _idFor('$objectType:$objectId:$ruleId');
    var ok = true;
    ok =
        await _cancelSafely(
          '$objectType notification:$objectId:$ruleId',
          () => notif.cancel(intId),
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelSafely(
          '$objectType alarm:$objectId:$ruleId',
          () => alarm.cancel(intId),
          blocking: blocking,
        ) &&
        ok;
    if (includeEmail) {
      ok =
          await _cancelEmail(
            intId,
            '$objectType:$objectId:$ruleId',
            blocking: blocking,
          ) &&
          ok;
    }
    ok =
        await _cancelSafely(
          '$objectType popup:$objectId:$ruleId',
          () => popup.cancel(intId),
          blocking: blocking,
        ) &&
        ok;
    if (ok) {
      _releaseBudgetIds(<int>{intId});
    }
    return ok;
  }

  Future<bool> _cancelEmail(
    int id,
    String label, {
    bool blocking = true,
  }) async {
    return _cancelSafely(
      'email:$label ($id)',
      () => email.cancel(id),
      blocking: blocking,
    );
  }

  Future<bool> _cancelSafely(
    String label,
    Future<void> Function() cancel, {
    bool blocking = true,
  }) async {
    try {
      await cancel();
      return true;
    } catch (e, st) {
      debugPrint('[ReminderScheduler] cancel failed for $label: $e\n$st');
      _recordCancellationIssue(label: label, error: e, blocking: blocking);
      return false;
    }
  }

  void _recordCancellationIssue({
    required String label,
    required Object error,
    bool blocking = true,
  }) {
    debugPrint(
      '[ReminderScheduler] Old reminder cleanup failed for $label: $error',
    );
    // 旧提醒清理失败时不阻塞新提醒注册，允许覆盖旧规则
    // 系统通知队列通常允许相同 ID 覆盖，重复注册会自动替换
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: '提醒已更新',
      message: '提醒已保存。若旧提醒仍弹出，可前往"我的 → 通知设置 → 已注册提醒"手动检查。',
      relatedId: _relatedIdFromIssueLabel(label) ?? label,
      blocking: false,
    );
  }

  Future<void> _syncRuleObjects({
    required String objectType,
    required Map<String, Map<String, _ResolvedRule>> wanted,
    required Map<String, Map<String, _ScheduledRule>> scheduled,
    required Future<bool> Function(String objectId, {bool blocking})
    cancelLegacy,
    required Map<String, Set<int>> blockedRegistryIdsByObject,
  }) async {
    final nextScheduled = <String, Map<String, _ScheduledRule>>{};
    final scheduleFailures = <ReminderSyncIssueEntry>[];
    final persistedRegistryIdsByObject = await registry.idsByObject(objectType);

    for (final objectId in scheduled.keys.toList()) {
      final priorRules = scheduled[objectId] ?? const {};
      final nextRules = wanted[objectId];
      if (objectType == 'todo' && nextRules != null) {
        _todoScheduleFailures.remove(objectId);
      }
      final blockedRegistryIds = <int>{
        ...?blockedRegistryIdsByObject[objectId],
      };
      if (nextRules == null) {
        final rulesCancelled = await _cancelRuleObjects(
          objectType,
          objectId,
          priorRules.keys,
        );
        final legacyCancelled = await cancelLegacy(objectId);
        if (!rulesCancelled || !legacyCancelled) {
          nextScheduled[objectId] = Map<String, _ScheduledRule>.from(
            priorRules,
          );
          await _replaceRegistryObject(
            objectType,
            objectId,
            {
              ...blockedRegistryIds,
              ..._registryIdsForScheduledRules(
                objectType,
                objectId,
                priorRules,
              ),
            },
            scheduledRules: priorRules.values,
            acceptedIdSets: _acceptedPendingIdSetsForScheduledRules(
              objectType,
              objectId,
              priorRules,
            ),
          );
        } else {
          await registry.removeObject(objectType, objectId);
        }
        continue;
      }

      final kept = <String, _ScheduledRule>{};
      var legacyCleanupDone = false;
      Future<void> cancelLegacyOnce() async {
        if (legacyCleanupDone) return;
        legacyCleanupDone = true;
        await cancelLegacy(objectId, blocking: false);
      }

      for (final priorEntry in priorRules.entries) {
        if (!nextRules.containsKey(priorEntry.key)) {
          await cancelLegacyOnce();
          final cancelled = await _cancelRule(
            objectType,
            objectId,
            priorEntry.key,
          );
          if (!cancelled) {
            kept[priorEntry.key] = priorEntry.value;
          }
        }
      }

      for (final nextEntry in nextRules.entries) {
        final nextRule = nextEntry.value;
        final prior = priorRules[nextEntry.key];
        final needsCancel =
            prior != null && !_sameScheduledRule(prior, nextRule);
        if (needsCancel) {
          await cancelLegacyOnce();
          await _cancelRule(
            objectType,
            objectId,
            nextEntry.key,
            blocking: false,
            includeEmail: !_isLocalPresentationChange(prior, nextRule),
          );
        }
      }

      for (final nextRule in nextRules.values) {
        final prior = priorRules[nextRule.ruleId];
        if (prior != null && _sameScheduledRule(prior, nextRule)) {
          if (await _scheduledRuleStillPending(nextRule)) {
            _recordRuleBudget(nextRule);
            kept[nextRule.ruleId] = prior;
            continue;
          }
          await cancelLegacyOnce();
          final cancelled = await _cancelRule(
            objectType,
            objectId,
            nextRule.ruleId,
          );
          if (!cancelled) {
            kept[nextRule.ruleId] = prior;
            continue;
          }
        }
        await cancelLegacyOnce();
        final budgetResult = await _prepareRuleDispatchForBudget(nextRule);
        if (budgetResult == _BudgetDecision.skip) {
          continue;
        }
        // 强制注册新规则，即使旧规则清理失败
        // 系统通知 ID 相同时会自动覆盖
        final ok = await _dispatchRule(nextRule);
        var registered = false;
        if (ok) {
          kept[nextRule.ruleId] = _scheduledFromResolved(nextRule);
          registered = true;
        } else {
          _releaseBudgetIds(_registryIdsForRule(nextRule));
          _recordTodoRuleDispatchFailure(nextRule);
          final prior = priorRules[nextRule.ruleId];
          if (prior != null &&
              _sameScheduledRule(prior, nextRule) &&
              await _scheduledRuleStillPending(nextRule)) {
            _recordRuleBudget(nextRule);
            kept[nextRule.ruleId] = prior;
            registered = true;
          }
        }
        if (!registered) {
          _recordRuleScheduleFailure(nextRule);
          scheduleFailures.add(_ruleScheduleFailureEntry(nextRule));
        }
      }

      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
        await _replaceRegistryObject(
          objectType,
          objectId,
          {
            ...blockedRegistryIds,
            ..._registryIdsForScheduledRules(objectType, objectId, kept),
          },
          scheduledRules: kept.values,
          acceptedIdSets: _acceptedPendingIdSetsForScheduledRules(
            objectType,
            objectId,
            kept,
          ),
        );
      } else if (blockedRegistryIds.isNotEmpty) {
        await _replaceRegistryObject(
          objectType,
          objectId,
          blockedRegistryIds,
          resolvedRules: nextRules.values,
          acceptedIdSets: _acceptedPendingIdSetsForResolvedRules(
            nextRules.values,
          ),
        );
      } else {
        await registry.removeObject(objectType, objectId);
      }
    }

    final sortedNewEntries = wanted.entries
        .where((entry) => !scheduled.containsKey(entry.key))
        .toList(growable: false)
      ..sort(
        (a, b) => _earliestRuleFireTime(
          a.value.values,
        ).compareTo(_earliestRuleFireTime(b.value.values)),
      );

    for (final entry in sortedNewEntries) {
      final objectId = entry.key;

      final nextRules = entry.value;
      final kept = <String, _ScheduledRule>{};
      final blockedRegistryIds = <int>{
        ...?blockedRegistryIdsByObject[objectId],
      };
      final persistedRegistryIds =
          persistedRegistryIdsByObject[objectId] ?? const <int>{};
      await cancelLegacy(objectId, blocking: false);
      for (final nextRule in nextRules.values) {
        final nextRuleRegistryIds = _registryIdsForRule(nextRule);
        final cancelled = await _cancelRule(
          objectType,
          objectId,
          nextRule.ruleId,
          blocking: false,
        );
        final hadPersistedRuleIds = persistedRegistryIds.any(
          nextRuleRegistryIds.contains,
        );
        if (!cancelled && hadPersistedRuleIds) {
          blockedRegistryIds.addAll(nextRuleRegistryIds);
        }
        final budgetResult = await _prepareRuleDispatchForBudget(nextRule);
        if (budgetResult == _BudgetDecision.skip) {
          continue;
        }
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _scheduledFromResolved(nextRule);
        } else {
          _releaseBudgetIds(_registryIdsForRule(nextRule));
          _recordRuleScheduleFailure(nextRule);
          scheduleFailures.add(_ruleScheduleFailureEntry(nextRule));
          _recordTodoRuleDispatchFailure(nextRule);
        }
      }
      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
        await _replaceRegistryObject(
          objectType,
          objectId,
          {
            ...blockedRegistryIds,
            ..._registryIdsForScheduledRules(objectType, objectId, kept),
          },
          scheduledRules: kept.values,
          acceptedIdSets: _acceptedPendingIdSetsForScheduledRules(
            objectType,
            objectId,
            kept,
          ),
        );
      } else if (blockedRegistryIds.isNotEmpty) {
        await _replaceRegistryObject(
          objectType,
          objectId,
          blockedRegistryIds,
          resolvedRules: nextRules.values,
          acceptedIdSets: _acceptedPendingIdSetsForResolvedRules(
            nextRules.values,
          ),
        );
      } else {
        await registry.removeObject(objectType, objectId);
      }
    }

    scheduled
      ..clear()
      ..addAll(nextScheduled);

    if (scheduleFailures.isNotEmpty) {
      throw ReminderScheduleSyncException(
        List<String>.unmodifiable(scheduleFailures.map((entry) => entry.raw)),
        issueCopy: ReminderSyncIssue(scheduleFailures),
      );
    }
  }

  bool _sameScheduledRule(_ScheduledRule prior, _ResolvedRule next) {
    return prior.kind == next.kind &&
        prior.mode == next.mode &&
        prior.scope == next.scope &&
        prior.fingerprint == next.fingerprint;
  }

  bool _isLocalPresentationChange(_ScheduledRule prior, _ResolvedRule next) {
    return next.kind != ReminderKind.email &&
        next.kind != ReminderKind.off &&
        prior.kind == next.kind &&
        prior.intentFingerprint == next.intentFingerprint;
  }

  Future<bool> _scheduledRuleStillPending(_ResolvedRule rule) async {
    return _sinkStillPending(
      label: rule.key,
      kind: rule.kind,
      expected: _expectedPendingIdsForRule(rule),
      acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
      stalePeerIds: _registryIdsForRule(rule),
      relatedId: rule.objectId,
    );
  }

  Future<Set<int>> _pendingIdsFor(ReminderPendingSink sink) async {
    final batch = _activeBatch;
    if (batch == null) {
      final cache = _ephemeralPendingIds;
      if (cache != null) {
        final future = cache.putIfAbsent(
          sink,
          () async => Set<int>.unmodifiable((await sink.pendingIds()).toSet()),
        );
        try {
          return await future;
        } catch (_) {
          cache.remove(sink);
          rethrow;
        }
      }
      return (await sink.pendingIds()).toSet();
    }
    if (batch.snapshotFailed(sink)) {
      return batch.fallbackPendingIds(sink);
    }
    try {
      return await batch.pendingIds(sink);
    } catch (_) {
      // A failed batch snapshot must not make every rule share one unsafe
      // answer. Fall back to the existing per-item probe semantics.
      return batch.fallbackPendingIds(sink);
    }
  }

  Future<bool> _habitStillPending(Habit habit) async {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return true;
    // 单条提醒沿用历史校验路径。
    if (rules.length == 1) {
      final rule = rules.single;
      final baseId = _idFor('habit_${habit.id}');
      final weekdays = (rule.hour != null && rule.minute != null)
          ? _applyQuietHoursToRepeating(
              rule.hour!,
              rule.minute!,
              _habitWeekdays(habit, rule),
              rule.kind,
            ).weekdays
          : _habitWeekdays(habit, rule);
      return _sinkStillPending(
        label: 'habit:${habit.id}',
        kind: rule.kind,
        expected: _expectedRepeatingPendingIds(baseId, weekdays),
        acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
          kind: rule.kind,
          base: baseId,
          weekdays: weekdays,
        ),
        stalePeerIds: _habitRegistryIds(habit),
        relatedId: habit.id,
      );
    }
    // 多提醒时间：任一条不在系统队列即视为整体需要重排。
    final peers = _habitRegistryIds(habit);
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      final baseId = _habitRuleId(habit.id, rule, i);
      final weekdays = (rule.hour != null && rule.minute != null)
          ? _applyQuietHoursToRepeating(
              rule.hour!,
              rule.minute!,
              _habitWeekdays(habit, rule),
              rule.kind,
            ).weekdays
          : _habitWeekdays(habit, rule);
      final stillPending = await _sinkStillPending(
        label: 'habit:${habit.id}#${rule.id}',
        kind: rule.kind,
        expected: _expectedRepeatingPendingIds(baseId, weekdays),
        acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
          kind: rule.kind,
          base: baseId,
          weekdays: weekdays,
        ),
        stalePeerIds: peers,
        relatedId: habit.id,
      );
      if (!stillPending) return false;
    }
    return true;
  }

  Future<bool> _anniversaryStillPending(Anniversary item) {
    final baseId = switch (item.reminderKind) {
      ReminderKind.alarm => _idFor('anni_alarm_${item.id}'),
      _ => _idFor('anni_${item.id}'),
    };
    return _sinkStillPending(
      label: 'anniversary:${item.id}',
      kind: item.reminderKind,
      expected: <int>{baseId},
      stalePeerIds: _anniversaryRegistryIds(item),
      relatedId: item.id,
    );
  }

  Future<bool> _countdownStillPending(CountdownItem item) {
    final baseId = _idFor('countdown:${item.id}:due');
    return _sinkStillPending(
      label: 'countdown:${item.id}',
      kind: item.reminderKind,
      expected: <int>{baseId},
      stalePeerIds: _countdownRegistryIds(item),
      relatedId: item.id,
    );
  }

  Future<bool> _sinkStillPending({
    required String label,
    required ReminderKind kind,
    required Set<int> expected,
    List<Set<int>>? acceptedExpectedSets,
    List<Set<int>>? notificationFallbackExpectedSets,
    Set<int>? stalePeerIds,
    String? relatedId,
  }) async {
    if (kind == ReminderKind.popup) {
      // Popup reminders are backed by in-process timers; there is no platform
      // pending queue that can prove the timer survived login, app restart, or
      // account cleanup. If peer cleanup succeeds, force the caller to
      // re-dispatch so the foreground timer is armed again.
      final cleanupSucceeded = await _cancelStalePeerPending(
        label: label,
        ownerKind: kind,
        ids: stalePeerIds ?? expected,
        relatedId: relatedId,
      );
      return !cleanupSucceeded;
    }
    final sink = switch (kind) {
      ReminderKind.push => notif,
      ReminderKind.alarm => alarm,
      _ => null,
    };
    if (sink is! ReminderPendingSink || expected.isEmpty) {
      return _cancelStalePeerPending(
        label: label,
        ownerKind: kind,
        ids: stalePeerIds ?? expected,
        relatedId: relatedId,
      );
    }
    try {
      final actual = await _pendingIdsFor(sink);
      final acceptedSets = acceptedExpectedSets ?? <Set<int>>[expected];
      final pendingSatisfied = acceptedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (pendingSatisfied) {
        await _cancelStalePeerPending(
          label: label,
          ownerKind: kind,
          ids: stalePeerIds ?? expected,
          relatedId: relatedId,
        );
        return true;
      }
      if (kind == ReminderKind.alarm &&
          await _notificationFallbackStillPendingForAlarm(
            label: label,
            acceptedExpectedSets:
                notificationFallbackExpectedSets ?? acceptedSets,
            stalePeerIds: stalePeerIds ?? expected,
            relatedId: relatedId,
          )) {
        return true;
      }
      final missing = expected.difference(actual);
      debugPrint(
        '[ReminderScheduler] pending queue missing for $label: '
        '${missing.join(',')}',
      );
      return false;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] pending probe failed for $label: $e\n$st',
      );
      _recordPendingProbeIssue(
        title: switch (kind) {
          ReminderKind.push => '普通通知状态无法确认',
          ReminderKind.alarm => '闹钟提醒状态无法确认',
          _ => '提醒状态无法确认',
        },
        message: '系统待触发队列查询失败，将重新注册提醒以修复可能丢失的系统队列；请检查系统提醒权限。',
        label: label,
        relatedId: relatedId,
        error: e,
        blocking: kind == ReminderKind.alarm,
      );
      return false;
    }
  }

  Future<bool> _notificationFallbackStillPendingForAlarm({
    required String label,
    required List<Set<int>> acceptedExpectedSets,
    required Set<int> stalePeerIds,
    String? relatedId,
  }) async {
    if (notif is! ReminderPendingSink) return false;
    try {
      final actual = await _pendingIdsFor(notif as ReminderPendingSink);
      final pendingSatisfied = acceptedExpectedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (!pendingSatisfied) return false;
      debugPrint(
        '[ReminderScheduler] notification fallback queue owns alarm reminder '
        'for $label; keep fallback to avoid duplicate delivery.',
      );
      await _cancelStalePeerPending(
        label: label,
        ownerKind: ReminderKind.push,
        ids: stalePeerIds,
        relatedId: relatedId,
      );
      return true;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] notification fallback pending probe failed for '
        '$label; keep prior state to avoid duplicate delivery: $e\n$st',
      );
      _recordPendingProbeIssue(
        title: '普通通知兜底状态无法确认',
        message: '普通通知兜底队列查询失败，已保留现有状态以避免重复弹出；请重新保存提醒或检查系统通知权限。',
        label: label,
        relatedId: relatedId,
        error: e,
        blocking: true,
      );
      return true;
    }
  }

  Future<bool> _alarmQueueAlreadyOwns({
    required String label,
    required Set<int> expected,
    List<Set<int>>? acceptedExpectedSets,
    String? relatedId,
  }) async {
    if (alarm is! ReminderPendingSink || expected.isEmpty) return false;
    try {
      final actual = await _pendingIdsFor(alarm as ReminderPendingSink);
      final acceptedSets = acceptedExpectedSets ?? <Set<int>>[expected];
      final owns = acceptedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (owns) {
        debugPrint(
          '[ReminderScheduler] alarm dispatch for $label failed after the '
          'alarm queue was registered; skip notification fallback to avoid duplicate delivery.',
        );
      }
      return owns;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] alarm fallback pending probe failed for $label; '
        'attempt notification fallback because alarm ownership was not confirmed: '
        '$e\n$st',
      );
      _recordPendingProbeIssue(
        title: '闹钟提醒状态无法确认',
        message: '系统待触发队列查询失败，已尝试使用普通通知兜底保住提醒；请重新保存提醒或检查系统提醒权限。',
        label: label,
        relatedId: relatedId,
        error: e,
        blocking: true,
      );
      return false;
    }
  }

  void _recordPendingProbeIssue({
    required String title,
    required String message,
    required String label,
    required Object error,
    String? relatedId,
    bool blocking = false,
  }) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: title,
      message: message,
      relatedId: relatedId ?? _relatedIdFromIssueLabel(label) ?? label,
      blocking: blocking,
    );
  }

  Future<bool> _cancelStalePeerPending({
    required String label,
    required ReminderKind ownerKind,
    required Set<int> ids,
    String? relatedId,
  }) async {
    if (ids.isEmpty) return true;
    var ok = true;

    Future<void> cleanupPeer({
      required ReminderPendingSink pending,
      required Future<void> Function(int id) cancel,
      required String staleLabel,
    }) async {
      Set<int> staleIds;
      try {
        staleIds = (await _pendingIdsFor(pending)).intersection(ids);
      } catch (e, st) {
        debugPrint(
          '[ReminderScheduler] stale $staleLabel pending probe failed for '
          '$label: $e\n$st',
        );
        _recordPendingProbeIssue(
          title: '残留提醒状态无法确认',
          message: '旧提醒队列查询失败，已保留当前注册状态以避免重复弹出；请重新保存提醒或检查系统提醒权限。',
          label: '$label stale $staleLabel',
          relatedId: relatedId,
          error: e,
        );
        ok = false;
        return;
      }
      for (final id in staleIds) {
        ok =
            await _cancelSafely(
              '$label stale $staleLabel owner:$id',
              () => cancel(id),
            ) &&
            ok;
      }
      if (staleIds.isNotEmpty && !ok) {
        debugPrint(
          '[ReminderScheduler] stale $staleLabel owner cleanup incomplete for '
          '$label; keep current owner without re-registering to avoid duplicates.',
        );
      }
    }

    switch (ownerKind) {
      case ReminderKind.push:
        if (alarm is ReminderPendingSink) {
          await cleanupPeer(
            pending: alarm as ReminderPendingSink,
            cancel: alarm.cancel,
            staleLabel: 'alarm',
          );
        }
        break;
      case ReminderKind.alarm:
        if (notif is ReminderPendingSink) {
          await cleanupPeer(
            pending: notif as ReminderPendingSink,
            cancel: notif.cancel,
            staleLabel: 'notification',
          );
        }
        break;
      case ReminderKind.popup:
        if (notif is ReminderPendingSink) {
          await cleanupPeer(
            pending: notif as ReminderPendingSink,
            cancel: notif.cancel,
            staleLabel: 'notification',
          );
        }
        if (alarm is ReminderPendingSink) {
          await cleanupPeer(
            pending: alarm as ReminderPendingSink,
            cancel: alarm.cancel,
            staleLabel: 'alarm',
          );
        }
        break;
      case ReminderKind.email:
      case ReminderKind.off:
        return true;
    }
    return ok;
  }

  Set<int> _expectedRepeatingPendingIds(int base, List<int> weekdays) {
    if (weekdays.isEmpty) return <int>{base};
    return {for (final weekday in weekdays) _subId(base, weekday)};
  }

  Set<int> _expectedPendingIdsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <int>{base};
    }
    return {for (final weekday in rule.weekdays) _subId(base, weekday)};
  }

  List<Set<int>> _acceptedPendingIdSetsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <Set<int>>[
        <int>{base},
      ];
    }
    return _acceptedRepeatingPendingIdSets(
      kind: rule.kind,
      base: base,
      weekdays: rule.weekdays,
    );
  }

  List<Set<int>> _acceptedRepeatingPendingIdSets({
    required ReminderKind kind,
    required int base,
    required List<int> weekdays,
  }) {
    final expected = _expectedRepeatingPendingIds(base, weekdays);
    if (kind != ReminderKind.alarm || weekdays.isEmpty) {
      return <Set<int>>[expected];
    }
    return <Set<int>>[
      <int>{base},
      expected,
    ];
  }

  Set<int> _registryIdsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <int>{base};
    }
    return <int>{
      base,
      for (final weekday in rule.weekdays) _subId(base, weekday),
      for (final weekday in rule.weekdays) _legacySubId(base, weekday),
    };
  }

  Set<int> _registryIdsForScheduledRules(
    String objectType,
    String objectId,
    Map<String, _ScheduledRule> rules,
  ) {
    return {
      for (final entry in rules.entries)
        ..._registryIdsForScheduledRule(
          objectType,
          objectId,
          entry.key,
          entry.value,
        ),
    };
  }

  Set<int> _registryIdsForScheduledRule(
    String objectType,
    String objectId,
    String ruleId,
    _ScheduledRule rule,
  ) {
    final base = _idFor('$objectType:$objectId:$ruleId');
    if (rule.mode == _DispatchMode.once) return <int>{base};
    final weekdays = _weekdaysFromScope(rule.scope);
    if (weekdays.isEmpty) return <int>{base};
    return <int>{
      base,
      for (final weekday in weekdays) _subId(base, weekday),
      for (final weekday in weekdays) _legacySubId(base, weekday),
    };
  }

  List<int> _weekdaysFromScope(String scope) {
    if (!scope.startsWith('weekly:')) return const <int>[];
    final rawDays = scope.substring('weekly:'.length).split(',');
    final result = <int>{};
    for (final raw in rawDays) {
      final day = int.tryParse(raw);
      if (day != null && day >= 1 && day <= 7) result.add(day);
    }
    return result.toList()..sort();
  }

  Set<int> _habitRegistryIds(Habit habit) {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return const <int>{};
    final ids = <int>{};
    for (var i = 0; i < rules.length; i++) {
      final base = _habitRuleId(habit.id, rules[i], i);
      ids.add(base);
      final weekdays = _habitWeekdays(habit, rules[i]);
      for (final weekday in weekdays) {
        ids.add(_subId(base, weekday));
        ids.add(_legacySubId(base, weekday));
      }
    }
    return ids;
  }

  List<Set<int>> _habitAcceptedPendingIdSets(Habit habit) {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return const <Set<int>>[];
    return _combineAcceptedIdSetAlternatives([
      for (var i = 0; i < rules.length; i++)
        if (_kindUsesSystemPendingQueue(rules[i].kind))
          _acceptedRepeatingPendingIdSets(
            kind: rules[i].kind,
            base: _habitRuleId(habit.id, rules[i], i),
            weekdays: _habitWeekdays(habit, rules[i]),
          ),
    ]);
  }

  Set<int> _anniversaryRegistryIds(Anniversary item) {
    return <int>{_idFor('anni_${item.id}'), _idFor('anni_alarm_${item.id}')};
  }

  List<Set<int>> _anniversaryAcceptedPendingIdSets(Anniversary item) {
    return switch (item.reminderKind) {
      ReminderKind.push => <Set<int>>[
        <int>{_idFor('anni_${item.id}')},
      ],
      ReminderKind.alarm => <Set<int>>[
        <int>{_idFor('anni_alarm_${item.id}')},
      ],
      ReminderKind.popup ||
      ReminderKind.email ||
      ReminderKind.off => const <Set<int>>[],
    };
  }

  Set<int> _countdownRegistryIds(CountdownItem item) {
    return <int>{_idFor('countdown:${item.id}:due')};
  }

  List<Set<int>> _countdownAcceptedPendingIdSets(CountdownItem item) {
    if (!_kindUsesSystemPendingQueue(item.reminderKind)) {
      return const <Set<int>>[];
    }
    return <Set<int>>[
      <int>{_idFor('countdown:${item.id}:due')},
    ];
  }

  _ScheduledRule _scheduledFromResolved(_ResolvedRule rule) {
    return _ScheduledRule(
      kind: rule.kind,
      mode: rule.mode,
      scope: rule.scope,
      fingerprint: rule.fingerprint,
      intentFingerprint: rule.intentFingerprint,
      title: rule.title,
      body: rule.body,
    );
  }

  int _subId(int base, int weekday) {
    var h = 0x811c9dc5;
    final key = '$base:$weekday';
    for (final unit in key.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? weekday : h;
  }

  int _legacySubId(int base, int weekday) =>
      legacyWeekdayNotificationId(base, weekday);

  // -------------------------------------------------------------------------
  // 内部：决定什么时候、以什么通道派发
  // -------------------------------------------------------------------------

  List<_ResolvedRule> _resolveTodoRules(
    TodoItem t, {
    required bool allowJustMissedOneShotReminders,
  }) {
    final plan = _effectiveTodoPlan(t);
    if (!plan.enabled || plan.rules.isEmpty) return const <_ResolvedRule>[];
    final now = DateTime.now();
    final resolved = <_ResolvedRule>[];
    for (final rule in plan.rules) {
      if (!rule.enabled || rule.kind == ReminderKind.off) continue;
      final next = _resolveTodoRule(
        t,
        rule,
        now,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      if (next != null) resolved.add(next);
    }
    return _dedupeResolvedRules(resolved);
  }

  ReminderPlan _effectiveTodoPlan(TodoItem t) {
    if (t.reminderPlan.enabled && t.reminderPlan.rules.isNotEmpty) {
      return t.reminderPlan;
    }
    if (t.reminder.enabled) {
      return ReminderPlan.fromLegacy(t.reminder);
    }
    // ignore: deprecated_member_use_from_same_package
    if (t.hasReminder) {
      final anchor = t.reminderAt ?? t.dueDate;
      if (anchor == null) return const ReminderPlan.disabled();
      return ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'legacy-${t.id}',
            enabled: true,
            type: ReminderRuleType.absolute,
            kind: ReminderKind.push,
            hour: anchor.hour,
            minute: anchor.minute,
          ),
        ],
      );
    }
    return const ReminderPlan.disabled();
  }

  _ResolvedRule? _resolveTodoRule(
    TodoItem t,
    ReminderRule rule,
    DateTime now, {
    required bool allowJustMissedOneShotReminders,
  }) {
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = _absoluteTodoReminderAnchor(t);
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final when = _dateAtTime(anchor, hour, minute);
        final scheduledWhen = _resolveOneShotReminderTime(
          when,
          now,
          allowJustMissed: allowJustMissedOneShotReminders,
        );
        if (scheduledWhen == null) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          when: scheduledWhen,
        );
      case ReminderRuleType.relativeToDue:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = _relativeTodoReminderAnchor(t);
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final base = _dateAtTime(anchor, hour, minute);
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        final scheduledWhen = _resolveOneShotReminderTime(
          when,
          now,
          allowJustMissed: allowJustMissedOneShotReminders,
        );
        if (scheduledWhen == null) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          when: scheduledWhen,
        );
      case ReminderRuleType.dailyTime:
        final payload = _todoPayload(t.id, rule.kind);
        if (!_validTime(rule.hour, rule.minute)) return null;
        return _buildRepeatingRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: const <int>[],
        );
      case ReminderRuleType.weeklyTime:
        final payload = _todoPayload(t.id, rule.kind);
        if (!_validTime(rule.hour, rule.minute) || rule.weekdays.isEmpty) {
          return null;
        }
        return _buildRepeatingRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: _normalizedWeekdays(rule.weekdays),
        );
    }
  }

  List<_ResolvedRule> _resolveGoalRules(GoalItem g) {
    final plan = g.reminderPlan.enabled && g.reminderPlan.rules.isNotEmpty
        ? g.reminderPlan
        : g.reminder.enabled
        ? ReminderPlan.fromLegacy(g.reminder)
        : const ReminderPlan.disabled();
    if (!plan.enabled || plan.rules.isEmpty) return const <_ResolvedRule>[];
    final now = DateTime.now();
    final resolved = <_ResolvedRule>[];
    for (final rule in plan.rules) {
      if (!rule.enabled || rule.kind == ReminderKind.off) continue;
      final next = _resolveGoalRule(g, rule, now);
      if (next != null) resolved.add(next);
    }
    return _dedupeResolvedRules(resolved);
  }

  List<_ResolvedRule> _dedupeResolvedRules(List<_ResolvedRule> rules) {
    if (rules.length < 2) return rules;
    final selectedOnceRuleKeys = <String>{};
    final selectedWeekdaysByRuleKey = <String, Set<int>>{};
    final selectedByOccurrence = <String, _ResolvedRule>{};
    for (final rule in rules) {
      if (rule.mode == _DispatchMode.repeating) {
        for (final weekday in _logicalDeliveryWeekdays(rule)) {
          final fingerprint = _logicalRepeatingDeliveryFingerprint(
            rule,
            weekday,
          );
          final prior = selectedByOccurrence[fingerprint];
          if (prior == null ||
              _deliveryPriority(rule.kind) > _deliveryPriority(prior.kind)) {
            if (prior != null) {
              selectedWeekdaysByRuleKey[prior.key]?.remove(weekday);
            }
            selectedByOccurrence[fingerprint] = rule;
            selectedWeekdaysByRuleKey
                .putIfAbsent(rule.key, () => <int>{})
                .add(weekday);
          }
        }
        continue;
      }

      final fingerprint = rule.logicalDeliveryFingerprint;
      final prior = selectedByOccurrence[fingerprint];
      if (prior == null ||
          _deliveryPriority(rule.kind) > _deliveryPriority(prior.kind)) {
        if (prior != null) {
          selectedOnceRuleKeys.remove(prior.key);
        }
        selectedByOccurrence[fingerprint] = rule;
        selectedOnceRuleKeys.add(rule.key);
      }
    }

    final result = <_ResolvedRule>[];
    for (final rule in rules) {
      if (rule.mode == _DispatchMode.repeating) {
        final weekdays = selectedWeekdaysByRuleKey[rule.key];
        if (weekdays == null || weekdays.isEmpty) continue;
        final original = _logicalDeliveryWeekdays(rule).toSet();
        if (weekdays.length == original.length &&
            weekdays.containsAll(original)) {
          result.add(rule);
        } else {
          result.add(_copyRepeatingRuleWithWeekdays(rule, weekdays));
        }
      } else if (selectedOnceRuleKeys.contains(rule.key)) {
        result.add(rule);
      }
    }
    return result;
  }

  int _deliveryPriority(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.alarm => 4,
      ReminderKind.push => 3,
      ReminderKind.popup => 2,
      ReminderKind.email => 1,
      ReminderKind.off => 0,
    };
  }

  List<int> _logicalDeliveryWeekdays(_ResolvedRule rule) {
    final weekdays = _normalizedWeekdays(rule.weekdays);
    if (weekdays.isEmpty) return const <int>[1, 2, 3, 4, 5, 6, 7];
    return weekdays;
  }

  String _logicalRepeatingDeliveryFingerprint(_ResolvedRule rule, int weekday) {
    return [
      rule.objectType,
      rule.objectId,
      rule.mode.name,
      rule.body,
      rule.hour?.toString() ?? '-',
      rule.minute?.toString() ?? '-',
      weekday,
    ].join('|');
  }

  _ResolvedRule _copyRepeatingRuleWithWeekdays(
    _ResolvedRule rule,
    Iterable<int> weekdays,
  ) {
    final normalized = _normalizedWeekdays(weekdays.toList());
    final scope = normalized.length == 7
        ? 'daily'
        : 'weekly:${normalized.join(',')}';
    return _ResolvedRule(
      objectType: rule.objectType,
      objectId: rule.objectId,
      ruleId: rule.ruleId,
      kind: rule.kind,
      mode: rule.mode,
      ruleType: normalized.length == 7
          ? ReminderRuleType.dailyTime
          : ReminderRuleType.weeklyTime,
      title: rule.title,
      body: rule.body,
      payload: rule.payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      hour: rule.hour,
      minute: rule.minute,
      weekdays: normalized.length == 7 ? const <int>[] : normalized,
      scope: scope,
      quietHoursDigest: rule.quietHoursDigest,
    );
  }

  _ResolvedRule? _resolveGoalRule(GoalItem g, ReminderRule rule, DateTime now) {
    final payload = 'duoyi://goal/${g.id}';
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final anchorDate = _goalAnchorDate(g, now);
        final hour = rule.hour ?? anchorDate.hour;
        final minute = rule.minute ?? anchorDate.minute;
        if (!_validTime(hour, minute)) return null;
        final when = _dateAtTime(anchorDate, hour, minute);
        if (!when.isAfter(now)) {
          final tomorrow = DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 1));
          final fallback = _dateAtTime(tomorrow, hour, minute);
          if (!fallback.isAfter(now)) return null;
          return _buildOnceRule(
            objectType: 'goal',
            objectId: g.id,
            rule: rule,
            title: _titleFor('goal', rule.type, rule.kind),
            body: g.title,
            payload: payload,
            when: fallback,
          );
        }
        return _buildOnceRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.relativeToDue:
        final anchor = g.targetDate;
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final base = _dateAtTime(anchor, hour, minute);
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        if (!when.isAfter(now)) return null;
        return _buildOnceRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.dailyTime:
        if (!_validTime(rule.hour, rule.minute)) return null;
        return _buildRepeatingRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: const <int>[],
        );
      case ReminderRuleType.weeklyTime:
        if (!_validTime(rule.hour, rule.minute) || rule.weekdays.isEmpty) {
          return null;
        }
        return _buildRepeatingRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: _normalizedWeekdays(rule.weekdays),
        );
    }
  }

  _ResolvedRule _buildOnceRule({
    required String objectType,
    required String objectId,
    required ReminderRule rule,
    required String title,
    required String body,
    required String payload,
    required DateTime when,
  }) {
    final effectiveWhen = _applyQuietHoursToOnceTime(when, rule.kind);
    return _ResolvedRule(
      objectType: objectType,
      objectId: objectId,
      ruleId: rule.id,
      kind: rule.kind,
      mode: _DispatchMode.once,
      ruleType: rule.type,
      title: title,
      body: body,
      payload: payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      when: effectiveWhen,
      scope: 'once',
      quietHoursDigest: _quietHours.enabled ? _quietHours.digest : '',
    );
  }

  _ResolvedRule _buildRepeatingRule({
    required String objectType,
    required String objectId,
    required ReminderRule rule,
    required String title,
    required String body,
    required String payload,
    required int hour,
    required int minute,
    required List<int> weekdays,
  }) {
    final rawNormalized = weekdays.isEmpty ? const <int>[] : weekdays;
    final adjusted = _applyQuietHoursToRepeating(
      hour,
      minute,
      rawNormalized,
      rule.kind,
    );
    final normalized = adjusted.weekdays;
    final scope = normalized.isEmpty
        ? 'daily'
        : 'weekly:${normalized.join(',')}';
    return _ResolvedRule(
      objectType: objectType,
      objectId: objectId,
      ruleId: rule.id,
      kind: rule.kind,
      mode: _DispatchMode.repeating,
      ruleType: rule.type,
      title: title,
      body: body,
      payload: payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      hour: adjusted.hour,
      minute: adjusted.minute,
      weekdays: normalized,
      scope: scope,
      quietHoursDigest: _quietHours.enabled ? _quietHours.digest : '',
    );
  }

  Future<bool> _dispatchRule(_ResolvedRule rule) async {
    try {
      switch (rule.mode) {
        case _DispatchMode.once:
          if (rule.when == null) return false;
          return await _dispatch(
            kind: rule.kind,
            payload: _DispatchPayload(
              id: _idFor(rule.key),
              title: rule.title,
              body: rule.body,
              when: rule.when!,
              payload: rule.payload,
              fullScreen: rule.fullScreen,
              vibrate: rule.vibrate,
              snoozeMinutes: rule.snoozeMinutes,
              repeatCount: rule.repeatCount,
            ),
          );
        case _DispatchMode.repeating:
          return await _dispatchRepeating(rule);
      }
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] dispatch failed for ${rule.key}: $e\n$st',
      );
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 内部：时间与文案
  // -------------------------------------------------------------------------

  DateTime _dateAtTime(DateTime date, int hour, int minute) {
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime _countdownReminderAt(CountdownItem item) {
    final target = DateTime(
      item.targetDate.year,
      item.targetDate.month,
      item.targetDate.day,
      item.remindHour,
      item.remindMinute,
    );
    return target.subtract(Duration(days: item.remindDaysBefore));
  }

  String _countdownScope(CountdownItem item, DateTime when) {
    final base =
        '${when.millisecondsSinceEpoch}:${item.title}:${item.remindDaysBefore}:${item.remindHour}:${item.remindMinute}:${item.reminderKind.name}';
    if (!_quietHours.enabled) return base;
    return '$base|qh:${_quietHours.digest}';
  }

  String _habitScope(Habit habit) {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return 'off';
    String fingerprint(ReminderRule rule) {
      final weekdays = _habitWeekdays(habit, rule);
      return [
        rule.kind.name,
        rule.type.name,
        rule.hour,
        rule.minute,
        rule.fullScreen,
        rule.vibrate,
        rule.snoozeMinutes,
        rule.repeatCount,
        weekdays.join(','),
      ].join('|');
    }

    // 单条提醒保持与历史完全一致的 scope，避免无谓重排与既有测试漂移。
    if (rules.length == 1) {
      return [habit.name, fingerprint(rules.single)].join('|');
    }
    // 多提醒时间：把每条规则的指纹（含 ruleId）一起编码，任一条变更都重排。
    return [
      habit.name,
      for (final rule in rules) '${rule.id}~${fingerprint(rule)}',
    ].join('||');
  }

  ReminderPlan _effectiveHabitPlan(Habit habit) {
    if (habit.reminderPlan.enabled && habit.reminderPlan.rules.isNotEmpty) {
      return habit.reminderPlan;
    }
    if (habit.remind &&
        habit.remindHour != null &&
        habit.remindMinute != null) {
      final weekdays = habit.activeWeekdays.map((w) => w + 1).toSet().toList()
        ..sort();
      return ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'habit-reminder',
            enabled: true,
            type: weekdays.length == 7
                ? ReminderRuleType.dailyTime
                : ReminderRuleType.weeklyTime,
            kind: ReminderKind.popup,
            hour: habit.remindHour,
            minute: habit.remindMinute,
            weekdays: weekdays.length == 7 ? const <int>[] : weekdays,
          ),
        ],
      );
    }
    return const ReminderPlan.disabled();
  }

  List<int> _habitWeekdays(Habit habit, ReminderRule rule) {
    if (rule.type == ReminderRuleType.weeklyTime && rule.weekdays.isNotEmpty) {
      return _normalizedWeekdays(rule.weekdays);
    }
    if (rule.type == ReminderRuleType.dailyTime) return const <int>[];
    final weekdays =
        habit.activeWeekdays
            .where((w) => w >= 0 && w <= 6)
            .map((w) => w + 1)
            .toSet()
            .toList()
          ..sort();
    return weekdays.length == 7 ? const <int>[] : weekdays;
  }

  /// 通知标题的品牌文案；默认 defaultBrand 与历史硬编码文案一致，
  /// 切换主题后由外部通过 [setStrings] 注入对应主题词条。
  BrandStrings _strings = BrandStrings.defaultBrand;

  /// 注入当前主题的通知文案（对齐 NotificationService.setStrings）。
  // ignore: use_setters_to_change_properties
  void setStrings(BrandStrings strings) {
    _strings = strings;
  }

  String _habitTitle() {
    return _strings.notifHabitRemindTitle;
  }

  String _todoTitle(TodoItem item, ReminderRuleType type) {
    return ReminderDeliveryCopy.todo(
      item.title,
      type,
    ).render(locale: I18n.current, strings: _strings).title;
  }

  List<int> _normalizedWeekdays(List<int> weekdays) {
    final normalized = <int>{};
    for (final day in weekdays) {
      if (day >= 1 && day <= 7) normalized.add(day);
    }
    final result = normalized.toList()..sort();
    return result;
  }

  bool _validTime(int? hour, int? minute) {
    return hour != null &&
        minute != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59;
  }

  String _titleFor(
    String objectType,
    ReminderRuleType type,
    ReminderKind kind,
  ) {
    if (objectType == 'goal') {
      // Email intent remains unchanged until a backend copy-update contract exists.
      return ReminderDeliveryCopy.goal('', type, kind)
          .render(
            locale: kind == ReminderKind.email ? AppLocale.zh : I18n.current,
            strings: _strings,
          )
          .title;
    }
    const subject = '待办';
    final prefix = switch (kind) {
      ReminderKind.alarm => '⏰',
      ReminderKind.popup => '🔔',
      ReminderKind.email => '✉️',
      ReminderKind.off => '🔕',
      ReminderKind.push => '🔔',
    };
    return switch (type) {
      ReminderRuleType.absolute => '$prefix $subject提醒',
      ReminderRuleType.relativeToDue => '$prefix $subject提前提醒',
      ReminderRuleType.dailyTime => '$prefix 每日$subject提醒',
      ReminderRuleType.weeklyTime => '$prefix 每周$subject提醒',
    };
  }

  String _todoPayload(String id, ReminderKind kind) {
    if (kind == ReminderKind.alarm) return 'duoyi://todo/$id?confirm=1';
    return 'duoyi://todo/$id';
  }

  Future<bool> _dispatchAnniversary(Anniversary item, DateTime remindAt) async {
    final effectiveWhen = _applyQuietHoursToOnceTime(remindAt, item.reminderKind);
    final copy = ReminderDeliveryCopy.anniversary(
      item.title,
      item.remindDaysBefore,
      item.reminderKind,
    ).render(locale: I18n.current, strings: _strings);
    switch (item.reminderKind) {
      case ReminderKind.push:
        try {
          await notif.scheduleAnniversary(
            annId: item.id,
            title: item.title,
            whenDate: item.nextOccurrence,
            daysBefore: item.remindDaysBefore,
            hour: effectiveWhen.hour,
            minute: effectiveWhen.minute,
          );
          return true;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary push permission denied for ${item.id}: $e',
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary push dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.popup:
        try {
          await popup.scheduleOnce(
            id: _idFor('anni_${item.id}'),
            title: copy.title,
            body: copy.body,
            when: effectiveWhen,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary popup dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.alarm:
        final alarmId = _idFor('anni_alarm_${item.id}');
        final alarmIds = <int>{alarmId};
        try {
          await alarm.scheduleFullScreen(
            id: alarmId,
            title: copy.title,
            body: copy.body,
            when: effectiveWhen,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return !_recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: effectiveWhen,
            alarmIds: alarmIds,
          );
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm permission denied for ${item.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: alarmIds,
            relatedId: item.id,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: item.id,
              scheduledTime: remindAt,
              alarmIds: alarmIds,
            );
          }
          await _scheduleAnniversaryPushFallback(item);
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary notification permission denied for ${item.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: alarmIds,
            relatedId: item.id,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: item.id,
              scheduledTime: remindAt,
              alarmIds: alarmIds,
            );
          }
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm queue handoff failed for ${item.id}: $e',
          );
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm dispatch failed for ${item.id}: $e\n$st',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: alarmIds,
            relatedId: item.id,
          )) {
            return !_recordAlarmScheduleIssue(
              relatedId: item.id,
              scheduledTime: remindAt,
              alarmIds: alarmIds,
            );
          }
          await _scheduleAnniversaryPushFallback(item);
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: true,
            alarmIds: alarmIds,
          );
          return false;
        }
      case ReminderKind.email:
        try {
          await email.scheduleOnce(
            id: _idFor('anni_${item.id}'),
            title: '✉️ 纪念日提醒',
            body: item.remindDaysBefore == 0
                ? '今天是 ${item.title}'
                : '${item.remindDaysBefore} 天后是 ${item.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary email dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  String? _fallbackPayload(String? payload) {
    if (payload == null) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null) return payload;
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('confirm')
      ..['fallback'] = 'push';
    return uri.replace(queryParameters: query).toString();
  }

  /// 目标锚定日：未设置开始日期时按创建日开启；提醒只从今天或未来开始注册。
  DateTime _goalAnchorDate(GoalItem g, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = g.startDate ?? g.createdAt;
    final startDay = DateTime(start.year, start.month, start.day);
    return startDay.isAfter(today) ? startDay : today;
  }

  // -------------------------------------------------------------------------
  // 内部：字符串 id → 稳定 int（与 `NotificationService._idFor` 等价）
  // -------------------------------------------------------------------------

  int _idFor(String key) {
    int h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _avoidReservedNotificationId(h);
  }

  int _avoidReservedNotificationId(int id) {
    var next = id;
    while (_reservedNotificationIds.contains(next)) {
      next = (next + 1) & 0x7fffffff;
    }
    return next;
  }

  static const Set<int> _reservedNotificationIds = <int>{
    880016,
    880017,
    880018,
    880019,
    880020,
    880021,
    880022,
    880023,
    919001,
    919002,
    919003,
    919004,
    919005,
    919006,
    919007,
  };

  DateTime _anniversaryReminderAt(Anniversary item) {
    final next = item.nextOccurrence;
    return DateTime(
      next.year,
      next.month,
      next.day,
      item.remindHour,
      item.remindMinute,
    ).subtract(Duration(days: item.remindDaysBefore));
  }

  String _anniversaryScope(Anniversary item, DateTime when) {
    final base = [
      item.reminderKind.index,
      item.title,
      item.remindDaysBefore,
      item.remindHour,
      item.remindMinute,
      when.toIso8601String(),
    ].join('|');
    if (!_quietHours.enabled) return base;
    return '$base|qh:${_quietHours.digest}';
  }

  DateTime _applyQuietHoursToOnceTime(DateTime when, ReminderKind kind) {
    if (!_quietHours.enabled) return when;
    if (kind == ReminderKind.alarm && _quietHours.allowAlarms) return when;
    if (!_quietHours.deferUntilEnd) return when;
    if (!_quietHours.isWithinQuietHours(when)) return when;
    return _quietHours.nextQuietEndLocal(when);
  }

  ({int hour, int minute, List<int> weekdays, bool silent})
  _applyQuietHoursToRepeating(
    int hour,
    int minute,
    List<int> weekdays,
    ReminderKind kind,
  ) {
    if (!_quietHours.enabled) {
      return (hour: hour, minute: minute, weekdays: weekdays, silent: false);
    }
    if (kind == ReminderKind.alarm && _quietHours.allowAlarms) {
      return (hour: hour, minute: minute, weekdays: weekdays, silent: false);
    }
    final minutesOfDay = hour * 60 + minute;
    if (!_quietHours.isMinutesInQuietWindow(minutesOfDay)) {
      return (hour: hour, minute: minute, weekdays: weekdays, silent: false);
    }
    if (!_quietHours.deferUntilEnd) {
      return (hour: hour, minute: minute, weekdays: weekdays, silent: true);
    }
    var adjustedWeekdays = weekdays;
    final wrapsMidnight =
        _quietHours.startMinutes > _quietHours.endMinutes &&
        minutesOfDay >= _quietHours.startMinutes;
    if (wrapsMidnight && weekdays.isNotEmpty && weekdays.length < 7) {
      adjustedWeekdays =
          weekdays.map((day) => (day % 7) + 1).toSet().toList()..sort();
    }
    return (
      hour: _quietHours.endHour,
      minute: _quietHours.endMinute,
      weekdays: adjustedWeekdays,
      silent: false,
    );
  }

  String _habitScopeWithQuietHours(Habit habit) {
    final base = _habitScope(habit);
    if (!_quietHours.enabled) return base;
    return '$base|qh:${_quietHours.digest}';
  }

  DateTime _nextRepeatingFireAt(
    int hour,
    int minute,
    List<int> weekdays, {
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    for (var offset = 0; offset <= 7; offset++) {
      final candidate = DateTime(
        effectiveNow.year,
        effectiveNow.month,
        effectiveNow.day + offset,
        hour,
        minute,
      );
      if (!candidate.isAfter(effectiveNow)) continue;
      if (weekdays.isEmpty || weekdays.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return DateTime(
      effectiveNow.year,
      effectiveNow.month,
      effectiveNow.day + 1,
      hour,
      minute,
    );
  }

  DateTime _ruleNextFireTime(_ResolvedRule rule, {DateTime? now}) {
    if (rule.mode == _DispatchMode.once && rule.when != null) {
      return rule.when!;
    }
    if (rule.hour != null && rule.minute != null) {
      return _nextRepeatingFireAt(
        rule.hour!,
        rule.minute!,
        rule.weekdays,
        now: now,
      );
    }
    return (now ?? DateTime.now()).add(const Duration(days: 3650));
  }

  DateTime _earliestRuleFireTime(
    Iterable<_ResolvedRule> rules, {
    DateTime? now,
  }) {
    DateTime? best;
    for (final rule in rules) {
      final fire = _ruleNextFireTime(rule, now: now);
      if (best == null || fire.isBefore(best)) best = fire;
    }
    return best ?? (now ?? DateTime.now()).add(const Duration(days: 3650));
  }

  Future<_BudgetDecision> _prepareRuleDispatchForBudget(
    _ResolvedRule rule,
  ) async {
    final ids = _registryIdsForRule(rule);
    final reserved = await _tryReserveBudgetIds(
      ids,
      _ruleNextFireTime(rule),
      objectType: rule.objectType,
      objectId: rule.objectId,
    );
    return reserved ? _BudgetDecision.proceed : _BudgetDecision.skip;
  }

  void _recordRuleBudget(_ResolvedRule rule) {
    _recordBudgetIds(
      _registryIdsForRule(rule),
      _ruleNextFireTime(rule),
      objectType: rule.objectType,
      objectId: rule.objectId,
    );
  }

  DateTime _habitBudgetFireTime(Habit habit, {DateTime? now}) {
    final rules = _enabledHabitRules(habit);
    DateTime? earliest;
    for (final rule in rules) {
      if (rule.hour == null || rule.minute == null) continue;
      final adjusted = _applyQuietHoursToRepeating(
        rule.hour!,
        rule.minute!,
        _habitWeekdays(habit, rule),
        rule.kind,
      );
      final candidate = _nextRepeatingFireAt(
        adjusted.hour,
        adjusted.minute,
        adjusted.weekdays,
        now: now,
      );
      if (earliest == null || candidate.isBefore(earliest)) {
        earliest = candidate;
      }
    }
    return earliest ?? (now ?? DateTime.now()).add(const Duration(days: 3650));
  }

  Future<bool> _reserveHabitBudget(Habit habit) {
    return _tryReserveBudgetIds(
      _habitRegistryIds(habit),
      _habitBudgetFireTime(habit),
      objectType: 'habit',
      objectId: habit.id,
    );
  }

  void _recordHabitBudget(Habit habit) {
    _recordBudgetIds(
      _habitRegistryIds(habit),
      _habitBudgetFireTime(habit),
      objectType: 'habit',
      objectId: habit.id,
    );
  }

  void _recordBudgetIds(
    Set<int> ids,
    DateTime fireAt, {
    required String objectType,
    required String objectId,
  }) {
    for (final id in ids) {
      if (id == 0) continue;
      _budgetedAlarmTimes[id] = fireAt;
      _budgetedAlarmOwners[id] = (objectType: objectType, objectId: objectId);
    }
  }

  void _releaseBudgetIds(Iterable<int> ids) {
    for (final id in ids) {
      _budgetedAlarmTimes.remove(id);
      _budgetedAlarmOwners.remove(id);
    }
  }

  Future<bool> _tryReserveBudgetIds(
    Set<int> ids,
    DateTime fireAt, {
    required String objectType,
    required String objectId,
  }) async {
    final cleanIds = ids.where((id) => id != 0).toSet();
    if (cleanIds.isEmpty) return true;
    final missingCount = cleanIds
        .where((id) => !_budgetedAlarmTimes.containsKey(id))
        .length;
    while (_budgetedAlarmTimes.length + missingCount > maxActiveAlarms) {
      MapEntry<int, DateTime>? farthest;
      for (final entry in _budgetedAlarmTimes.entries) {
        if (cleanIds.contains(entry.key)) continue;
        if (farthest == null || entry.value.isAfter(farthest.value)) {
          farthest = entry;
        }
      }
      if (farthest == null || !fireAt.isBefore(farthest.value)) {
        return false;
      }
      await _evictBudgetOwnerId(farthest.key);
    }
    _recordBudgetIds(
      cleanIds,
      fireAt,
      objectType: objectType,
      objectId: objectId,
    );
    return true;
  }

  Future<void> _evictBudgetOwnerId(int evictedId) async {
    final owner = _budgetedAlarmOwners.remove(evictedId);
    _budgetedAlarmTimes.remove(evictedId);
    await _cancelSafely(
      'budget evict notif:$evictedId',
      () => notif.cancel(evictedId),
      blocking: false,
    );
    await _cancelSafely(
      'budget evict alarm:$evictedId',
      () => alarm.cancel(evictedId),
      blocking: false,
    );
    await _cancelSafely(
      'budget evict popup:$evictedId',
      () => popup.cancel(evictedId),
      blocking: false,
    );
    await _cancelEmail(evictedId, 'budget_evict:$evictedId', blocking: false);
    if (owner == null) return;
    final objectType = owner.objectType;
    final objectId = owner.objectId;
    switch (objectType) {
      case 'todo':
        final rules = _scheduledTodoRules[objectId];
        if (rules != null) {
          rules.removeWhere(
            (ruleId, _) => _idFor('todo:$objectId:$ruleId') == evictedId,
          );
          if (rules.isEmpty) {
            _scheduledTodoRules.remove(objectId);
            _forgetReminderDisplay('todo', objectId);
          }
        }
        break;
      case 'goal':
        final rules = _scheduledGoalRules[objectId];
        if (rules != null) {
          rules.removeWhere(
            (ruleId, _) => _idFor('goal:$objectId:$ruleId') == evictedId,
          );
          if (rules.isEmpty) {
            _scheduledGoalRules.remove(objectId);
            _forgetReminderDisplay('goal', objectId);
          }
        }
        break;
      case 'habit':
        _scheduledHabitScopes.remove(objectId);
        _forgetReminderDisplay('habit', objectId);
        break;
      case 'anniversary':
        _scheduledAnniversaryScopes.remove(objectId);
        _forgetReminderDisplay('anniversary', objectId);
        break;
      case 'countdown':
        _scheduledCountdownScopes.remove(objectId);
        _forgetReminderDisplay('countdown', objectId);
        break;
      case 'course':
        _scheduledCourseScopes.remove(objectId);
        _forgetReminderDisplay('course', objectId);
        break;
      case 'calendar_event':
        _scheduledCalendarEventScopes.remove(objectId);
        _forgetReminderDisplay('calendar_event', objectId);
        break;
    }
    try {
      final persisted = await registry.idsByObject(objectType);
      final current = Set<int>.from(persisted[objectId] ?? const <int>{})
        ..remove(evictedId);
      if (current.isEmpty) {
        await registry.removeObject(objectType, objectId);
      } else {
        await registry.replaceObject(
          objectType,
          objectId,
          current,
          display: _registeredReminderDisplay['$objectType:$objectId'],
        );
      }
    } catch (_) {}
  }

  ({DateTime classStart, DateTime remindAt})? _nextCourseOccurrence(
    CourseItem course,
    ScheduleSettings settings,
    DateTime now,
  ) {
    if (course.reminderMinutes <= 0) return null;
    final weeks =
        course.weeks
            .where((w) => w >= 1 && w <= settings.totalWeeks)
            .toSet()
            .toList()
          ..sort();
    if (weeks.isEmpty) return null;
    final termDay = DateTime(
      settings.termStart.year,
      settings.termStart.month,
      settings.termStart.day,
    );
    for (final week in weeks) {
      final weekBase = DateTime(
        termDay.year,
        termDay.month,
        termDay.day + (week - 1) * 7,
      );
      final dayOffset = (course.weekday - weekBase.weekday + 7) % 7;
      final classDate = DateTime(
        weekBase.year,
        weekBase.month,
        weekBase.day + dayOffset,
      );
      final classStart = settings.sectionStart(classDate, course.startSection);
      final remindAt = classStart.subtract(
        Duration(minutes: course.reminderMinutes),
      );
      if (remindAt.isAfter(now)) {
        return (classStart: classStart, remindAt: remindAt);
      }
    }
    return null;
  }

  void _rememberCourseReminderDisplay(CourseItem course, DateTime remindAt) {
    final name = course.name.trim();
    final timeStr = _timeLabel(remindAt.hour, remindAt.minute);
    _rememberReminderDisplay(
      'course',
      course.id,
      title: name.isEmpty ? '课程提醒' : name,
      subtitle: '课程 · ${remindAt.month}/${remindAt.day} $timeStr · 普通通知',
      kinds: const <ReminderKind>{ReminderKind.push},
    );
  }

  DateTime _calendarEventStartAt(CalendarEvent event) {
    final t = event.time;
    if (t == null) {
      return DateTime(event.date.year, event.date.month, event.date.day, 9, 0);
    }
    return DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
      t.hour,
      t.minute,
    );
  }

  void _rememberCalendarEventReminderDisplay(
    CalendarEvent event,
    DateTime remindAt,
  ) {
    final title = event.title.trim();
    final timeStr = _timeLabel(remindAt.hour, remindAt.minute);
    _rememberReminderDisplay(
      'calendar_event',
      event.id,
      title: title.isEmpty ? '日程提醒' : title,
      subtitle: '日程 · ${remindAt.month}/${remindAt.day} $timeStr · 普通通知',
      kinds: const <ReminderKind>{ReminderKind.push},
    );
  }
}

enum _BudgetDecision { proceed, skip }

/// 周年提醒时刻已过（如打开 app 时当天的提醒时刻已经过去）时，
/// 推进到下一年同一时刻，避免该周年被跳过后整年漏提醒；
/// 闰日（2/29）推进后由 DateTime 自动滚动到 3/1。未来时刻原样返回。
DateTime rollAnniversaryRemindAtForward(DateTime remindAt, DateTime now) {
  if (remindAt.isAfter(now)) return remindAt;
  return DateTime(
    remindAt.year + 1,
    remindAt.month,
    remindAt.day,
    remindAt.hour,
    remindAt.minute,
  );
}
