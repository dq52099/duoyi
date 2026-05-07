import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地全量备份 / 恢复。导出/导入 JSON 文本；所有备份键列表集中在这。
class BackupService {
  static const List<String> _keys = [
    'todos',
    'habits',
    'pomodoro_sessions',
    'pomodoro_config',
    'user_profile',
    'duoyi_notes',
    'duoyi_countdowns',
    'duoyi_anniversaries_v2',
    'duoyi_diary',
    'duoyi_goals',
    'duoyi_courses',
    'duoyi_course_settings',
  ];

  static const int schemaVersion = 1;

  /// 导出 JSON 字符串。
  static Future<String> exportAll() async {
    final p = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final k in _keys) {
      if (p.getStringList(k) != null) {
        map[k] = {'type': 'stringList', 'value': p.getStringList(k)};
      } else if (p.getString(k) != null) {
        map[k] = {'type': 'string', 'value': p.getString(k)};
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
  static Future<int> importAll(String rawJson, {bool merge = false}) async {
    final obj = json.decode(rawJson);
    if (obj is! Map || obj['app'] != 'duoyi') {
      throw const FormatException('备份文件无效: 不是多仪备份');
    }
    final data = obj['data'];
    if (data is! Map) throw const FormatException('备份文件损坏: data 字段缺失');

    final p = await SharedPreferences.getInstance();
    int count = 0;

    for (final entry in data.entries) {
      final key = entry.key.toString();
      if (!_keys.contains(key)) continue; // 忽略未知键
      final v = entry.value;
      if (v is! Map) continue;
      final type = v['type'];
      final value = v['value'];

      if (type == 'stringList' && value is List) {
        final list = value.map((e) => e.toString()).toList();
        if (merge) {
          final existing = p.getStringList(key) ?? const <String>[];
          final set = <String>{...existing, ...list};
          await p.setStringList(key, set.toList());
        } else {
          await p.setStringList(key, list);
        }
        count++;
      } else if (type == 'string' && value is String) {
        // 对象类型(config/profile) 总是覆盖
        await p.setString(key, value);
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
}
