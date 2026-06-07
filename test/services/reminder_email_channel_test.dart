import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('reminder model and sinks expose an email channel', () {
    final model = File('lib/models/goal.dart').readAsStringSync();
    final sinks = File('lib/services/reminder_sinks.dart').readAsStringSync();
    final backendSink = File(
      'lib/services/backend_reminder_email_sink.dart',
    ).readAsStringSync();

    expect(
      model,
      contains('enum ReminderKind { push, alarm, email, popup, off }'),
    );
    expect(model, contains('[ReminderKind.email]'));
    expect(sinks, contains('abstract class ReminderEmailSink'));
    expect(sinks, contains('scheduleOnce'));
    expect(sinks, contains('scheduleRepeating'));
    expect(sinks, contains('class NoopReminderEmailSink'));
    expect(backendSink, contains('implements ReminderEmailSink'));
    expect(backendSink, contains('/api/reminders/email/once'));
    expect(backendSink, contains('/api/reminders/email/repeating'));
    expect(backendSink, contains(r'/api/reminders/email/$id'));
    expect(backendSink, contains('client.token'));
    expect(
      backendSink,
      isNot(contains('scheduleOnce failed')),
      reason:
          'Backend email scheduling failures must reach ReminderScheduler so a failed registration is not cached as success.',
    );
    expect(backendSink, isNot(contains('scheduleRepeating failed')));
  });

  test('ReminderScheduler routes email rules away from push and alarm', () {
    final scheduler = File(
      'lib/services/reminder_scheduler.dart',
    ).readAsStringSync();

    expect(scheduler, contains('final ReminderEmailSink email;'));
    expect(scheduler, contains('ReminderEmailSink? email'));
    expect(scheduler, contains('NoopReminderEmailSink'));
    expect(scheduler, contains('case ReminderKind.email:'));
    expect(scheduler, contains('email.scheduleOnce'));
    expect(scheduler, contains('email.scheduleRepeating'));
    expect(scheduler, contains('email dispatch failed'));
    expect(scheduler, contains('repeating email dispatch failed'));
    expect(scheduler, contains('Future<bool> _cancelEmail'));
    expect(scheduler, contains("ReminderKind.email => '✉️'"));
  });

  test('ReminderScheduler routes popup rules to the foreground popup sink', () {
    final scheduler = File(
      'lib/services/reminder_scheduler.dart',
    ).readAsStringSync();
    final sinks = File('lib/services/reminder_sinks.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(sinks, contains('abstract class ReminderPopupSink'));
    expect(sinks, contains('class NoopReminderPopupSink'));
    expect(sinks, contains('未配置弹出框提醒出口'));
    expect(sinks, contains('class NotificationFallbackReminderPopupSink'));
    expect(scheduler, contains('final ReminderPopupSink popup;'));
    expect(
      scheduler,
      contains('popup = popup ?? NotificationFallbackReminderPopupSink(notif)'),
    );
    expect(scheduler, contains('case ReminderKind.popup:'));
    expect(scheduler, contains('await popup.scheduleOnce'));
    expect(scheduler, contains('await popup.scheduleRepeating'));
    expect(scheduler, contains('() => popup.cancel(intId)'));
    expect(scheduler, contains('Future<bool> _cancelSafely'));
    expect(main, contains('ForegroundReminderPopupSink('));
    expect(main, contains('onOpenPayload: (payload)'));
  });

  test(
    'foreground popup reminders register notification fallback and cancel it in foreground',
    () {
      final popupSink = File(
        'lib/services/foreground_reminder_popup_sink.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();

      expect(
        popupSink,
        contains('final ReminderNotificationSink? notificationFallback'),
      );
      expect(popupSink, contains('fallback.scheduleOnce('));
      expect(popupSink, contains('fallback.scheduleDaily('));
      expect(popupSink, contains('notificationFallback?.cancel(id)'));
      expect(popupSink, contains('isForegroundGetter'));
      expect(popupSink, contains('AppLifecycleState.resumed'));
      expect(main, contains('notificationFallback: notificationService'));
      expect(popupSink, contains("'fallback', () => 'popup_notification'"));
      expect(
        popupSink,
        contains('_showOrFallback('),
        reason: '用户选择弹出框时，后台应保留系统通知兜底，前台显示弹窗前再取消兜底。',
      );
      expect(popupSink, contains('_visibleDialogIds.add(id)'));
      expect(popupSink, contains('_visibleNavigators'));
      expect(popupSink, contains('await navigator.maybePop();'));
      expect(
        popupSink.indexOf('_timers.remove(id)?.cancel();'),
        lessThan(popupSink.indexOf('await navigator.maybePop();')),
        reason: '关闭或切换 popup 提醒时，先停 timer，再关闭已显示的旧弹框。',
      );
    },
  );

  test('backend exposes SMTP-backed reminder email scheduling', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(backend, contains('CREATE TABLE IF NOT EXISTS reminder_email_jobs'));
    expect(backend, contains('"reminder_email_enabled"'));
    expect(backend, contains('class ReminderEmailOnceRequest'));
    expect(backend, contains('class ReminderEmailRepeatingRequest'));
    expect(backend, contains('@app.post("/api/reminders/email/once")'));
    expect(backend, contains('@app.post("/api/reminders/email/repeating")'));
    expect(
      backend,
      contains('@app.delete("/api/reminders/email/{reminder_id}")'),
    );
    expect(backend, contains('@app.post("/api/admin/reminders/email/test")'));
    expect(backend, contains('dispatch_due_reminder_emails'));
    expect(backend, contains('REMINDER_EMAIL_TASK'));
    expect(backend, contains('_smtp_send('));
  });

  test(
    'ReminderPlanEditor exposes user-facing notification popup and alarm choices',
    () {
      final editor = File(
        'lib/widgets/reminder_plan_editor.dart',
      ).readAsStringSync();

      expect(editor, contains('value: ReminderKind.push'));
      expect(editor, contains('value: ReminderKind.popup'));
      expect(editor, contains('value: ReminderKind.alarm'));
      expect(editor, contains('value: ReminderKind.off'));
      expect(editor, contains("label: Text('通知')"));
      expect(editor, contains("label: Text('弹出框')"));
      expect(editor, contains("label: Text('闹钟')"));
      expect(editor, contains("label: Text('关闭')"));
      expect(editor, isNot(contains("label: Text('邮件')")));
    },
  );
}
