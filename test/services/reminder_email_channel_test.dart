import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('reminder model and sinks expose an email channel', () {
    final model = File('lib/models/goal.dart').readAsStringSync();
    final sinks = File('lib/services/reminder_sinks.dart').readAsStringSync();
    final backendSink = File(
      'lib/services/backend_reminder_email_sink.dart',
    ).readAsStringSync();

    expect(model, contains('enum ReminderKind { push, alarm, email }'));
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
    expect(scheduler, contains('await email.cancel(intId)'));
    expect(scheduler, contains("ReminderKind.email => '✉️'"));
  });

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

  test('ReminderPlanEditor lets users pick email reminders', () {
    final editor = File(
      'lib/widgets/reminder_plan_editor.dart',
    ).readAsStringSync();

    expect(editor, contains('value: ReminderKind.email'));
    expect(editor, contains("label: Text('邮件')"));
    expect(editor, contains('Icons.alternate_email'));
    expect(editor, contains("ReminderKind.email => '邮件'"));
  });
}
