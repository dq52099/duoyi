import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/achievements.dart';
import '../core/brand_strings.dart';
import '../core/notification_history_policy.dart';
import '../models/location_reminder.dart';
import '../models/goal.dart' show ReminderKind;
import '../providers/location_reminder_provider.dart';
import '../services/local_notifications.dart';
import '../services/notification_permission_exception.dart';
import '../services/notification_settings.dart';
import '../services/reminder_sinks.dart';

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final NotificationType type;
  final String? relatedId;
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    required this.type,
    this.relatedId,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'scheduledTime': scheduledTime.toIso8601String(),
    'type': type.index,
    'relatedId': relatedId,
    'isRead': isRead,
  };

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
    id: j['id'].toString(),
    title: (j['title'] ?? '').toString(),
    body: (j['body'] ?? '').toString(),
    scheduledTime: DateTime.parse(j['scheduledTime']),
    type: NotificationType.values[(j['type'] as num?)?.toInt() ?? 0],
    relatedId: j['relatedId']?.toString(),
    isRead: j['isRead'] == true || j['read'] == true,
  );

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      type: type,
      relatedId: relatedId,
      isRead: isRead ?? this.isRead,
    );
  }
}

enum NotificationType { todo, habit, pomodoro, anniversary, general, location }

class NotificationScheduleIssue {
  final String title;
  final String message;
  final DateTime happenedAt;
  final DateTime? scheduledTime;
  final String? relatedId;
  final bool blocking;

  const NotificationScheduleIssue({
    required this.title,
    required this.message,
    required this.happenedAt,
    this.scheduledTime,
    this.relatedId,
    this.blocking = true,
  });
}

