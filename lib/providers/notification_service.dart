import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/achievements.dart';
import '../core/brand_strings.dart';
import '../services/desktop_notification.dart';
import '../services/local_notifications.dart';
import '../services/reminder_sinks.dart';

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

/// NotificationService —— 推送通道（`duoyi_general`，`Importance.high`）。
///
/// 本服务**只**处理「系统通知」语义的发送：番茄钟结束、休息结束、纪念日提醒、
/// 成就解锁等轻提示；对应设计文档 §2.4 的 push 通道（R4.1 / R4.2）。
///
/// 闹钟语义（任务到期 / 目标派发 / 习惯闹钟，需要全屏 + 震动 + 精准唤醒）由
/// `AlarmService` 承担（Task 13）；`ReminderScheduler` 是协调器，
/// 按 `ReminderConfig.kind` 分发到本服务或 `AlarmService`（Task 14）。
///
/// 设计目的是在模型上把「消息」与「闹钟」两条路径彻底分离：
///   * `duoyi_general` → 轻推、可被系统折叠、不唤屏；
///   * `duoyi_alarm`   → 强提醒、全屏 intent、震动序列、`Importance.max`。
///
/// 所以本文件中所有对 `LocalNotifications` 的调用都**必须且仅能**使用
/// `channelId: 'duoyi_general'`；任何涉及 `duoyi_alarm` 的调度都应经 `AlarmService`。
class NotificationService extends ChangeNotifier
    implements ReminderNotificationSink {
  static const _kHistoryKey = 'duoyi_notif_history';

  /// 本服务使用的唯一通道 id。
  static const String channelId = 'duoyi_general';

  Timer? _pomodoroNotificationTimer;
  int _pendingNotifications = 0;
  final List<NotificationItem> _history = [];
  final DesktopNotification _desktop = DesktopNotification();
  bool _desktopReady = false;
  BrandStrings _strings = BrandStrings.defaultBrand;

  int get pendingCount => _pendingNotifications;
  List<NotificationItem> get history => List.unmodifiable(_history);
  bool get desktopReady => _desktopReady;
  bool get permissionGranted => LocalNotifications.instance.permissionGranted;

  void setStrings(BrandStrings s) {
    _strings = s;
  }

  Future<void> init() async {
    await _desktop.init();
    _desktopReady = _desktop.isAvailable;
    // 初始化底层 plugin，其 init 会创建 Android 端的 duoyi_general 渠道
    // （Importance.high）与 duoyi_alarm 渠道（由 AlarmService 使用）。
    await LocalNotifications.instance.init();
    await _loadHistory();
    // 首次使用时尝试一次(用户可在偏好页再次申请)
    if (!LocalNotifications.instance.permissionGranted) {
      await LocalNotifications.instance.requestPermission();
    }
  }

  Future<bool> requestPermission() =>
      LocalNotifications.instance.requestPermission();

  /// 重新读取系统通知权限状态，并在状态变化时通知订阅者刷新 UI。
  Future<bool> refreshPermission() async {
    final before = permissionGranted;
    final granted = await LocalNotifications.instance.refreshPermission();
    if (before != granted) {
      notifyListeners();
    }
    return granted;
  }

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
        raw.map((e) {
          try {
            return NotificationItem.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        }).whereType<NotificationItem>(),
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
  // Public API — 所有路径统一使用 duoyi_general（Importance.high）。
  // ——————————————————————————————————————————————

  /// 立即推送一条自定义消息（push 通道）。
  ///
  /// 薄封装 `LocalNotifications.show`，固定 `duoyi_general` 渠道，便于
  /// `ReminderScheduler._dispatch(r.kind = push)` 等上游直接调用。
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await LocalNotifications.instance.show(
      id: id,
      title: title,
      body: body,
      channelId: channelId,
      payload: payload,
    );
  }

  /// 调度一次性 push 通知（`when` 为本地墙钟时间）。
  ///
  /// 这是对齐 Task 12 描述的通用 `scheduleOnce(id, title, body, when, payload)`
  /// 接口，专供 `ReminderScheduler` 路由 `kind = push` 的提醒使用。
  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (when.isBefore(DateTime.now())) return;
    await LocalNotifications.instance.scheduleOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      channelId: channelId,
      payload: payload,
    );
    _pendingNotifications++;
    notifyListeners();
  }

  /// 每日固定时间的 push 通知；可选 `weekdays`（1=Mon..7=Sun）限定。
  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    await LocalNotifications.instance.scheduleDaily(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      channelId: channelId,
      payload: payload,
    );
    _pendingNotifications++;
    notifyListeners();
  }

  /// 取消某个已调度的通知。
  @override
  Future<void> cancel(int id) async {
    await LocalNotifications.instance.cancel(id);
  }

  /// 取消全部已调度通知（push + alarm 都会被清；Task 14 前保留该行为，
  /// 之后由 `ReminderScheduler` 只清理本服务管辖的 id）。
  Future<void> cancelAll() async {
    await LocalNotifications.instance.cancelAll();
    _pendingNotifications = 0;
    notifyListeners();
  }

  Future<List<int>> pendingIds() => LocalNotifications.instance.pendingIds();

  // ——————————————————————————————————————————————
  // 便捷语义 API（语义化包装，全部走 push 通道）
  // ——————————————————————————————————————————————

  /// 调度一次性待办到期提醒（push 语义）。
  ///
  /// 注：按 R4.5，`ReminderConfig.kind = alarm` 的任务到期应改走 `AlarmService`，
  /// 相关路由在 Task 14 `ReminderScheduler._dispatch` 中统一处理。
  Future<void> scheduleTodoReminder({
    required String todoId,
    required String title,
    required DateTime when,
  }) async {
    if (when.isBefore(DateTime.now())) return;
    await LocalNotifications.instance.scheduleOnce(
      id: _idFor('todo_$todoId'),
      title: _strings.notifTodoDueTitle,
      body: title,
      when: when,
      channelId: channelId,
      payload: 'duoyi://tab/todo',
    );
    _pendingNotifications++;
    notifyListeners();
  }

  @override
  Future<void> cancelTodoReminder(String todoId) async {
    await LocalNotifications.instance.cancel(_idFor('todo_$todoId'));
  }

  /// 每日习惯提醒（push 语义；可选指定 weekdays: 1..7）。
  ///
  /// 注：按 R4.5，`ReminderConfig.kind = alarm` 的习惯闹钟应改走 `AlarmService`，
  /// 相关路由在 Task 14 `ReminderScheduler._dispatch` 中统一处理。
  @override
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
      channelId: channelId,
      payload: 'duoyi://tab/habit',
    );
    _pendingNotifications++;
    notifyListeners();
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    await LocalNotifications.instance.cancel(_idFor('habit_$habitId'));
  }

  /// 纪念日/生日到达前 N 天提醒（push 语义）。
  ///
  /// TODO(task-13): 用户若把某个纪念日标为「强提醒」（kind=alarm），
  /// 应由 `AlarmService.scheduleFullScreen` 承担；本方法保留 push 语义作为
  /// 默认回退，直到 Task 14 `ReminderScheduler` 按 `ReminderConfig.kind` 完成分发。
  @override
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
      channelId: channelId,
      payload: 'duoyi://tab/calendar',
    );
    _pendingNotifications++;
    notifyListeners();
  }

  @override
  Future<void> cancelAnniversary(String annId) async {
    await LocalNotifications.instance.cancel(_idFor('anni_$annId'));
  }

  /// 立即发送一条番茄钟完成通知（push 语义；番茄钟结束属 R4 的 push 事件）。
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
      channelId: channelId,
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

  /// 番茄钟休息结束提示（push 语义）。
  void notifyBreakComplete() {
    final body = _strings.notifBreakDoneBody;
    final title = _strings.notifBreakDoneTitle;
    _desktopShow(title, body);
    LocalNotifications.instance.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
      channelId: channelId,
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

  /// 发送一条自定义通知（测试用；走 push 通道）。
  Future<void> sendTest() async {
    await LocalNotifications.instance.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: '多仪 · 测试通知',
      body: '如果你看到这条，通知已经正常工作。',
      channelId: channelId,
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

  void notifyAchievementUnlocked(Achievement achievement) {
    final title = '成就解锁：${achievement.title}';
    final body = achievement.description;
    _desktopShow(title, body);
    LocalNotifications.instance.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
      channelId: channelId,
      payload: 'duoyi://tab/mine',
    );
    _addToHistory(
      NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        scheduledTime: DateTime.now(),
        type: NotificationType.general,
        relatedId: achievement.id,
      ),
    );
    notifyListeners();
  }

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
