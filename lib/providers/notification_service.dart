import 'dart:async';
import 'package:flutter/material.dart';
import '../core/brand_strings.dart';
import '../services/desktop_notification.dart';

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final NotificationType type;
  final String? relatedId;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    required this.type,
    this.relatedId,
  });
}

enum NotificationType { todo, habit, pomodoro }

class NotificationService extends ChangeNotifier {
  Timer? _pomodoroNotificationTimer;
  int _pendingNotifications = 0;
  final List<NotificationItem> _history = [];
  final DesktopNotification _desktop = DesktopNotification();
  bool _desktopReady = false;
  BrandStrings _strings = BrandStrings.re0;

  int get pendingCount => _pendingNotifications;
  List<NotificationItem> get history => _history;
  bool get desktopReady => _desktopReady;

  void setStrings(BrandStrings s) {
    _strings = s;
  }

  Future<void> init() async {
    await _desktop.init();
    _desktopReady = _desktop.isAvailable;
  }

  void _send(String title, String body) {
    if (_desktopReady) {
      _desktop.notify(summary: title, body: body);
    }
  }

  void scheduleTodoReminder(String todoTitle, DateTime dueDate) {
    final delay = dueDate.difference(DateTime.now());
    if (delay.isNegative) return;
    _pendingNotifications++;
    notifyListeners();

    Timer(delay, () {
      _pendingNotifications--;
      _send(_strings.notifTodoDueTitle, '"$todoTitle" 已到期');
      _addToHistory(NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _strings.notifTodoDueTitle,
        body: '"$todoTitle" 已到期',
        scheduledTime: dueDate,
        type: NotificationType.todo,
      ));
      notifyListeners();
    });
  }

  void scheduleHabitReminder(String habitName, TimeOfDay time) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    _pendingNotifications++;
    notifyListeners();

    Timer(scheduled.difference(now), () {
      _pendingNotifications--;
      _send(_strings.notifHabitRemindTitle, '别忘了: $habitName');
      _addToHistory(NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _strings.notifHabitRemindTitle,
        body: '别忘了: $habitName',
        scheduledTime: scheduled,
        type: NotificationType.habit,
      ));
      notifyListeners();
    });
  }

  void notifyPomodoroComplete({String? taskName}) {
    _pomodoroNotificationTimer?.cancel();
    final body = taskName != null && taskName.isNotEmpty
        ? '"$taskName" — ${_strings.notifPomodoroDoneBody}'
        : _strings.notifPomodoroDoneBody;
    _send(_strings.notifPomodoroDoneTitle, body);
    _addToHistory(NotificationItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _strings.notifPomodoroDoneTitle,
      body: body,
      scheduledTime: DateTime.now(),
      type: NotificationType.pomodoro,
    ));
    notifyListeners();
  }

  void notifyBreakComplete() {
    _send(_strings.notifBreakDoneTitle, _strings.notifBreakDoneBody);
    _addToHistory(NotificationItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _strings.notifBreakDoneTitle,
      body: _strings.notifBreakDoneBody,
      scheduledTime: DateTime.now(),
      type: NotificationType.pomodoro,
    ));
    notifyListeners();
  }

  void _addToHistory(NotificationItem item) {
    _history.insert(0, item);
    if (_history.length > 50) _history.removeLast();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _pomodoroNotificationTimer?.cancel();
    _desktop.dispose();
    super.dispose();
  }
}