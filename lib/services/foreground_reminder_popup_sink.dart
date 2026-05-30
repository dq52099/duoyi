import 'dart:async';

import 'package:flutter/material.dart';

import 'reminder_sinks.dart';

typedef ReminderPopupContextGetter = BuildContext? Function();
typedef ReminderPopupPayloadOpener = void Function(String payload);

class ForegroundReminderPopupSink implements ReminderPopupSink {
  static const Duration _visiblePopupDuplicateWindow = Duration(seconds: 3);

  final ReminderPopupContextGetter contextGetter;
  final ReminderPopupPayloadOpener? onOpenPayload;
  final Map<int, Timer> _timers = {};
  final Set<int> _visibleDialogIds = <int>{};
  final Map<String, DateTime> _recentVisibleDialogSignatures =
      <String, DateTime>{};
  final Map<int, String> _visibleDialogSignatures = <int, String>{};
  final Map<int, NavigatorState> _visibleNavigators = <int, NavigatorState>{};

  ForegroundReminderPopupSink({
    required this.contextGetter,
    this.onOpenPayload,
  });

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
    _timers[id] = Timer(delay, () {
      _timers.remove(id);
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
    void scheduleNext() {
      final next = _nextOccurrence(hour, minute, weekdays);
      _timers[id] = Timer(next.difference(DateTime.now()), () {
        _show(id: id, title: title, body: body, payload: payload);
        scheduleNext();
      });
    }

    scheduleNext();
  }

  @override
  Future<void> cancel(int id) async {
    _timers.remove(id)?.cancel();
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

  void _show({
    required int id,
    required String title,
    required String body,
    required String? payload,
  }) {
    final context = contextGetter();
    if (context == null || !context.mounted) return;
    final signature = _popupSignature(
      title: title,
      body: body,
      payload: payload,
    );
    if (!_reserveVisibleDialog(id: id, signature: signature)) return;
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
}
