import 'dart:async';

import 'package:flutter/material.dart';

import 'reminder_sinks.dart';

typedef ReminderPopupContextGetter = BuildContext? Function();
typedef ReminderPopupPayloadOpener = void Function(String payload);
typedef ReminderPopupForegroundGetter = bool Function();

class ForegroundReminderPopupSink implements ReminderInAppOnlyPopupSink {
  static const Duration _visiblePopupDuplicateWindow = Duration(seconds: 3);

  final ReminderPopupContextGetter contextGetter;
  final ReminderPopupPayloadOpener? onOpenPayload;
  final ReminderNotificationSink? notificationFallback;
  final ReminderPopupForegroundGetter isForegroundGetter;
  final Map<int, Timer> _timers = {};
  final Set<int> _visibleDialogIds = <int>{};
  final Map<String, DateTime> _recentVisibleDialogSignatures =
      <String, DateTime>{};
  final Map<int, String> _visibleDialogSignatures = <int, String>{};
  final Map<int, NavigatorState> _visibleNavigators = <int, NavigatorState>{};

  ForegroundReminderPopupSink({
    required this.contextGetter,
    this.onOpenPayload,
    this.notificationFallback,
    ReminderPopupForegroundGetter? isForegroundGetter,
  }) : isForegroundGetter = isForegroundGetter ?? _defaultIsForeground;

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    await cancel(id);
    final delay = when.difference(DateTime.now());
    if (delay <= Duration.zero) {
      throw StateError('提醒时间已过去，popup 提醒未注册');
    }
    await _scheduleFallbackOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      payload: payload,
    );
    final hasFallback = notificationFallback != null;
    if (!hasFallback) {
      _timers[id] = Timer(delay, () {
        _timers.remove(id);
        _showOrFallback(
          id: id,
          title: title,
          body: body,
          payload: payload,
          fallbackWasCancelled: false,
          cancelFallbackAfterDialog: false,
        );
      });
      return;
    }
    _timers[id] = Timer(delay, () {
      _prepareForegroundDelivery(
        id: id,
        title: title,
        body: body,
        payload: payload,
        cancelFallbackAfterDialog: hasFallback,
      );
    });
  }

  @override
  Future<void> scheduleInAppOnlyOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    await cancel(id);
    final delay = when.difference(DateTime.now());
    if (delay <= Duration.zero) {
      throw StateError('提醒时间已过去，popup 提醒未注册');
    }
    _timers[id] = Timer(delay, () {
      _timers.remove(id);
      if (!isForegroundGetter()) return;
      final context = contextGetter();
      if (context == null || !context.mounted) return;
      _show(id: id, title: title, body: body, payload: payload);
    });
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    await cancel(id);
    await _scheduleFallbackRepeating(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: payload,
    );

    void scheduleNext() {
      final next = _nextOccurrence(hour, minute, weekdays);
      final delay = next.difference(DateTime.now());
      final hasFallback = notificationFallback != null;
      if (!hasFallback) {
        _timers[id] = Timer(delay, () {
          _timers.remove(id);
          _showOrFallback(
            id: id,
            title: title,
            body: body,
            payload: payload,
            fallbackWasCancelled: false,
            cancelFallbackAfterDialog: false,
            onForegroundDelivered: scheduleNext,
            onBackgroundDelivered: scheduleNext,
          );
        });
        return;
      }
      _timers[id] = Timer(delay, () {
        _prepareForegroundDelivery(
          id: id,
          title: title,
          body: body,
          payload: payload,
          cancelFallbackAfterDialog: hasFallback,
          onForegroundDelivered: () {
            unawaited(
              _rescheduleRepeatingFallbackSafely(
                id: id,
                title: title,
                body: body,
                hour: hour,
                minute: minute,
                weekdays: weekdays,
                payload: payload,
              ),
            );
            scheduleNext();
          },
          onBackgroundDelivered: scheduleNext,
        );
      });
    }

    scheduleNext();
  }

  Future<void> _rescheduleRepeatingFallbackSafely({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    try {
      await _scheduleFallbackRepeating(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: payload,
      );
    } catch (e, st) {
      debugPrint(
        '[ForegroundReminderPopupSink] repeating fallback reschedule failed: '
        '$e\n$st',
      );
      final issueSink = notificationFallback;
      if (issueSink is ReminderScheduleIssueSink) {
        (issueSink as ReminderScheduleIssueSink).recordReminderScheduleIssue(
          title: '弹出提醒兜底重建失败',
          message: '前台弹出提醒已展示，但下一次后台通知兜底未能重新注册。请检查通知权限后重新保存提醒。($e)',
          relatedId: _relatedIdFromPayload(payload) ?? id.toString(),
          blocking: false,
        );
      }
    }
  }

  Future<void> _scheduleFallbackOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    final fallback = notificationFallback;
    if (fallback == null) return;
    try {
      await fallback.scheduleOnce(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: _fallbackPayload(payload),
      );
    } catch (e, st) {
      debugPrint(
        '[ForegroundReminderPopupSink] one-shot fallback schedule failed: '
        '$e\n$st',
      );
      throw ReminderPopupFallbackUnavailableException(
        '弹出提醒的系统通知兜底注册失败，提醒未可靠注册。请检查通知权限和通知渠道后重试。($e)',
      );
    }
  }

  Future<void> _scheduleFallbackRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    final fallback = notificationFallback;
    if (fallback == null) return;
    try {
      await fallback.scheduleDaily(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: _fallbackPayload(payload),
      );
    } catch (e, st) {
      debugPrint(
        '[ForegroundReminderPopupSink] repeating fallback schedule failed: '
        '$e\n$st',
      );
      throw ReminderPopupFallbackUnavailableException(
        '重复弹出提醒的系统通知兜底注册失败，提醒未可靠注册。请检查通知权限和通知渠道后重试。($e)',
      );
    }
  }

  void _prepareForegroundDelivery({
    required int id,
    required String title,
    required String body,
    required String? payload,
    required bool cancelFallbackAfterDialog,
    VoidCallback? onForegroundDelivered,
    VoidCallback? onBackgroundDelivered,
  }) {
    _timers.remove(id);
    // 若此时应用已后台/上下文失效，让兜底通知接管，不再尝试前台弹窗。
    // 关键：**不取消**兜底通知，否则后台时用户什么都收不到。
    if (!isForegroundGetter()) {
      (onBackgroundDelivered ?? onForegroundDelivered)?.call();
      return;
    }
    final context = contextGetter();
    if (context == null || !context.mounted) {
      (onBackgroundDelivered ?? onForegroundDelivered)?.call();
      return;
    }
    _showOrFallback(
      id: id,
      title: title,
      body: body,
      payload: payload,
      fallbackWasCancelled: false,
      cancelFallbackAfterDialog: cancelFallbackAfterDialog,
      onForegroundDelivered: onForegroundDelivered,
      onBackgroundDelivered: onBackgroundDelivered,
    );
  }

  void _showOrFallback({
    required int id,
    required String title,
    required String body,
    required String? payload,
    required bool fallbackWasCancelled,
    required bool cancelFallbackAfterDialog,
    VoidCallback? onForegroundDelivered,
    VoidCallback? onBackgroundDelivered,
  }) {
    final shown = isForegroundGetter()
        ? _show(id: id, title: title, body: body, payload: payload)
        : false;
    if (!shown) {
      if (fallbackWasCancelled) {
        unawaited(
          _scheduleFallbackOnce(
            id: id,
            title: title,
            body: body,
            when: DateTime.now().add(const Duration(seconds: 1)),
            payload: payload,
          ).catchError((Object error, StackTrace st) {
            debugPrint(
              '[ForegroundReminderPopupSink] immediate fallback failed: '
              '$error\n$st',
            );
          }),
        );
        onForegroundDelivered?.call();
        return;
      }
      (onBackgroundDelivered ?? onForegroundDelivered)?.call();
      return;
    }
    if (cancelFallbackAfterDialog) {
      unawaited(
        notificationFallback?.cancel(id).catchError((
          Object error,
          StackTrace st,
        ) {
          debugPrint(
            '[ForegroundReminderPopupSink] fallback cancel failed: $error\n$st',
          );
        }),
      );
    }
    onForegroundDelivered?.call();
  }

  String? _fallbackPayload(String? payload) {
    if (payload == null || payload.isEmpty) return payload;
    final uri = Uri.tryParse(payload);
    if (uri == null) return payload;
    final query = Map<String, String>.from(uri.queryParameters)
      ..putIfAbsent('fallback', () => 'popup_notification');
    return uri.replace(queryParameters: query).toString();
  }

  String? _relatedIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null ||
        uri.scheme != 'duoyi' ||
        uri.pathSegments.isEmpty) {
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

  @override
  Future<void> cancel(int id) async {
    _timers.remove(id)?.cancel();
    try {
      await notificationFallback?.cancel(id);
    } catch (e, st) {
      debugPrint(
        '[ForegroundReminderPopupSink] fallback cancel failed: $e\n$st',
      );
    }
    final navigator = _visibleNavigators.remove(id);
    if (navigator != null && navigator.mounted) {
      await navigator.maybePop();
    }
    _visibleDialogSignatures.remove(id);
    _visibleDialogIds.remove(id);
  }

  DateTime _nextOccurrence(int hour, int minute, List<int>? weekdays) {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    final repeatDays = (weekdays ?? const <int>[])
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toSet();
    while (!next.isAfter(now) ||
        (repeatDays.isNotEmpty && !repeatDays.contains(next.weekday))) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  bool _show({
    required int id,
    required String title,
    required String body,
    required String? payload,
  }) {
    if (!isForegroundGetter()) return false;
    final context = contextGetter();
    if (context == null || !context.mounted) return false;
    final signature = _popupSignature(
      title: title,
      body: body,
      payload: payload,
    );
    if (!_reserveVisibleDialog(id: id, signature: signature)) return false;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        _visibleNavigators[id] = Navigator.of(ctx, rootNavigator: true);
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
            if (payload != null && payload.isNotEmpty && onOpenPayload != null)
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onOpenPayload!(payload);
                },
                child: const Text('查看'),
              ),
          ],
        );
      },
    ).whenComplete(() {
      _visibleNavigators.remove(id);
      _visibleDialogSignatures.remove(id);
      _visibleDialogIds.remove(id);
    });
    return true;
  }

  String _popupSignature({
    required String title,
    required String body,
    required String? payload,
  }) {
    return '$title\n$body\n${payload ?? ''}';
  }

  bool _reserveVisibleDialog({required int id, required String signature}) {
    final now = DateTime.now();
    _recentVisibleDialogSignatures.removeWhere(
      (_, at) => now.difference(at) > _visiblePopupDuplicateWindow,
    );
    if (_visibleDialogIds.contains(id)) return false;
    if (_visibleDialogSignatures.containsValue(signature)) return false;
    final lastShownAt = _recentVisibleDialogSignatures[signature];
    if (lastShownAt != null &&
        now.difference(lastShownAt) <= _visiblePopupDuplicateWindow) {
      return false;
    }
    _visibleDialogIds.add(id);
    _visibleDialogSignatures[id] = signature;
    _recentVisibleDialogSignatures[signature] = now;
    return true;
  }

  static bool _defaultIsForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }
}
