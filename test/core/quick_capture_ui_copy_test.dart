import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/quick_capture_ui_copy.dart';
import 'package:duoyi/models/quick_capture_template.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'generated habit units follow locale and count without changing data',
    () {
      for (final unit in <String?>[null, '', '   ']) {
        for (final count in [1, 2]) {
          final template = QuickCaptureTemplate(
            name: '用户模板 literal',
            kind: QuickCaptureTemplateKind.habit,
            habitTargetCount: count,
            habitUnit: unit,
          );
          final stored = template.toJson();
          for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
            I18n.setLocale(locale);
            final expected = locale == AppLocale.en
                ? (count == 1 ? 'time' : 'times')
                : '次';
            expect(
              QuickCaptureUiCopy.templateSummary(template),
              '${locale == AppLocale.en ? 'Habit' : '习惯'} · $count $expected',
            );
            expect(template.toJson(), stored);
            expect(template.toHabit('new habit').unit, isNull);
          }
        }
      }
    },
  );

  test(
    'authored habit units stay literal across counts and locale changes',
    () {
      for (final unit in ['次', 'time', '分钟 literal', '  cups  ']) {
        final template = QuickCaptureTemplate(
          name: '用户模板',
          kind: QuickCaptureTemplateKind.habit,
          habitTargetCount: 2,
          habitUnit: unit,
        );
        final stored = template.toJson();
        for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
          I18n.setLocale(locale);
          expect(
            QuickCaptureUiCopy.templateSummary(template),
            endsWith('2 $unit'),
          );
          expect(template.toJson(), stored);
        }
      }
    },
  );

  test('default unit hint matches the normalized saved target', () {
    I18n.setLocale(AppLocale.en);
    for (final count in [-2, 0, 1]) {
      expect(QuickCaptureUiCopy.defaultHabitUnit(count), 'time');
    }
    expect(QuickCaptureUiCopy.defaultHabitUnit(2), 'times');
    I18n.setLocale(AppLocale.zh);
    expect(QuickCaptureUiCopy.defaultHabitUnit(1), '次');
    expect(QuickCaptureUiCopy.defaultHabitUnit(2), '次');
  });

  for (final locale in AppLocale.values) {
    test('quick capture fixed copy and literal diagnostics in $locale', () {
      I18n.setLocale(locale);
      final en = locale == AppLocale.en;
      expect(QuickCaptureUiCopy.aiCommandTitle, en ? 'AI commands' : 'AI 指令');
      expect(QuickCaptureUiCopy.executeAction, en ? 'Run' : '执行');
      expect(
        QuickCaptureUiCopy.saveFailed,
        en ? 'Could not save. Please try again.' : '保存失败，请重试。',
      );
      expect(QuickCaptureUiCopy.draftSaveFailed, contains(en ? 'draft' : '草稿'));
      const literal = '服务端原文 literal 123';
      expect(
        QuickCaptureUiCopy.commandExecuted(literal, literal),
        contains(literal),
      );
      expect(
        QuickCaptureUiCopy.habitReminderFailed(literal),
        contains(literal),
      );
    });

    test('custom template data remains literal in $locale', () {
      I18n.setLocale(locale);
      final template = QuickCaptureTemplate(
        name: '工作会议 literal',
        kind: QuickCaptureTemplateKind.todo,
        listGroupName: '原文 list',
        tags: ['原文-tag'],
        priority: TodoPriority.high,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.push,
              offsetMinutes: -15,
            ),
          ],
        ),
      );
      expect(QuickCaptureUiCopy.templateName(template), '工作会议 literal');
      final summary = QuickCaptureUiCopy.templateSummary(template);
      expect(summary, contains('原文 list'));
      expect(summary, contains('#原文-tag'));
      expect(
        summary,
        contains(locale == AppLocale.en ? 'With reminder' : '含提醒'),
      );
    });

    test('habit template summary keeps reminder time and unit in $locale', () {
      I18n.setLocale(locale);
      final template = QuickCaptureTemplate(
        name: '习惯原文',
        kind: QuickCaptureTemplateKind.habit,
        habitTargetCount: 30,
        habitUnit: '分钟 literal',
        habitCategory: '学习 literal',
        habitRemind: true,
        habitRemindHour: 7,
        habitRemindMinute: 5,
      );
      expect(QuickCaptureUiCopy.templateSummary(template), contains('07:05'));
      expect(
        QuickCaptureUiCopy.templateSummary(template),
        contains('分钟 literal'),
      );
      expect(
        QuickCaptureUiCopy.templateSummary(template),
        contains('学习 literal'),
      );
    });
  }

  test(
    'built-in presentation changes language without changing stored fields',
    () {
      final template = QuickCaptureTemplate.builtIns().first;
      final payload = template.toJson();
      I18n.setLocale(AppLocale.en);
      expect(QuickCaptureUiCopy.templateName(template), 'Work meeting');
      expect(template.toJson(), payload);
      expect(QuickCaptureUiCopy.templateSummary(template), contains('Work'));
      expect(
        QuickCaptureUiCopy.templateSummary(template),
        contains('#Meeting'),
      );
      expect(
        QuickCaptureUiCopy.templateSummary(
          QuickCaptureTemplate.builtIns().last,
        ),
        contains('30 minutes'),
      );
      expect(
        QuickCaptureUiCopy.templateSummary(
          QuickCaptureTemplate.builtIns().last,
        ),
        contains('Learning'),
      );
      I18n.setLocale(AppLocale.zh);
      expect(QuickCaptureUiCopy.templateName(template), '工作会议');
    },
  );
}
