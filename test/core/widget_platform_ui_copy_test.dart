import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('preview sample dates and labels stay consistent in both languages', () {
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      expect(
        WidgetUiCopy.sampleHeaderDate('Sample', date: DateTime(2026, 12, 3)),
        contains(locale == AppLocale.zh ? '12/03' : 'Dec 3'),
      );
      expect(WidgetUiCopy.scheduleItem1, startsWith('09:00'));
      expect(WidgetUiCopy.scheduleItem2, startsWith('14:30'));
      expect(WidgetUiCopy.scheduleItem3, startsWith('19:00'));
      expect(WidgetUiCopy.courseItem3, contains('5-6'));
      expect(
        WidgetUiCopy.calendarCurrentDate,
        locale == AppLocale.zh ? '5月17日 · 周日' : 'May 17 · Sunday',
      );
      expect(
        WidgetUiCopy.calendarCurrentDay,
        locale == AppLocale.zh ? '5月17日' : 'May 17',
      );
      expect(
        WidgetUiCopy.focusTimerUnit,
        locale == AppLocale.zh ? '分钟' : 'min',
      );
      expect(
        WidgetUiCopy.diaryItem1,
        startsWith(locale == AppLocale.zh ? '5/17' : 'May 17'),
      );
      expect(
        WidgetUiCopy.previewNavLabels.first,
        locale == AppLocale.zh ? '待办' : 'Tasks',
      );
      for (final kind in WidgetPreviewKind.values) {
        final title = WidgetUiCopy.previewSampleBadge(
          WidgetUiCopy.previewTitle(kind),
        );
        expect(
          title,
          startsWith(locale == AppLocale.zh ? '示例 · ' : 'Sample · '),
        );
        expect(title, isNot(contains('预览')));
      }
    }
  });

  test(
    'iOS widget instructions use the system gallery and supported sizes',
    () {
      I18n.setLocale(AppLocale.en);
      final help = WidgetUiCopy.hostHelpMessage(WidgetHostPlatform.ios);
      expect(help, contains('widget gallery'));
      expect(help, contains('Duoyi'));
      expect(help, contains('Small, medium and large'));
      expect(help, contains('supported iPads'));
      expect(help, contains('iPhone (iOS 16+)'));
      expect(help, contains('iPad (iPadOS 17+)'));
      expect(help, contains('Lock Screen'));
      expect(help, contains('Customize'));
      expect(help, isNot(contains('Android')));
      expect(help, isNot(contains('2×2')));
      expect(
        WidgetUiCopy.hostStyleDescription('standard', WidgetHostPlatform.ios),
        contains('system gallery'),
      );
      expect(
        WidgetUiCopy.hostStyleSyncSuccess('Standard', WidgetHostPlatform.ios),
        isNot(contains('Long press')),
      );
      I18n.setLocale(AppLocale.zh);
      final chinese = WidgetUiCopy.hostHelpMessage(WidgetHostPlatform.ios);
      expect(chinese, contains('iPhone（iOS 16 及以上）'));
      expect(chinese, contains('iPad（iPadOS 17 及以上）'));
      expect(chinese, contains('锁定屏幕'));
      expect(chinese, contains('自定'));
    },
  );

  test('Manual widget guidance has live bilingual copy for every host', () {
    for (final platform in [
      WidgetHostPlatform.ios,
      WidgetHostPlatform.web,
      WidgetHostPlatform.desktop,
    ]) {
      I18n.setLocale(AppLocale.zh);
      final chinese = WidgetUiCopy.hostHelpMessage(platform);
      expect(chinese, matches(RegExp(r'[\u3400-\u9fff]')));
      I18n.setLocale(AppLocale.en);
      for (final copy in [
        WidgetUiCopy.hostHelpMessage(platform),
        WidgetUiCopy.hostHelpTitle(platform),
        WidgetUiCopy.hostSupportTitle(platform),
        WidgetUiCopy.hostSupportMessage(platform),
        WidgetUiCopy.hostAddAction(platform),
        WidgetUiCopy.hostTipsMessage(platform),
        WidgetUiCopy.hostStyleDescription('compact', platform),
      ]) {
        expect(copy, isNotEmpty);
        expect(copy, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
      }
      expect(WidgetUiCopy.hostHelpMessage(platform), isNot(chinese));
    }
  });

  test('Android host copy uses Android style and help contracts', () {
    for (final locale in [AppLocale.zh, AppLocale.en]) {
      I18n.setLocale(locale);
      expect(
        WidgetUiCopy.hostStyleDescription(
          'detailed',
          WidgetHostPlatform.android,
        ),
        WidgetUiCopy.displayModeDescription('detailed'),
      );
      expect(
        WidgetUiCopy.hostTipsMessage(WidgetHostPlatform.android),
        WidgetUiCopy.widgetTipsBannerMessage,
      );
      expect(
        WidgetUiCopy.hostStyleSyncSuccess(
          'Detailed',
          WidgetHostPlatform.android,
        ),
        WidgetUiCopy.styleSyncSuccess('Detailed'),
      );
    }
  });

  test(
    'Android style descriptions allow content to fit the available space',
    () {
      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        final isZh = locale == AppLocale.zh;
        for (final mode in ['standard', 'detailed']) {
          final description = WidgetUiCopy.hostStyleDescription(
            mode,
            WidgetHostPlatform.android,
          );
          expect(description, contains(isZh ? '可用空间' : 'available space'));
          expect(description, isNot(contains(isZh ? '两行' : 'two lines')));
          expect(description, isNot(contains(isZh ? '三行' : 'three lines')));
        }
      }
    },
  );

  for (final locale in AppLocale.values) {
    test(
      'Android size instructions match preset behavior in ${locale.name}',
      () {
        I18n.setLocale(locale);
        final isZh = locale == AppLocale.zh;
        for (final id in ['compact', 'detailed']) {
          final description = WidgetUiCopy.displayModeDescription(id);
          expect(description, contains(isZh ? '固定尺寸' : 'fixed size'));
          expect(description, isNot(contains(isZh ? '长按' : 'Touch and hold')));
        }
        expect(
          WidgetUiCopy.displayModeDescription('standard'),
          contains(isZh ? '桌面支持时' : 'if your launcher supports it'),
        );
        final tips = WidgetUiCopy.widgetTipsBannerMessage;
        expect(tips, contains(isZh ? '固定尺寸' : 'fixed sizes'));
        expect(
          tips,
          contains(isZh ? '移除后重新添加' : 'remove the widget and add it again'),
        );
        expect(tips, contains(isZh ? '桌面支持时' : 'if your launcher supports it'));
        for (final feedback in [
          WidgetUiCopy.pinInitiatedSnackBar('Custom label'),
          WidgetUiCopy.styleSyncSuccess('Custom label'),
          WidgetUiCopy.pinSupportSupportedMessage,
        ]) {
          expect(feedback, isNot(contains(isZh ? '调整大小' : 'resize')));
        }
      },
    );
  }

  for (final module in [
    'todo',
    'focus_habit',
    'habit',
    'calendar',
    'schedule',
    'goal',
    'course',
    'note',
    'anniversary',
    'diary',
  ]) {
    test('$module XML keeps fixed presets and resizable Standard', () {
      for (final mode in ['compact', 'detailed']) {
        final xml = File(
          'android/app/src/main/res/xml/duoyi_${module}_widget_info_$mode.xml',
        ).readAsStringSync();
        expect(xml, contains('android:resizeMode="none"'));
        for (final dimension in ['Width', 'Height']) {
          final min = RegExp(
            'android:minResize$dimension="([^"]+)"',
          ).firstMatch(xml)!.group(1);
          final max = RegExp(
            'android:maxResize$dimension="([^"]+)"',
          ).firstMatch(xml)!.group(1);
          expect(min, max);
        }
      }
      final standard = File(
        'android/app/src/main/res/xml/duoyi_${module}_widget_info.xml',
      ).readAsStringSync();
      expect(standard, contains('android:resizeMode="horizontal|vertical"'));
    });
  }
}