/// NotificationService —— 推送通道（`duoyi_general_alerts_v18`，`Importance.high`）。
///
/// 本服务**只**处理「系统通知」语义的发送：番茄钟结束、休息结束、纪念日提醒、
/// 成就解锁等轻提示；对应设计文档 §2.4 的 push 通道（R4.1 / R4.2）。
///
/// 闹钟语义（任务到期 / 目标派发 / 习惯闹钟，需要全屏 + 震动 + 精准唤醒）由
/// `AlarmService` 承担（Task 13）；`ReminderScheduler` 是协调器，
/// 按 `ReminderConfig.kind` 分发到本服务或 `AlarmService`（Task 14）。
///
/// 设计目的是在模型上把「消息」与「闹钟」两条路径彻底分离：
///   * `duoyi_general_alerts_v18` → 普通提醒，柔和提示音、震动并尽量显示横幅；
///   * `duoyi_alarm_fullscreen_v18` → 强提醒，柔和内置铃声、停止按钮、`Importance.max`。
///
/// 所以本文件中普通提醒对 `LocalNotifications` 的调用都固定使用 [channelId]；
/// 任何涉及强提醒的调度都应经 `AlarmService`。
class NotificationService extends ChangeNotifier
    implements
        ReminderNotificationSink,
        ReminderPendingSink,
        ReminderScheduleIssueSink,
        ReminderScheduleIssueClearSink {
  static const _kHistoryKey = 'duoyi_notif_history';
  static const _kHistorySeenKey = 'duoyi_notif_history_seen_at';
  static const int _scheduledPopupDiagnosticNotificationId = 919005;
  static const int _scheduledAlarmDiagnosticNotificationId = 919006;
  static const int _scheduledFullScreenDiagnosticNotificationId = 919007;
  static const Set<int> _diagnosticNotificationIds = <int>{
    LocalNotifications.scheduledDiagnosticNotificationId,
    _scheduledPopupDiagnosticNotificationId,
    _scheduledAlarmDiagnosticNotificationId,
    _scheduledFullScreenDiagnosticNotificationId,
  };

  /// 本服务使用的唯一通道 id。
  ///
  /// Android 通知渠道创建后，声音/重要性由系统固定，后续代码修改不会覆盖
  /// 用户手机上的旧渠道。v18 重新创建柔和晨铃渠道，并清理旧渠道。
  static const String channelId = 'duoyi_general_alerts_v18';
  static const Set<String> legacyChannelIds = <String>{
    'duoyi_general_alerts_v2',
    'duoyi_general_alerts_v3',
    'duoyi_general_alerts_v4',
    'duoyi_general_alerts_v5',
    'duoyi_general_alerts_v6',
    'duoyi_general_alerts_v7',
    'duoyi_general_alerts_v8',
    'duoyi_general_alerts_v9',
    'duoyi_general_alerts_v10',
    'duoyi_general_alerts_v11',
    'duoyi_general_alerts_v12',
    'duoyi_general_alerts_v13',
    'duoyi_general_alerts_v14',
    'duoyi_general_alerts_v15',
    'duoyi_general_alerts_v16',
    'duoyi_general_alerts_v17',
  };
  static const Duration _scheduleIssueDuplicateWindow = Duration(seconds: 30);

  Timer? _pomodoroNotificationTimer;
  int _pendingNotifications = 0;
  int _historyLimit = NotificationHistoryPolicy.defaultLimit;
  final List<NotificationItem> _history = [];
  DateTime? _historyLastSeenAt;
  NotificationScheduleIssue? _lastScheduleIssue;
  String? _lastScheduleIssueSignature;
  DateTime? _lastScheduleIssueRecordedAt;
  BrandStrings _strings = BrandStrings.defaultBrand;
  int _storageGeneration = 0;

  int get pendingCount => _pendingNotifications;
  int get historyCount => _history.length;
  int get historyLimit => _historyLimit;
  List<NotificationItem> get history => List.unmodifiable(_history);
  int get unreadCount => _history.where((item) => !item.isRead).length;
  bool get hasUnreadHistory => unreadCount > 0;
  NotificationScheduleIssue? get lastScheduleIssue => _lastScheduleIssue;
  bool get permissionGranted => LocalNotifications.instance.permissionGranted;

  void setStrings(BrandStrings s) {
    _strings = s;
  }

  Future<void> init() async {
    // 初始化底层 plugin，其 init 会创建 Android 端的普通提醒渠道与强提醒渠道。
    try {
      await LocalNotifications.instance.init();
    } catch (e, st) {
      debugPrint(
        '[NotificationService] local notification init failed: $e\n$st',
      );
      _recordScheduleIssue(
        title: '提醒注册初始化失败',
        message: '系统通知初始化失败，提醒暂时无法注册。请检查通知权限、通知渠道和系统后台限制后重新保存提醒。($e)',
      );
    }
    await _loadHistory();
  }

  Future<bool> requestPermission() async {
    final before = permissionGranted;
    final granted = await LocalNotifications.instance.requestPermission();
    var changed = before != granted;
    if (granted && _lastScheduleIssueIsPermissionOnly) {
      _clearScheduleIssueState();
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
    return granted;
  }

  void resetLocalState() {
    _storageGeneration++;
    _pomodoroNotificationTimer?.cancel();
    _pendingNotifications = 0;
    _historyLimit = NotificationHistoryPolicy.defaultLimit;
    _history.clear();
    _historyLastSeenAt = null;
    _clearScheduleIssueState();
    notifyListeners();
  }

  void clearScheduleIssue() {
    if (_lastScheduleIssue == null) return;
    _clearScheduleIssueState();
    notifyListeners();
  }

  @override
  void clearReminderScheduleIssue() {
    clearScheduleIssue();
  }

  void _clearScheduleIssueState() {
    _lastScheduleIssue = null;
    _lastScheduleIssueSignature = null;
    _lastScheduleIssueRecordedAt = null;
  }

  bool get _lastScheduleIssueIsPermissionOnly {
    final issue = _lastScheduleIssue;
    if (issue == null) return false;
    final text = '${issue.title}\n${issue.message}';
    return text.contains('通知权限未开启') ||
        text.contains('系统通知权限未开启') ||
        text.contains('系统通知未授权');
  }

  /// 重新读取系统通知权限状态，并在状态变化时通知订阅者刷新 UI。
  Future<bool> refreshPermission() async {
    final before = permissionGranted;
    final granted = await LocalNotifications.instance.refreshPermission();
    var changed = before != granted;
    if (granted && _lastScheduleIssueIsPermissionOnly) {
      _clearScheduleIssueState();
      changed = true;
    }
    if (changed) {
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
    final generation = _storageGeneration;
    final p = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    _historyLimit = NotificationHistoryPolicy.normalize(
      p.getInt(NotificationHistoryPolicy.preferenceKey),
    );
    _historyLastSeenAt = DateTime.tryParse(p.getString(_kHistorySeenKey) ?? '');
    final raw = p.getStringList(_kHistoryKey) ?? const [];
    _history
      ..clear()
      ..addAll(
        raw.map((e) {
          try {
            final decoded = jsonDecode(e);
            if (decoded is! Map<String, dynamic>) return null;
            final item = NotificationItem.fromJson(decoded);
            final hasReadState =
                decoded.containsKey('isRead') || decoded.containsKey('read');
            if (!hasReadState) {
              final seenAt = _historyLastSeenAt;
              if (seenAt != null && !item.scheduledTime.isAfter(seenAt)) {
                return item.copyWith(isRead: true);
              }
              return item;
            }
            return item;
          } catch (_) {
            return null;
          }
        }).whereType<NotificationItem>(),
      );
    if (generation != _storageGeneration) return;
    if (_history.length > _historyLimit) {
      _history.removeRange(_historyLimit, _history.length);
      await _saveHistory();
    }
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
    final nextSeenAt = _history.isEmpty
        ? (_historyLastSeenAt ?? DateTime.now())
        : _history.first.scheduledTime;
    final seenChanged = _historyLastSeenAt != nextSeenAt;
    _historyLastSeenAt = nextSeenAt;
    var changed = false;
    for (var i = 0; i < _history.length; i++) {
      if (!_history[i].isRead) {
        _history[i] = _history[i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (changed) {
      unawaited(_saveHistory());
    }
    if (seenChanged || changed) {
      unawaited(_saveHistorySeen());
      notifyListeners();
    }
  }

  Future<void> markHistoryItemRead(String id, {bool read = true}) async {
    final index = _history.indexWhere((item) => item.id == id);
    if (index < 0 || _history[index].isRead == read) return;
    _history[index] = _history[index].copyWith(isRead: read);
    _historyLastSeenAt = _latestReadTime();
    await _saveHistory();
    await _saveHistorySeen();
    notifyListeners();
  }

  Future<void> markAllHistoryRead() async {
    if (_history.isEmpty) {
      return;
    }
    final nextSeenAt = _history.first.scheduledTime;
    var changed = false;
    for (var i = 0; i < _history.length; i++) {
      if (!_history[i].isRead) {
        _history[i] = _history[i].copyWith(isRead: true);
        changed = true;
      }
    }
    final seenChanged = _historyLastSeenAt != nextSeenAt;
    _historyLastSeenAt = nextSeenAt;
    if (!changed && !seenChanged) return;
    if (!changed) {
      await _saveHistorySeen();
      notifyListeners();
      return;
    }
    await _saveHistory();
    await _saveHistorySeen();
    notifyListeners();
  }

  Future<void> markAllHistoryUnread() async {
    if (_history.isEmpty) return;
    var changed = false;
    for (var i = 0; i < _history.length; i++) {
      if (_history[i].isRead) {
        _history[i] = _history[i].copyWith(isRead: false);
        changed = true;
      }
    }
    if (!changed) return;
    _historyLastSeenAt = null;
    await _saveHistory();
    await _saveHistorySeen();
    notifyListeners();
  }

  DateTime? _latestReadTime() {
    DateTime? latest;
    for (final item in _history) {
      if (!item.isRead) continue;
      if (latest == null || item.scheduledTime.isAfter(latest)) {
        latest = item.scheduledTime;
      }
    }
    return latest;
  }

  int _idFor(String key) {
    // 从字符串 id 生成稳定 int(用于 flutter_local_notifications)
    int h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _avoidReservedNotificationId(h);
  }

  int _avoidReservedNotificationId(int id) {
    var next = id;
    while (LocalNotifications.reservedNotificationIds.contains(next) ||
        _diagnosticNotificationIds.contains(next)) {
      next = (next + 1) & 0x7fffffff;
    }
    return next;
  }

  int _ephemeralNotificationId() {
    return _avoidReservedNotificationId(
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
    );
  }

  void _recordScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {
    final now = DateTime.now();
    final signature =
        '$title\n$message\n${scheduledTime?.toIso8601String() ?? ''}\n'
        '${relatedId ?? ''}\n$blocking';
    final lastRecordedAt = _lastScheduleIssueRecordedAt;
    if (_lastScheduleIssueSignature == signature &&
        lastRecordedAt != null &&
        now.difference(lastRecordedAt) <= _scheduleIssueDuplicateWindow) {
      debugPrint('[NotificationService] duplicate schedule issue skipped');
      return;
    }
    _lastScheduleIssueSignature = signature;
    _lastScheduleIssueRecordedAt = now;
    _lastScheduleIssue = NotificationScheduleIssue(
      title: title,
      message: message,
      happenedAt: now,
      scheduledTime: scheduledTime,
      relatedId: relatedId,
      blocking: blocking,
    );
    debugPrint('[NotificationService] $title: $message');
    notifyListeners();
  }

  @override
  void recordReminderScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {
    _recordScheduleIssue(
      title: title,
      message: message,
      scheduledTime: scheduledTime,
      relatedId: relatedId,
      blocking: blocking,
    );
  }

  Future<bool> _ensureChannelReadyOrRecord({
    required String issueTitle,
    DateTime? scheduledTime,
    String? relatedId,
  }) async {
    try {
      await LocalNotifications.instance.init();
      final statuses = await NotificationSettings.notificationChannelStatuses(
        const [channelId],
      );
      final status = statuses?[channelId];
      if (status == null || !status.exists) return true;
      if (status.isBlocked) {
        _recordScheduleIssue(
          title: issueTitle,
          message: '普通提醒渠道已关闭，提醒已注册但到点可能不会显示。请在系统通知设置里开启“多仪 · 通知提醒”。',
          scheduledTime: scheduledTime,
          relatedId: relatedId,
          blocking: false,
        );
        return true;
      }
      if (status.isSilent) {
        _recordScheduleIssue(
          title: issueTitle,
          message: '普通提醒渠道声音已关闭，提醒已注册但到点可能无声。请在系统通知设置里恢复“多仪 · 通知提醒”的声音。',
          scheduledTime: scheduledTime,
          relatedId: relatedId,
          blocking: false,
        );
        return true;
      }
    } catch (e, st) {
      debugPrint(
        '[NotificationService] channel readiness probe failed: $e\n$st',
      );
      _recordScheduleIssue(
        title: issueTitle,
        message: '普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。($e)',
        scheduledTime: scheduledTime,
        relatedId: relatedId,
        blocking: false,
      );
    }
    return true;
  }

  Future<bool> _scheduleOnceOrRecord({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String issueTitle,
    String? payload,
    String? relatedId,
    bool requestIfNeeded = false,
  }) async {
    final now = DateTime.now();
    if (!when.isAfter(now)) {
      _recordScheduleIssue(
        title: issueTitle,
        message: '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
        scheduledTime: when,
        relatedId: relatedId,
      );
      return false;
    }
    final priorIssue = _lastScheduleIssue;
    if (!await _ensureChannelReadyOrRecord(
      issueTitle: issueTitle,
      scheduledTime: when,
      relatedId: relatedId,
    )) {
      return false;
    }
    final channelWarningRecorded =
        !identical(priorIssue, _lastScheduleIssue) &&
        _lastScheduleIssue?.blocking == false;
    try {
      await LocalNotifications.instance.scheduleOnce(
        id: id,
        title: title,
        body: body,
        when: when,
        channelId: channelId,
        payload: payload,
        requestIfNeeded: requestIfNeeded,
      );
      final granted = await LocalNotifications.instance.refreshPermission();
      if (!granted) {
        _recordScheduleIssue(
          title: issueTitle,
          message: '提醒已注册，但系统通知权限未开启，到点可能不会弹出。请开启通知权限后重新保存提醒。',
          scheduledTime: when,
          relatedId: relatedId,
        );
        return true;
      }
      if (_lastScheduleIssue != null && !channelWarningRecorded) {
        _clearScheduleIssueState();
        notifyListeners();
      }
      return true;
    } on NotificationPermissionDeniedException {
      _recordScheduleIssue(
        title: issueTitle,
        message: '系统通知权限未开启，提醒未注册。请开启通知权限后重新保存提醒。',
        scheduledTime: when,
        relatedId: relatedId,
      );
      return false;
    } catch (e, st) {
      debugPrint('[NotificationService] scheduleOnce failed: $e\n$st');
      _recordScheduleIssue(
        title: issueTitle,
        message: '系统通知注册失败，请检查通知权限、精确闹钟权限和系统通知渠道设置后重新保存提醒。($e)',
        scheduledTime: when,
        relatedId: relatedId,
      );
      return false;
    }
  }

  Future<bool> _scheduleDailyOrRecord({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String issueTitle,
    List<int>? weekdays,
    String? payload,
    String? relatedId,
  }) async {
    final priorIssue = _lastScheduleIssue;
    if (!await _ensureChannelReadyOrRecord(
      issueTitle: issueTitle,
      relatedId: relatedId,
    )) {
      return false;
    }
    final channelWarningRecorded =
        !identical(priorIssue, _lastScheduleIssue) &&
        _lastScheduleIssue?.blocking == false;
    try {
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
      final granted = await LocalNotifications.instance.refreshPermission();
      if (!granted) {
        _recordScheduleIssue(
          title: issueTitle,
          message: '重复提醒已注册，但系统通知权限未开启，到点可能不会弹出。请开启通知权限后重新保存提醒。',
          relatedId: relatedId,
        );
        return true;
      }
      if (_lastScheduleIssue != null && !channelWarningRecorded) {
        _clearScheduleIssueState();
        notifyListeners();
      }
      return true;
    } on NotificationPermissionDeniedException {
      _recordScheduleIssue(
        title: issueTitle,
        message: '系统通知权限未开启，重复提醒未注册。请开启通知权限后重新保存提醒。',
        relatedId: relatedId,
      );
      return false;
    } catch (e, st) {
      debugPrint('[NotificationService] scheduleDaily failed: $e\n$st');
      _recordScheduleIssue(
        title: issueTitle,
        message: '重复提醒注册失败，请检查通知权限、精确闹钟权限和系统通知渠道设置后重新保存提醒。($e)',
        relatedId: relatedId,
      );
      return false;
    }
  }

  String _notificationBodyForPayload(String body, String? payload) {
    final uri = payload == null ? null : Uri.tryParse(payload);
    if (uri?.scheme != 'duoyi' || uri?.host != 'todo') return body;
    if (body.contains('\n')) return body;
    final title = body.trim();
    if (title.isEmpty) return '点击查看待办详情';
    return '任务：$title\n点击查看详情或完成';
  }

  bool _isAlarmPushFallbackPayload(String? payload) {
    final uri = payload == null ? null : Uri.tryParse(payload);
    return uri?.queryParameters['fallback'] == 'push';
  }

  String? _relatedIdFromPayload(String? payload) {
    final uri = payload == null ? null : Uri.tryParse(payload);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    return uri.pathSegments.first;
  }

  void _recordAlarmPushFallback({
    required String issueTitle,
    DateTime? scheduledTime,
    String? relatedId,
  }) {
    _recordScheduleIssue(
      title: '闹钟提醒已降级为普通通知',
      message:
          '$issueTitle：强提醒或内置铃声注册失败，已改用普通通知提醒；到点不会弹出强提醒。请检查精准闹钟权限、强提醒渠道、后台限制和普通提醒渠道声音。',
      scheduledTime: scheduledTime,
      relatedId: relatedId,
    );
  }

  bool _showImmediate({
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
          _recordScheduleIssue(
            title: '通知发送失败',
            message: '系统通知发送失败，请检查通知权限和通知渠道设置后重试。($e)',
            blocking: false,
          );
        });
    return true;
  }

  void _addScheduledToHistory(NotificationItem item) {
    // 调度记录默认保留未读状态，必须由用户在通知记录页确认后手动标记。
    final record = item;
    _history.removeWhere(
      (existing) => _sameScheduledHistoryRecord(existing, record),
    );
    _addToHistory(record);
  }

  bool _sameScheduledHistoryRecord(NotificationItem a, NotificationItem b) {
    return a.id == b.id &&
        a.title == b.title &&
        a.body == b.body &&
        a.type == b.type &&
        a.relatedId == b.relatedId;
  }

  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String issueTitle = '提醒注册失败',
    String? relatedId,
  }) async {
    if (scheduledTime != null && !scheduledTime.isAfter(DateTime.now())) {
      _recordScheduleIssue(
        title: issueTitle,
        message: '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
        scheduledTime: scheduledTime,
        relatedId: relatedId,
      );
      return false;
    }
    final granted = await requestPermission();
    if (!granted) {
      _recordScheduleIssue(
        title: issueTitle,
        message: '系统通知权限未开启，提醒未注册。请开启通知权限后重新保存提醒。',
        scheduledTime: scheduledTime,
        relatedId: relatedId,
      );
      return false;
    }
    if (!await _ensureChannelReadyOrRecord(
      issueTitle: issueTitle,
      scheduledTime: scheduledTime,
      relatedId: relatedId,
    )) {
      return false;
    }
    return true;
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
    try {
      await LocalNotifications.instance.show(
        id: id,
        title: title,
        body: body,
        channelId: channelId,
        payload: payload,
      );
    } on NotificationPermissionDeniedException {
      _recordScheduleIssue(
        title: '通知发送失败',
        message: '系统通知权限未开启，通知未发送。请开启通知权限后重试。',
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationService] show failed: $e\n$st');
      _recordScheduleIssue(
        title: '通知发送失败',
        message: '系统通知发送失败，请检查通知权限和通知渠道设置后重试。($e)',
      );
      return;
    }
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
    final when = DateTime.now().add(delay);
    try {
      await LocalNotifications.instance.cancel(id);
    } catch (e, st) {
      debugPrint('[NotificationService] snooze cancel failed: $e\n$st');
      _recordScheduleIssue(
        title: '稍后提醒注册异常',
        message: '旧提醒取消失败，仍会尝试重新注册稍后提醒。若稍后收到重复提醒，请重新保存原提醒。($e)',
        scheduledTime: when,
        blocking: false,
      );
    }
    final scheduled = await _scheduleOnceOrRecord(
      id: id,
      title: title,
      body: body,
      when: when,
      payload: payload,
      issueTitle: '稍后提醒注册失败',
    );
    if (!scheduled) return;
    if (_isAlarmPushFallbackPayload(payload)) {
      _recordAlarmPushFallback(
        issueTitle: '提醒注册降级',
        scheduledTime: when,
        relatedId: _relatedIdFromPayload(payload),
      );
    }
    _pendingNotifications++;
    _addScheduledToHistory(
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
    final displayBody = _notificationBodyForPayload(body, payload);
    final scheduled = await _scheduleOnceOrRecord(
      id: id,
      title: title,
      body: displayBody,
      when: when,
      payload: payload,
      issueTitle: '提醒注册失败',
    );
    if (!scheduled) return;
    if (_isAlarmPushFallbackPayload(payload)) {
      _recordAlarmPushFallback(
        issueTitle: '提醒注册降级',
        scheduledTime: when,
        relatedId: _relatedIdFromPayload(payload),
      );
    }
    _pendingNotifications++;
    _addScheduledToHistory(
      NotificationItem(
        id: id.toString(),
        title: title,
        body: displayBody,
        scheduledTime: when,
        type: NotificationType.general,
      ),
    );
    notifyListeners();
  }

  Future<void> scheduleCalendarReminder({
    required String calendarEventId,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    final id = _idFor('ai_calendar_$calendarEventId');
    final displayBody = _notificationBodyForPayload(body, payload);
    final scheduled = await _scheduleOnceOrRecord(
      id: id,
      title: title,
      body: displayBody,
      when: when,
      payload: payload,
      issueTitle: 'AI 日程提醒注册失败',
      relatedId: calendarEventId,
    );
    if (!scheduled) return;
    _pendingNotifications++;
    _addScheduledToHistory(
      NotificationItem(
        id: id.toString(),
        title: title,
        body: displayBody,
        scheduledTime: when,
        type: NotificationType.general,
        relatedId: calendarEventId,
      ),
    );
    notifyListeners();
  }

  Future<void> cancelCalendarReminder(String calendarEventId) async {
    await LocalNotifications.instance.cancel(
      _idFor('ai_calendar_$calendarEventId'),
    );
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
    final displayBody = _notificationBodyForPayload(body, payload);
    final scheduled = await _scheduleDailyOrRecord(
      id: id,
      title: title,
      body: displayBody,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: payload,
      issueTitle: '重复提醒注册失败',
    );
    if (!scheduled) return;
    if (_isAlarmPushFallbackPayload(payload)) {
      _recordAlarmPushFallback(
        issueTitle: '重复提醒注册降级',
        relatedId: _relatedIdFromPayload(payload),
      );
    }
    _pendingNotifications++;
    _addScheduledToHistory(
      NotificationItem(
        id: id.toString(),
        title: title,
        body: displayBody,
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

  /// 取消全部已调度通知，并清扫 Android 原生铃声残留队列。
  /// 单条跨通道切换仍由 `ReminderScheduler` 按具体 id 做 owner 清理。
  Future<void> cancelAll() async {
    await LocalNotifications.instance.cancelAll();
    _pendingNotifications = 0;
    notifyListeners();
  }

  @override
  Future<List<int>> pendingIds() => LocalNotifications.instance.pendingIds();

  // ——————————————————————————————————————————————
  // 便捷语义 API（语义化包装，全部走 push 通道）
  // ——————————————————————————————————————————————

  void notifyLocationReminderHit(
    LocationReminderHit hit, {
    bool showSystemNotification = true,
  }) {
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

    if (showSystemNotification &&
        !_showImmediate(
          id: notificationId,
          title: title,
          body: body,
          payload: payload,
        )) {
      return;
    }
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
    final body = _notificationBodyForPayload(title, 'duoyi://todo/$todoId');
    final displayTitle = '提醒：$title';
    final scheduled = await _scheduleOnceOrRecord(
      id: _idFor('todo_$todoId'),
      title: displayTitle,
      body: body,
      when: when,
      payload: 'duoyi://todo/$todoId',
      issueTitle: '待办提醒注册失败',
      relatedId: todoId,
    );
    if (!scheduled) return;
    _pendingNotifications++;
    _addScheduledToHistory(
      NotificationItem(
        id: _idFor('todo_$todoId').toString(),
        title: displayTitle,
        body: body,
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
    const title = '习惯打卡提醒';
    final scheduled = await _scheduleDailyOrRecord(
      id: _idFor('habit_$habitId'),
      title: title,
      body: '别忘了: $habitName',
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: 'duoyi://habit/$habitId?confirm=1',
      issueTitle: '习惯提醒注册失败',
      relatedId: habitId,
    );
    if (!scheduled) return;
    _pendingNotifications++;
    _addScheduledToHistory(
      NotificationItem(
        id: _idFor('habit_$habitId').toString(),
        title: title,
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
    final scheduled = await _scheduleOnceOrRecord(
      id: _idFor('anni_$annId'),
      title: '📅 纪念日提醒',
      body: daysBefore == 0 ? '今天是 $title' : '$daysBefore 天后是 $title',
      when: remindAt,
      payload: 'duoyi://tab/calendar',
      issueTitle: '纪念日提醒注册失败',
      relatedId: annId,
    );
    if (!scheduled) return;
    _pendingNotifications++;
    _addScheduledToHistory(
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
    final notificationId = _ephemeralNotificationId();
    if (!_showImmediate(
      id: notificationId,
      title: _strings.notifPomodoroDoneTitle,
      body: body,
    )) {
      return;
    }
    _addToHistory(
      NotificationItem(
        id: notificationId.toString(),
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
    final notificationId = _ephemeralNotificationId();
    if (!_showImmediate(id: notificationId, title: title, body: body)) {
      return;
    }
    _addToHistory(
      NotificationItem(
        id: notificationId.toString(),
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
    final priorIssue = _lastScheduleIssue;
    await _ensureChannelReadyOrRecord(issueTitle: '普通通知测试异常');
    final channelWarningRecorded =
        !identical(priorIssue, _lastScheduleIssue) &&
        _lastScheduleIssue?.blocking == false;
    const notificationId = LocalNotifications.diagnosticNotificationId;
    try {
      await LocalNotifications.instance.show(
        id: notificationId,
        title: '多仪 · 通知测试',
        body: '这是一条普通提醒测试。如果没有声音，请检查“通知提醒”渠道声音设置。',
        channelId: channelId,
        payload: 'duoyi://tab/mine',
      );
      final granted = await LocalNotifications.instance.refreshPermission();
      if (!granted) {
        _recordScheduleIssue(
          title: '普通通知测试异常',
          message: '测试通知已请求发送，但系统通知权限未开启，真机可能看不到通知或没有声音。请开启系统通知权限后再测试。',
          blocking: false,
        );
      } else if (_lastScheduleIssue != null && !channelWarningRecorded) {
        _clearScheduleIssueState();
      }
    } on NotificationPermissionDeniedException {
      _recordScheduleIssue(
        title: '普通通知测试异常',
        message: '系统通知权限未开启，测试通知未发送。请开启系统通知权限后再测试。',
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationService] test notification failed: $e\n$st');
      _recordScheduleIssue(
        title: '普通通知测试异常',
        message: '测试通知发送失败，请检查系统通知权限和通知渠道设置。($e)',
      );
      return;
    }
    _addToHistory(
      NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '测试通知',
        body: '已发送普通通知测试。',
        scheduledTime: DateTime.now(),
        type: NotificationType.general,
        isRead: true,
      ),
    );
    await _saveHistory();
    notifyListeners();
  }

  Future<void> sendScheduledTest({
    Duration delay = const Duration(minutes: 1),
    ReminderKind reminderKind = ReminderKind.push,
    bool fullScreenAlarm = true,
    ReminderPopupSink? popup,
    ReminderAlarmSink? alarm,
    @visibleForTesting bool cancelSystemNotification = true,
  }) async {
    final when = DateTime.now().add(delay);
    final kind = _diagnosticReminderKind(reminderKind);
    final notificationId = _scheduledDiagnosticIdFor(
      kind,
      fullScreenAlarm: fullScreenAlarm,
    );
    final kindLabel = _diagnosticReminderKindLabel(
      kind,
      fullScreenAlarm: fullScreenAlarm,
    );
    const payload = 'duoyi://tab/mine';
    final title = _diagnosticReminderTitle(
      kind,
      fullScreenAlarm: fullScreenAlarm,
    );
    final body = '如果到点能收到$kindLabel，定时提醒调度正常。';

    await _cancelScheduledDiagnosticAcrossChannels(
      notificationId,
      popup: popup,
      alarm: alarm,
      cancelSystemNotification: cancelSystemNotification,
    );

    final scheduled = switch (kind) {
      ReminderKind.push => await _scheduleOnceOrRecord(
        id: notificationId,
        title: title,
        body: body,
        when: when,
        payload: payload,
        issueTitle: '定时通知测试注册失败',
        requestIfNeeded: true,
      ),
      ReminderKind.popup => await _schedulePopupDiagnosticOrRecord(
        popup: popup,
        id: notificationId,
        title: title,
        body: body,
        when: when,
        payload: payload,
      ),
      ReminderKind.alarm => await _scheduleAlarmDiagnosticOrRecord(
        alarm: alarm,
        id: notificationId,
        title: title,
        body: body,
        when: when,
        payload: payload,
        fullScreen: fullScreenAlarm,
      ),
      ReminderKind.email || ReminderKind.off => false,
    };
    if (!scheduled) return;
    if (kind == ReminderKind.push) {
      _pendingNotifications++;
    }
    _addScheduledToHistory(
      NotificationItem(
        id: notificationId.toString(),
        title: '定时测试通知',
        body:
            '计划在 ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')} 触发$kindLabel',
        scheduledTime: when,
        type: NotificationType.general,
      ),
    );
    await _saveHistory();
    notifyListeners();
  }

  ReminderKind _diagnosticReminderKind(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.popup || ReminderKind.alarm => kind,
      ReminderKind.push ||
      ReminderKind.email ||
      ReminderKind.off => ReminderKind.push,
    };
  }

  String _diagnosticReminderKindLabel(
    ReminderKind kind, {
    bool fullScreenAlarm = true,
  }) {
    return switch (_diagnosticReminderKind(kind)) {
      ReminderKind.popup => '弹出提醒',
      ReminderKind.alarm => fullScreenAlarm ? '全屏闹钟提醒' : '闹钟提醒',
      ReminderKind.push || ReminderKind.email || ReminderKind.off => '普通通知',
    };
  }

  int _scheduledDiagnosticIdFor(
    ReminderKind kind, {
    required bool fullScreenAlarm,
  }) {
    return switch (_diagnosticReminderKind(kind)) {
      ReminderKind.popup => _scheduledPopupDiagnosticNotificationId,
      ReminderKind.alarm =>
        fullScreenAlarm
            ? _scheduledFullScreenDiagnosticNotificationId
            : _scheduledAlarmDiagnosticNotificationId,
      ReminderKind.push ||
      ReminderKind.email ||
      ReminderKind.off => LocalNotifications.scheduledDiagnosticNotificationId,
    };
  }

  String _diagnosticReminderTitle(
    ReminderKind kind, {
    required bool fullScreenAlarm,
  }) {
    return switch (_diagnosticReminderKind(kind)) {
      ReminderKind.popup => '多仪 · 弹出提醒测试',
      ReminderKind.alarm => fullScreenAlarm ? '多仪 · 全屏闹钟测试' : '多仪 · 闹钟测试',
      ReminderKind.push ||
      ReminderKind.email ||
      ReminderKind.off => '多仪 · 定时通知测试',
    };
  }

  Future<void> _cancelScheduledDiagnosticAcrossChannels(
    int id, {
    ReminderPopupSink? popup,
    ReminderAlarmSink? alarm,
    bool cancelSystemNotification = true,
  }) async {
    Future<void> cancelSafely(
      String label,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (e, st) {
        debugPrint(
          '[NotificationService] diagnostic $label cancel failed: $e\n$st',
        );
      }
    }

    if (cancelSystemNotification) {
      await cancelSafely(
        'notification',
        () => LocalNotifications.instance.cancel(id),
      );
    }
    await cancelSafely('popup', () async {
      await popup?.cancel(id);
    });
    await cancelSafely('alarm', () async {
      await alarm?.cancel(id);
    });
  }

  Future<bool> _schedulePopupDiagnosticOrRecord({
    required ReminderPopupSink? popup,
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
  }) async {
    if (popup == null) {
      return _scheduleOnceOrRecord(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
        issueTitle: '定时弹出测试注册失败',
        requestIfNeeded: true,
      );
    }
    try {
      await popup.scheduleOnce(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      );
      return true;
    } catch (e, st) {
      debugPrint('[NotificationService] scheduled popup test failed: $e\n$st');
      _recordScheduleIssue(
        title: '定时弹出测试注册失败',
        message: '弹出提醒注册失败，请确认应用仍在前台或已允许通知兜底。',
        scheduledTime: when,
      );
      rethrow;
    }
  }

  Future<bool> _scheduleAlarmDiagnosticOrRecord({
    required ReminderAlarmSink? alarm,
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
    required bool fullScreen,
  }) async {
    if (alarm == null) {
      return _scheduleOnceOrRecord(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
        issueTitle: '定时闹钟测试注册失败',
        requestIfNeeded: true,
      );
    }
    try {
      await alarm.scheduleFullScreen(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
        fullScreen: fullScreen,
        vibrate: true,
        snoozeMinutes: fullScreen ? 5 : 0,
      );
      return true;
    } catch (e, st) {
      debugPrint('[NotificationService] scheduled alarm test failed: $e\n$st');
      _recordScheduleIssue(
        title: '定时闹钟测试注册失败',
        message: '闹钟提醒注册失败，请检查通知权限、精准闹钟权限和强提醒渠道设置。',
        scheduledTime: when,
      );
      rethrow;
    }
  }

  void notifyAchievementUnlocked(Achievement achievement) {
    final title = '成就解锁：${achievement.title}';
    final body = achievement.description;
    final existingIndex = _history.indexWhere(
      (item) =>
          item.type == NotificationType.general &&
          ((item.relatedId == achievement.id &&
                  item.title.startsWith('成就解锁：')) ||
              (item.title == title && item.body == body)),
    );
    if (existingIndex >= 0) {
      return;
    }
    final notificationId = _ephemeralNotificationId();
    if (!_showImmediate(
      id: notificationId,
      title: title,
      body: body,
      payload: 'duoyi://tab/mine',
    )) {
      return;
    }
    _addToHistory(
      NotificationItem(
        id: notificationId.toString(),
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
    notifyListeners();
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
    super.dispose();
  }
}
