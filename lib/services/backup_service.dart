import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地全量备份 / 恢复。导出/导入 JSON 文本；所有备份键列表集中在这。
class BackupService {
  /// 偏好/提醒设置键（与 cloud_sync_provider 的 _preference*Keys 对齐）。
  /// 不纳入这些键会导致换机恢复后提醒时刻表与个性化设置全部归零。
  static const List<String> _preferenceKeys = [
    // 基础偏好（周起始日 / 日期格式 / 农历 / 触感等）
    'pref_first_day_of_week',
    'pref_date_format',
    'pref_default_tab',
    'pref_haptic_feedback',
    'pref_show_lunar',
    'pref_show_completed_todos',
    'pref_default_pomodoro_minutes',
    'pref_quick_capture_fab',
    'pref_notification_quick_add',
    'pref_notification_today_progress',
    'pref_notification_history_limit',
    'pref_auto_archive_completed_days',
    // 每日提醒 slot 1（默认组）
    'pref_daily_reminder_enabled',
    'pref_daily_reminder_kind',
    'pref_daily_reminder_hour',
    'pref_daily_reminder_minute',
    'pref_daily_reminder_today_tasks',
    'pref_daily_reminder_tomorrow_plan',
    'pref_daily_reminder_overdue',
    'pref_daily_reminder_repeat_days',
    'pref_daily_reminder_pause_holidays',
    // 每日提醒 slot 2
    'pref_daily_reminder_slot2_enabled',
    'pref_daily_reminder_slot2_kind',
    'pref_daily_reminder_slot2_hour',
    'pref_daily_reminder_slot2_minute',
    'pref_daily_reminder_slot2_today',
    'pref_daily_reminder_slot2_tomorrow',
    'pref_daily_reminder_slot2_overdue',
    'pref_daily_reminder_slot2_repeat_days',
    'pref_daily_reminder_slot2_pause_holidays',
    // 每日提醒 slot 3
    'pref_daily_reminder_slot3_enabled',
    'pref_daily_reminder_slot3_kind',
    'pref_daily_reminder_slot3_hour',
    'pref_daily_reminder_slot3_minute',
    'pref_daily_reminder_slot3_today',
    'pref_daily_reminder_slot3_tomorrow',
    'pref_daily_reminder_slot3_overdue',
    'pref_daily_reminder_slot3_repeat_days',
    'pref_daily_reminder_slot3_pause_holidays',
    // 日 / 周 / 月 / 年报告提醒
    'pref_daily_report_reminder',
    'pref_daily_report_reminder_hour',
    'pref_daily_report_reminder_minute',
    'pref_weekly_report_reminder',
    'pref_weekly_report_reminder_weekday',
    'pref_weekly_report_reminder_hour',
    'pref_weekly_report_reminder_minute',
    'pref_monthly_report_reminder',
    'pref_monthly_report_reminder_day',
    'pref_monthly_report_reminder_hour',
    'pref_monthly_report_reminder_minute',
    'pref_yearly_report_reminder',
    'pref_yearly_report_reminder_month',
    'pref_yearly_report_reminder_day',
    'pref_yearly_report_reminder_hour',
    'pref_yearly_report_reminder_minute',
    // 底部导航布局
    'pref_bottom_nav_order',
    'pref_bottom_nav_visible',
    // 提醒铃声（音量 int / 音效 string / 旧强提醒迁移标记 bool）
    'pref_reminder_ringtone_sound',
    'pref_reminder_ringtone_volume_percent',
    'pref_reminder_ringtone_alarm_migrated_to_soft',
  ];

  /// 恢复时有意不迁移的设备相关偏好键：
  /// 时区应跟随各设备自身设置，避免把 A 设备的时区写死到 B 设备。
  static const Set<String> _deviceSpecificPreferenceKeys = {
    'pref_app_timezone_iana',
    'pref_app_timezone_mode',
  };

  static const List<String> _keys = [
    'todos',
    'habits',
    'pomodoro_sessions',
    'pomodoro_focus_penalties',
    'pomodoro_config',
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
    'duoyi_achievements_unlocked',
    'duoyi_virtual_rewards',
    'duoyi_custom_focus_sounds',
    'duoyi_focus_rooms',
    'duoyi_location_reminders_v1',
    'duoyi_quick_capture_templates_v1',
    'active_brand',
    'theme_unlocked_brands',
    'theme_shop_state',
    ..._preferenceKeys,
  ];

  static const int schemaVersion = 1;

