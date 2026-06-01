import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('倒数日页面固定文案迁移到 I18n', () {
    final source = File('lib/screens/countdown_screen.dart').readAsStringSync();
    final model = File('lib/models/countdown.dart').readAsStringSync();
    final scheduler = File(
      'lib/services/reminder_scheduler.dart',
    ).readAsStringSync();
    expect(
      source,
      contains("import '../providers/notification_service.dart';"),
    );
    expect(source, contains("import '../models/goal.dart' show ReminderKind;"));
    expect(source, contains("import '../services/alarm_service.dart';"));
    expect(source, contains("import '../services/local_notifications.dart';"));
    expect(source, contains('ensureReadyForReminder('));
    expect(source, contains("I18n.tr('countdown.reminder.register_failed')"));
    expect(source, contains("I18n.tr('countdown.reminder.not_registered')"));
    expect(
      source,
      contains(
        'next = next.copyWith(remind: false, reminderKind: ReminderKind.off)',
      ),
    );
    expect(source, contains('late ReminderKind _reminderKind'));
    expect(source, contains('SegmentedButton<ReminderKind>'));
    expect(source, contains('value: ReminderKind.push'));
    expect(source, contains('value: ReminderKind.popup'));
    expect(source, contains('value: ReminderKind.alarm'));
    expect(source, contains('value: ReminderKind.off'));
    expect(source, contains('case ReminderKind.push:'));
    expect(source, contains('case ReminderKind.popup:'));
    expect(source, contains('case ReminderKind.alarm:'));
    expect(source, contains('case ReminderKind.off:'));
    expect(source, contains('LocalNotifications.instance.ensurePermission()'));
    expect(source, contains('AlarmService.instance'));
    expect(source, contains('.notificationChannelIds()'));
    expect(source, contains('.hasExactAlarmPermission()'));
    expect(source, contains('.hasFullScreenIntentPermission()'));
    expect(
      source,
      contains('reminderKind: _remind ? _reminderKind : ReminderKind.off'),
    );
    expect(model, contains('final ReminderKind reminderKind'));
    expect(model, contains("'reminderKind': reminderKind.index"));
    expect(model, contains('_reminderKindFromJson'));
    expect(scheduler, contains('kind: item.reminderKind'));
    expect(scheduler, contains("'countdown popup:\$countdownId'"));
    expect(scheduler, contains('() => popup.cancel(id)'));
    expect(scheduler, contains('item.reminderKind.name'));
    expect(source, contains('bool _saving = false'));
    expect(source, contains('if (_saving) return'));
    expect(source, contains('setState(() => _saving = true)'));
    expect(source, contains('onPressed: _saving ? null : _save'));
    expect(source, contains('CircularProgressIndicator(strokeWidth: 2)'));
    expect(source, contains('await provider.updateItem(next)'));
    expect(source, isNot(contains('await provider.addItem(next)')));
    expect(source, isNot(contains('showCountdownEditor(routeContext')));
    expect(source, isNot(contains('_isNewItem')));
    expect(source, isNot(contains('FloatingActionButton(')));
    expect(
      source,
      isNot(contains("actionLabel: I18n.tr('countdown.add_record')")),
    );
    expect(source, isNot(contains("onAction: () => _showEditor(context)")));
    expect(
      source.indexOf('await provider.updateItem(next)'),
      lessThan(source.indexOf('Navigator.pop(context)')),
      reason: '倒数日本体应先保存，再关闭弹层或提示提醒降级。',
    );
    expect(
      source,
      isNot(contains('return;\n      }\n    }\n    try {')),
      reason: '提醒注册失败不能直接阻断倒数日创建。',
    );

    for (final key in [
      'countdown.title',
      'countdown.empty',
      'countdown.nearest.empty',
      'countdown.nearest.prefix',
      'countdown.nearest.days_prefix',
      'countdown.summary.total',
      'countdown.summary.within_7_days',
      'countdown.list.title',
      'countdown.list.subtitle',
      'countdown.category.default',
      'countdown.editor.edit_title',
      'countdown.editor.subtitle',
      'countdown.field.title',
      'countdown.field.category',
      'countdown.field.target_date',
      'countdown.field.due_reminder',
      'countdown.field.remind_days',
      'countdown.field.remind_time',
      'countdown.validation.title_required',
      'countdown.saved',
      'countdown.save_failed_prefix',
      'countdown.reminder.closed',
      'countdown.reminder.before_prefix',
      'countdown.reminder.before_suffix',
      'countdown.reminder.register_failed',
      'countdown.reminder.not_registered',
      'countdown.reminder.popup_fallback_failed',
      'countdown.reminder.popup_permission_denied',
      'countdown.reminder.popup_warning',
      'countdown.reminder.alarm_permission_denied',
      'countdown.reminder.alarm_channel_missing',
      'countdown.reminder.exact_alarm_missing',
      'countdown.reminder.fullscreen_missing',
      'countdown.reminder.email_warning',
      'countdown.reminder.exception_prefix',
      'countdown.reminder.time_past',
      'reminder.kind.push',
      'reminder.kind.popup',
      'reminder.kind.alarm',
      'reminder.kind.off',
      'countdown.status.pinned',
      'countdown.status.expired',
      'countdown.status.soon',
      'countdown.status.running',
      'countdown.target.prefix',
      'countdown.days.elapsed',
      'countdown.days.remaining',
      'unit.day',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    for (final hardcoded in [
      "'倒数日'",
      "'暂无倒数日记录'",
      "'暂无即将到期的事件'",
      "'总数'",
      "'全部倒数日'",
      "'按优先级和剩余天数排序'",
      "'编辑倒数日'",
      "'事件名称'",
      "'目标日期'",
      "'到期提醒'",
      "'提醒时间'",
      "'置顶'",
      "'已过期'",
      "'倒数中'",
      "'已过'",
      "'天'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }
  });

  test('倒数日卡片和生日纪念日保持轻量统一风格', () {
    final source = File('lib/screens/countdown_screen.dart').readAsStringSync();
    final card = source.substring(
      source.indexOf('class _CountdownCard'),
      source.indexOf('class _StatusPill'),
    );
    final pill = source.substring(source.indexOf('class _StatusPill'));

    expect(card, contains('AppSurfaceCard('));
    expect(card, contains('appSecondaryRouteTitleTextStyle(context)'));
    expect(card, contains('appSecondaryControlLabelStyle('));
    expect(card, contains('crossAxisAlignment: WrapCrossAlignment.center'));
    expect(
      card,
      contains('Border.all(color: color.withValues(alpha: 0.12), width: 0.45)'),
    );
    expect(card, contains('BorderRadius.circular(14)'));
    expect(card, contains('width: 5'));
    expect(card, contains('fontSize: 18'));
    expect(card, contains('fontSize: 11'));
    expect(card, isNot(contains('fontSize: 28')));
    expect(card, isNot(contains('fontSize: 32')));
    expect(card, isNot(contains('textTheme.titleMedium')));
    expect(card, isNot(matches(RegExp(r'FontWeight\.(bold|w700|w800|w900)'))));
    expect(
      pill,
      contains('Border.all(color: color.withValues(alpha: 0.10), width: 0.45)'),
    );
    for (final call in _calls(card + pill, 'Border.all(')) {
      expect(call, contains('width: 0.45'), reason: call);
    }
  });
}

Iterable<String> _calls(String source, String token) sync* {
  var searchFrom = 0;
  while (true) {
    final start = source.indexOf(token, searchFrom);
    if (start == -1) return;
    var depth = 0;
    var end = start;
    for (; end < source.length; end++) {
      final char = source[end];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          end++;
          break;
        }
      }
    }
    yield source.substring(start, end);
    searchFrom = end;
  }
}
