import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/achievements.dart';
import '../core/brand_strings.dart';
import '../core/notification_history_policy.dart';
import '../models/location_reminder.dart';
import '../providers/location_reminder_provider.dart';
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

enum NotificationType { todo, habit, pomodoro, anniversary, general, location }

/// NotificationService —— 推送通道（`duoyi_general_alerts_v9`，`Importance.high`）。
///
/// 本服务**只**处理「系统通知」语义的发送：番茄钟结束、休息结束、纪念日提醒、
/// 成就解锁等轻提示；对应设计文档 §2.4 的 push 通道（R4.1 / R4.2）。
///
/// 闹钟语义（任务到期 / 目标派发 / 习惯闹钟，需要全屏 + 震动 + 精准唤醒）由
/// `AlarmService` 承担（Task 13）；`ReminderScheduler` 是协调器，
/// 按 `ReminderConfig.kind` 分发到本服务或 `AlarmService`（Task 14）。
///
/// 设计目的是在模型上把「消息」与「闹钟」两条路径彻底分离：
///   * `duoyi_general_alerts_v9` → 普通提醒，柔和提示音、震动并尽量弹出横幅；
///   * `duoyi_alarm_fullscreen_v6` → 强提醒，全屏 intent、震动序列、`Importance.max`。
///
/// 所以本文件中普通提醒对 `LocalNotifications` 的调用都固定使用 [channelId]；
/// 任何涉及强提醒的调度都应经 `AlarmService`。
class NotificationService extends ChangeNotifier
    implements ReminderNotificationSink {
  static const _kHistoryKey = 'duoyi_notif_history';
  static const _kHistorySeenKey = 'duoyi_notif_history_seen_at';

  /// 本服务使用的唯一通道 id。
  ///
  /// Android 通知渠道创建后，声音/重要性由系统固定，后续代码修改不会覆盖
  /// 用户手机上的旧渠道。v9 更新默认轻铃提示音，并清理旧渠道。
  static const String channelId = 'duoyi_general_alerts_v9';
  static const Set<String> legacyChannelIds = <String>{
    'duoyi_general_alerts_v2',
    'duoyi_general_alerts_v3',
    'duoyi_general_alerts_v4',
    'duoyi_general_alerts_v5',
    'duoyi_general_alerts_v6',
    'duoyi_general_alerts_v7',
    'duoyi_general_alerts_v8',
  };

  Timer? _pomodoroNotificationTimer;
  int _pendingNotifications = 0;
  int _historyLimit = NotificationHistoryPolicy.defaultLimit;
  final List<NotificationItem> _history = [];
  DateTime? _historyLastSeenAt;
  final DesktopNotification _desktop = DesktopNotification();
  bool _desktopReady = false;
  BrandStrings _strings = BrandStrings.defaultBrand;

  int get pendingCount => _pendingNotifications;
  int get historyCount => _history.length;
  int get historyLimit => _historyLimit;
  List<NotificationItem> get history => List.unmodifiable(_history);
  bool get hasUnreadHistory =>
      _history.isNotEmpty &&
      (_historyLastSeenAt == null ||
          _history.first.scheduledTime.isAfter(_historyLastSeenAt!));
  bool get desktopReady => _desktopReady;
  bool get permissionGranted => LocalNotifications.instance.permissionGranted;

  void setStrings(BrandStrings s) {
    _strings = s;
  }

  Future<void> init() async {
    await _desktop.init();
    _desktopReady = _desktop.isAvailable;
    // 初始化底层 plugin，其 init 会创建 Android 端的普通提醒渠道与强提醒渠道。
    await LocalNotifications.instance.init();
    await _loadHistory();
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
      _history.take(_historyLimit).map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> _saveHistorySeen() async {
    final p = await SharedPreferences.getInstance();
    final seenAt = _historyLastSeenAt;
    if (seenAt == null) {
      await p.remove(_kHistorySeenKey);
    } else {
      await p.setString(_kHistorySeenKey, seenAt.toIso8601String());
    }
  }

  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    _historyLimit = NotificationHistoryPolicy.normalize(
      p.getInt(NotificationHistoryPolicy.preferenceKey),
    );
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
    if (_history.length > _historyLimit) {
      _history.removeRange(_historyLimit, _history.length);
      await _saveHistory();
    }
    _historyLastSeenAt = DateTime.tryParse(p.getString(_kHistorySeenKey) ?? '');
    notifyListeners();
  }

  @visibleForTesting
  Future<void> loadHistoryForTest() => _loadHistory();

  @visibleForTesting
  void addHistoryForTest(NotificationItem item) => _addToHistory(item);

  Future<void> setHistoryLimit(int value) async {
    final next = NotificationHistoryPolicy.normalize(value);
    if (_historyLimit == next && _history.length <= next) return;
    _historyLimit = next;
    if (_history.length > _historyLimit) {
      _history.removeRange(_historyLimit, _history.length);
      await _saveHistory();
    }
    notifyListeners();
  }

  void markHistorySeen() {
    _historyLastSeenAt = _history.isEmpty
        ? DateTime.now()
        : _history.first.scheduledTime;
    unawaited(_saveHistorySeen());
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

  void _showImmediate({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) {
    // ignore: discarded_futures
    LocalNotifications.instance
        .show(
          id: id,
          title: title,
          body: body,
          channelId: channelId,
          payload: payload,
        )
        .catchError((Object e, StackTrace st) {
          debugPrint(
            '[NotificationService] immediate notification failed: $e\n$st',
          );
        });
  }

  // ——————————————————————————————————————————————
  // Public API — 普通提醒路径统一使用 channelId。
  // ——————————————————————————————————————————————

  /// 立即推送一条自定义消息（push 通道）。
  ///
  /// 薄封装 `LocalNotifications.show`，固定普通提醒渠道，便于
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
    _addToHistory(
      NotificationItem(
        id: id.toString(),
        title: title,
        body: body,
        scheduledTime: DateTime.now(),
        type: NotificationType.general,
      ),
    );
    notifyListeners();
  }

  /// 稍后提醒（Snooze, Task T-12）。
  ///
  /// 取消现有 [id] 上的调度，并在 [delay] 之后重新调度同一条提醒。
  /// 上层（深链处理或通知 action）应当传入原 payload 以保留跳转上下文。
  Future<void> snooze({
    required int id,
    required String title,
    required String body,
    required Duration delay,
    String? payload,
  }) async {
    await LocalNotifications.instance.cancel(id);
    final when = DateTime.now().add(delay);
    await LocalNotifications.instance.scheduleOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      channelId: channelId,
      payload: payload,
    );
    _addToHistory(
      NotificationItem(
        id: id.toString(),
        title: title,
        body: body,
        scheduledTime: when,
        type: NotificationType.general,
      ),
    );
    notifyListeners();
  }

  /// 通过 deep-link `duoyi://snooze/{id}?delay={minutes}` 触发的快捷路径。
  Future<void> handleSnoozeDeepLink(Uri uri) async {
    if (uri.host != 'snooze') return;
    final idStr = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    final id = int.tryParse(idStr ?? '');
    if (id == null) return;
    final minutes = int.tryParse(uri.queryParameters['delay'] ?? '5') ?? 5;
    final title = uri.queryParameters['title'] ?? '稍后提醒';
    final body = uri.queryParameters['body'] ?? '';
    final payload = uri.queryParameters['payload'];
    await snooze(
      id: id,
      title: title,
      body: body,
      delay: Duration(minutes: minutes),
      payload: payload,
    );
  }

  /// 上层（通知中心、深链处理或通知 action）调用此通用方法重新调度提醒。
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
    _addToHistory(
      NotificationItem(
        id: id.toString(),
        title: title,
        body: body,
        scheduledTime: when,
        type: NotificationType.general,
      ),
    );
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
    _addToHistory(
      NotificationItem(
        id: id.toString(),
        title: title,
        body: body,
        scheduledTime: DateTime.now(),
        type: NotificationType.general,
      ),
    );
    notifyListeners();
  }

  /// 取消某个已调度的通知。
  @override
  Future<void> cancel(int id) async {
    await LocalNotifications.instance.cancel(id);
    if (_pendingNotifications > 0) {
      _pendingNotifications--;
      notifyListeners();
    }
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

  void notifyLocationReminderHit(LocationReminderHit hit) {
    final reminder = hit.reminder;
    final direction = hit.triggeredBy == LocationTrigger.enter ? '到达' : '离开';
    final title = '位置提醒：${reminder.title}';
    final note = reminder.note?.trim();
    final body = note == null || note.isEmpty
        ? '已$direction ${reminder.radiusMeters.toStringAsFixed(0)} 米提醒范围'
        : '已$direction提醒范围 · $note';
    final payload = _locationPayload(reminder);
    final notificationId = _idFor(
      'location_${reminder.id}_${hit.fix.at.millisecondsSinceEpoch}',
    );

    _desktopShow(title, body);
    _showImmediate(
      id: notificationId,
      title: title,
      body: body,
      payload: payload,
    );
    _addToHistory(
      NotificationItem(
        id: notificationId.toString(),
        title: title,
        body: body,
        scheduledTime: hit.fix.at,
        type: NotificationType.location,
        relatedId: reminder.id,
      ),
    );
    notifyListeners();
  }

  String _locationPayload(LocationReminder reminder) {
    final linkedId = reminder.linkedId;
    if (linkedId != null && linkedId.isNotEmpty) {
      if (reminder.linkedType == 'todo') return 'duoyi://todo/$linkedId';
      if (reminder.linkedType == 'goal') return 'duoyi://goal/$linkedId';
    }
    return 'duoyi://location/${reminder.id}';
  }

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
    _addToHistory(
      NotificationItem(
        id: _idFor('todo_$todoId').toString(),
        title: _strings.notifTodoDueTitle,
        body: title,
        scheduledTime: when,
        type: NotificationType.todo,
        relatedId: todoId,
      ),
    );
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
      payload: 'duoyi://habit/$habitId?confirm=1',
    );
    _pendingNotifications++;
    _addToHistory(
      NotificationItem(
        id: _idFor('habit_$habitId').toString(),
        title: _strings.notifHabitRemindTitle,
        body: '别忘了: $habitName',
        scheduledTime: DateTime.now(),
        type: NotificationType.habit,
        relatedId: habitId,
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    await LocalNotifications.instance.cancel(_idFor('habit_$habitId'));
  }

  /// 纪念日/生日到达前 N 天提醒（push 语义）。
  ///
  /// alarm kind 路由已由 `ReminderScheduler.syncAnniversaries` 完成：
  /// 当 `Anniversary.reminderKind == alarm` 时调用 `AlarmService`；
  /// 本方法仅处理 push 回退路径。
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
    _addToHistory(
      NotificationItem(
        id: _idFor('anni_$annId').toString(),
        title: '📅 纪念日提醒',
        body: daysBefore == 0 ? '今天是 $title' : '$daysBefore 天后是 $title',
        scheduledTime: remindAt,
        type: NotificationType.anniversary,
        relatedId: annId,
      ),
    );
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
    _showImmediate(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: _strings.notifPomodoroDoneTitle,
      body: body,
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
    _showImmediate(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
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

  /// 发送一条普通测试通知。
  ///
  /// 偏好设置里的默认测试只验证普通通知渠道是否可见、可响铃；强提醒闹钟
  /// 必须由用户在提醒规则中明确选择，避免误触后突然全屏响铃。
  Future<void> sendTest() async {
    await LocalNotifications.instance.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: '多仪 · 通知测试',
      body: '这是一条普通提醒测试。如果没有声音，请检查“通知提醒”渠道声音设置。',
      channelId: channelId,
      payload: 'duoyi://tab/mine',
    );
    _addToHistory(
      NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '测试通知',
        body: '已发送普通通知测试。',
        scheduledTime: DateTime.now(),
        type: NotificationType.general,
      ),
    );
    await _saveHistory();
    notifyListeners();
  }

  Future<void> sendScheduledTest({
    Duration delay = const Duration(minutes: 1),
  }) async {
    final when = DateTime.now().add(delay);
    await LocalNotifications.instance.scheduleOnce(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: '多仪 · 定时通知测试',
      body: '如果到点能收到普通提醒，定时通知调度正常。',
      when: when,
      channelId: channelId,
      payload: 'duoyi://tab/mine',
    );
    _pendingNotifications++;
    _addToHistory(
      NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '定时测试通知',
        body:
            '计划在 ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')} 触发普通通知',
        scheduledTime: when,
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
    _showImmediate(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
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
    if (_history.length > _historyLimit) {
      _history.removeRange(_historyLimit, _history.length);
    }
    _saveHistory();
  }

  Future<void> clearHistory() async {
    _history.clear();
    _historyLastSeenAt = DateTime.now();
    await _saveHistory();
    await _saveHistorySeen();
    notifyListeners();
  }

  @override
  void dispose() {
    _pomodoroNotificationTimer?.cancel();
    _desktop.dispose();
    super.dispose();
  }
}
