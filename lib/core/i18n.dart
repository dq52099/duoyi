/// 国际化文案表（Task: i18n）。
///
/// 设计思路：
/// - 当前项目 200+ 处中文硬编码；一次性全替换不现实。
/// - 引入 `AppLocale.zh` / `AppLocale.en` + `tr(key)` 函数式 API。
/// - 高频公共词条先入表，调用方按需迁移；未命中的 key 直接返回中文回退。
/// - `LocaleProvider` 持久化用户偏好（默认 `zh`）。
///
/// 添加新词条：在 `_zh` 与 `_en` 中同步追加同一 key。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLocale { zh, en }

const Map<String, String> _zh = <String, String>{
  // 通用动作
  'action.confirm': '确定',
  'action.cancel': '取消',
  'action.save': '保存',
  'action.delete': '删除',
  'action.edit': '编辑',
  'action.add': '添加',
  'action.complete': '完成',
  'action.snooze': '稍后提醒',
  'action.retry': '重试',
  'action.back': '返回',
  // 导航
  'nav.today': '今日',
  'nav.todo': '待办',
  'nav.habit': '习惯',
  'nav.calendar': '日历',
  'nav.focus': '专注',
  'nav.mine': '我的',
  // 待办
  'todo.empty': '今天没有待办，去添加一个吧',
  'todo.add': '添加待办',
  'todo.matrix': '四象限',
  'todo.list': '列表',
  'todo.postpone': '顺延',
  'todo.priority.high': '高',
  'todo.priority.medium': '中',
  'todo.priority.low': '低',
  // 日历
  'calendar.month': '月',
  'calendar.week': '周',
  'calendar.day': '日',
  'calendar.empty': '这一天没有事项',
  // 专注
  'focus.start': '开始专注',
  'focus.pause': '暂停',
  'focus.resume': '继续',
  'focus.reset': '重置',
  // 提醒/通知
  'reminder.health': '通知健康',
  'reminder.test_notification': '发送测试通知',
  'reminder.snooze_5min': '5 分钟后',
  'reminder.snooze_10min': '10 分钟后',
  'reminder.snooze_30min': '30 分钟后',
  // 时间足迹
  'time_audit.title': '时间足迹',
  'time_audit.add_manual': '手动记录',
  'time_audit.weekly_overview': '本周时间分布',
  // 共享
  'share.title': '共享空间',
  'share.create_invite': '生成邀请码',
  'share.accept_invite': '加入空间',
  'share.role.owner': '拥有者',
  'share.role.editor': '可编辑',
  'share.role.viewer': '只读',
};

const Map<String, String> _en = <String, String>{
  'action.confirm': 'OK',
  'action.cancel': 'Cancel',
  'action.save': 'Save',
  'action.delete': 'Delete',
  'action.edit': 'Edit',
  'action.add': 'Add',
  'action.complete': 'Done',
  'action.snooze': 'Snooze',
  'action.retry': 'Retry',
  'action.back': 'Back',
  'nav.today': 'Today',
  'nav.todo': 'Tasks',
  'nav.habit': 'Habits',
  'nav.calendar': 'Calendar',
  'nav.focus': 'Focus',
  'nav.mine': 'Me',
  'todo.empty': "Nothing scheduled today. Add one?",
  'todo.add': 'Add task',
  'todo.matrix': 'Matrix',
  'todo.list': 'List',
  'todo.postpone': 'Postpone',
  'todo.priority.high': 'High',
  'todo.priority.medium': 'Medium',
  'todo.priority.low': 'Low',
  'calendar.month': 'Month',
  'calendar.week': 'Week',
  'calendar.day': 'Day',
  'calendar.empty': 'No events on this day',
  'focus.start': 'Start focus',
  'focus.pause': 'Pause',
  'focus.resume': 'Resume',
  'focus.reset': 'Reset',
  'reminder.health': 'Notifications',
  'reminder.test_notification': 'Send test notification',
  'reminder.snooze_5min': 'In 5 min',
  'reminder.snooze_10min': 'In 10 min',
  'reminder.snooze_30min': 'In 30 min',
  'time_audit.title': 'Time Tracking',
  'time_audit.add_manual': 'Add manual entry',
  'time_audit.weekly_overview': 'This week',
  'share.title': 'Shared Spaces',
  'share.create_invite': 'Create invite code',
  'share.accept_invite': 'Join space',
  'share.role.owner': 'Owner',
  'share.role.editor': 'Editor',
  'share.role.viewer': 'Viewer',
};

class I18n {
  I18n._();

  static AppLocale _current = AppLocale.zh;

  static AppLocale get current => _current;

  static void setLocale(AppLocale locale) {
    _current = locale;
  }

  /// 翻译键。如果当前 locale 字典缺失，先回退到中文，再回退到 key 本身。
  static String tr(String key) {
    final dict = _current == AppLocale.en ? _en : _zh;
    return dict[key] ?? _zh[key] ?? key;
  }
}

/// 持久化的 locale 偏好。
class LocaleProvider extends ChangeNotifier {
  static const _key = 'duoyi_locale_v1';

  AppLocale _locale = AppLocale.zh;

  AppLocale get locale => _locale;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == 'en') {
      _locale = AppLocale.en;
    } else {
      _locale = AppLocale.zh;
    }
    I18n.setLocale(_locale);
  }

  Future<void> setLocale(AppLocale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    I18n.setLocale(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale == AppLocale.en ? 'en' : 'zh');
    notifyListeners();
  }
}
