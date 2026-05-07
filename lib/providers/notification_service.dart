import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/brand_strings.dart';
import '../services/desktop_notification.dart';
import '../services/local_notifications.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'scheduledTime': scheduledTime.toIso8601String(),
        'type': type.index,
        'relatedId': relatedId,
      };

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        scheduledTime: DateTime.parse(j['scheduledTime']),
        type: NotificationType.values[(j['type'] as num?)?.toInt() ?? 0],
        relatedId: j['relatedId']?.toString(),
      );
}

enum NotificationType { todo, habit, pomodoro, anniversary, general }

/// 前台/历史通知管理 + 调度本地通知(/闹钟)。
class NotificationService extends ChangeNotifier {
  static const _kHistoryKey = 'duoyi_notif_history';

  Timer? _pomodoroNotificationTimer;
  int _pendingNotifications = 0;
  final List<NotificationItem> _history = [];
  final DesktopNotification _desktop = DesktopNotification();
  bool _desktopReady = false;
  BrandStrings _strings = BrandStrings.defaultBrand;

  int get pendingCount => _pendingNotifications;
  List<NotificationItem> get history => List.unmodifiable(_history);
  bool get desktopReady => _desktopReady;
  bool get permissionGranted =>
      LocalNotifications.instance.permissionGranted;

  void setStrings(BrandStrings s) {
    _strings = s;
  }

  Future<void> init() async {
    await _desktop.init();
    _desktopReady = _desktop.isAvailable;
    await LocalNotifications.instance.init();
    await _loadHistory();
    // 首次使用时尝试一次(用户可在偏好页再次申请)
    if (!LocalNotifications.instance.permissionGranted) {
      await LocalNotifications.instance.requestPermission();
    }
  }

  Future<bool> requestPermission() =>
      LocalNotifications.instance.requestPermission();

  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kHistoryKey,
      _history.take(50).map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kHistoryKey) ?? const [];
    _history
      ..clear()
      ..addAll(
        raw
            .map((e) {
              try {
                return NotificationItem.fromJson(jsonDecode(e));
              } catch (_) {
                return null;
              }
            })
            .whereType<NotificationItem>(),
      );
    notifyListeners();
  }

  int _idFor(String key) {
    // 从字符串 id 生成稳定 int(用于 flutter_local_notifications)
    int h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  void _desktopShow(String title, String body) {
    if (_desktopReady) _desktop.notify(summary: title, body: body);
  }

  // ——————————————————————————————————————————————
  // Public API
  // ——————————————————————————————————————————————

  /// 调度一次性待办到期提醒
  Future<void> scheduleTodoReminder({
    required String todoId,
    required String title,
    required DateTime when,
  }) async {
    if (when.isBefore(DateTime.now())) return;
    await LocalNotifications.instance.scheduleOnce(
      id: _idFor('todo_$todoId'),
      title: _strings.notifTodoDueTitle,
      body: '$title',
      when: when,
      channelId: 'duoyi_general',
      payload: 'duoyi://tab/todo',
    );
    _pendingNotifications++;
    notifyListeners();
  }

  Future<void> cancelTodoReminder(String todoId) async {
    await LocalNotifications.instance.cancel(_idFor('todo_$todoId'));
  }

  /// 每日习惯提醒 (可选指定 weekdays: 1..7)
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {
    await LocalNotifications.instance.scheduleDaily(
      id: _idFor('habit_$habitId'),
      title: _strings.notifHabitRemindTitle,
      body: '别忘了: $habitName',
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      channelId: 'duoyi_general',
      payload: 'duoyi://tab/habit',
    );
    _pendingNotifications++;
    notifyListeners();
  }

  Future<void> cancelHabitReminder(String habitId) async {
    await LocalNotifications.instance.cancel(_idFor('habit_$habitId'));
  }

  /// 纪念日/生日到达前 N 天提醒
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate, // 当日公历
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) async {
    final remindAt = DateTime(
      whenDate.year,
      whenDate.month,
      whenDate.day,
      hour,
      minute,
    ).subtract(Duration(days: daysBefore));
    if (remindAt.isBefore(DateTime.now())) return;
    await LocalNotifications.instance.scheduleOnce(
      id: _idFor('anni_$annId'),
      title: '📅 纪念日提醒',
      body: daysBefore == 0 ? '今天是 $title' : '$daysBefore 天后是 $title',
      when: remindAt,
      channelId: 'duoyi_alarm',
      payload: 'duoyi://tab/calendar',
    );
  }

  Future<void> cancelAnniversary(String annId) async {
    await LocalNotifications.instance.cancel(_idFor('anni_$annId'));
  }

  /// 立即发送一条番茄钟完成通知(已在执行中，无需调度)
  void notifyPomodoroComplete({String? taskName}) {
    _pomodoroNotificationTimer?.cancel();
    final body = taskName != null && taskName.isNotEmpty
        ? '"$taskName" — ${_strings.notifPomodoroDoneBody}'
        : _strings.notifPomodoroDoneBody;
    _desktopShow(_strings.notifPomodoroDoneTitle, body);
    LocalNotifications.instance.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: _strings.notifPomodoroDoneTitle,
      body: body,
      channelId: 'duoyi_alarm',
    );
    _addToHistory(
      NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _strings.notifPomodoroDoneTitle,
        body: body,
        scheduledTime: DateTime.now(),
        type: NotificationType.pomodoro,
      ),
    );
    notifyListeners();
  }

  void notifyBreakComplete() {
    final body = _strings.notifBreakDoneBody;
    final title = _strings.notifBreakDoneTitle;
    _desktopShow(title, body);
    LocalNotifications.instance.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
      channelId: 'duoyi_alarm',
    );
    _addToHistory(
      NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        scheduledTime: DateTime.now(),
        type: NotificationType.pomodoro,
      ),
    );
    notifyListeners();
  }

  /// 发送一条自定义通知(测试用)
  Future<void> sendTest() async {
    await LocalNotifications.instance.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: '多仪 · 测试通知',
      body: '如果你看到这条，通知已经正常工作。',
      channelId: 'duoyi_alarm',
    );
    _addToHistory(
      NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '测试通知',
        body: '如果你看到这条，通知已经正常工作。',
        scheduledTime: DateTime.now(),
        type: NotificationType.general,
      ),
    );
    await _saveHistory();
    notifyListeners();
  }

  Future<void> cancelAll() async {
    await LocalNotifications.instance.cancelAll();
    _pendingNotifications = 0;
    notifyListeners();
  }

  Future<List<int>> pendingIds() =>
      LocalNotifications.instance.pendingIds();

  void _addToHistory(NotificationItem item) {
    _history.insert(0, item);
    if (_history.length > 50) _history.removeLast();
    _saveHistory();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  @override
  void dispose() {
    _pomodoroNotificationTimer?.cancel();
    _desktop.dispose();
    super.dispose();
  }
}