  /// 导出 JSON 字符串。
  static Future<String> exportAll() async {
    final p = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final k in _keys) {
      // 设备相关偏好不进备份（如时区），避免把 A 设备的设置写死到 B 设备。
      if (_deviceSpecificPreferenceKeys.contains(k)) continue;
      // 用无类型 get 探测：getStringList 对 string 值会抛类型转换异常
      // (shared_preferences 的 getStringList 直接 as List)，string 键
      // (pomodoro_config/user_profile 等) 不能先走 getStringList。
      final value = p.get(k);
      if (value is List) {
        map[k] = {
          'type': 'stringList',
          'value': value.map((e) => e.toString()).toList(),
        };
      } else if (value is String) {
        map[k] = {'type': 'string', 'value': value};
      } else if (value is bool) {
        map[k] = {'type': 'bool', 'value': value};
      } else if (value is int) {
        map[k] = {'type': 'int', 'value': value};
      } else if (value is double) {
        map[k] = {'type': 'double', 'value': value};
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'duoyi',
      'schema': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': map,
    });
  }

  /// 返回本次覆盖的键数量。
  static Future<int> importAll(
    String rawJson, {
    bool merge = false,
    bool clearMissing = false,
  }) async {
    final obj = json.decode(rawJson);
    if (obj is! Map || obj['app'] != 'duoyi') {
      throw const FormatException('备份文件无效: 不是多仪备份');
    }
    final data = obj['data'];
    if (data is! Map) throw const FormatException('备份文件损坏: data 字段缺失');

    final p = await SharedPreferences.getInstance();
    int count = 0;

    if (clearMissing && !merge) {
      for (final key in _keys) {
        if (!data.containsKey(key)) {
          await p.remove(key);
        }
      }
    }

    for (final entry in data.entries) {
      final key = entry.key.toString();
      if (!_keys.contains(key)) continue; // 忽略未知键
      // 设备相关偏好（时区）即使出现在备份文件里也不写入本机。
      if (_deviceSpecificPreferenceKeys.contains(key)) continue;
      final v = entry.value;
      if (v is! Map) continue;
      final type = v['type'];
      final value = v['value'];

      if (type == 'stringList' && value is List) {
        final list = value.map((e) => e.toString()).toList();
        // 偏好键（提醒重复星期/底部导航布局）在合并导入时也整体覆盖：
        // 云同步对这些键是时间戳门控的 LWW 整体写入（cloud_sync_provider
        // 的 _writePreferencesPayload 不做并集），并集会让另一台设备的
        // 重复星期/隐藏导航项只增不减地渗入本机设置。
        if (merge && !_preferenceKeys.contains(key)) {
          final existing = p.getStringList(key) ?? const <String>[];
          await p.setStringList(key, _mergeStringLists(existing, list));
        } else {
          await p.setStringList(key, list);
        }
        count++;
      } else if (type == 'string' && value is String) {
        // 对象类型(config/profile) 总是覆盖
        await p.setString(key, value);
        count++;
      } else if (type == 'bool' && value is bool) {
        await p.setBool(key, value);
        count++;
      } else if (type == 'int' && value is int) {
        await p.setInt(key, value);
        count++;
      } else if (type == 'double' && value is num) {
        // JSON 中 1.0 可能被解码为 int，统一按 double 落盘。
        await p.setDouble(key, value.toDouble());
        count++;
      }
    }
    return count;
  }

  /// 清空全部本地数据(保留登录/服务器配置)。
  static Future<void> wipeAll() async {
    final p = await SharedPreferences.getInstance();
    for (final k in _keys) {
      await p.remove(k);
    }
  }

  static List<String> _mergeStringLists(
    List<String> existing,
    List<String> incoming,
  ) {
    final merged = <String>[];
    final indexByKey = <String, int>{};

    void absorb(String raw) {
      final mergeKey = _stringListMergeKey(raw);
      final index = indexByKey[mergeKey];
      if (index == null) {
        indexByKey[mergeKey] = merged.length;
        merged.add(raw);
      } else {
        merged[index] = raw;
      }
    }

    for (final raw in existing) {
      absorb(raw);
    }
    for (final raw in incoming) {
      absorb(raw);
    }
    return merged;
  }

  static String _stringListMergeKey(String raw) {
    final trimmed = raw.trim();
    final recordId = _decodedRecordId(trimmed);
    if (recordId == null || recordId.isEmpty) {
      return 'raw:$trimmed';
    }
    return 'id:$recordId';
  }

  static String? _decodedRecordId(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        final id = decoded['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) return id;
      }
    } catch (_) {}
    return null;
  }
}
