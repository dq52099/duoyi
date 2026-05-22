import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android 通知栏快捷添加接入偏好、常驻通知和智能待办创建', () {
    final preferences = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final localNotifications = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    final localNotificationsStub = File(
      'lib/services/local_notifications_stub.dart',
    ).readAsStringSync();
    final preferencesScreen = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final deepLinkService = File(
      'lib/services/deep_link_service.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final i18n = File('lib/core/i18n.dart').readAsStringSync();
    final zhArb = File('lib/l10n/app_zh.arb').readAsStringSync();
    final enArb = File('lib/l10n/app_en.arb').readAsStringSync();
    final requirement = File('docs/requirement-v2.md').readAsStringSync();

    expect(preferences, contains("_kNotificationQuickAdd"));
    expect(preferences, contains("pref_notification_quick_add"));
    expect(preferences, contains("bool get notificationQuickAdd"));
    expect(preferences, contains("setNotificationQuickAdd"));
    expect(
      preferences,
      contains("_notificationQuickAdd = p.getBool(_kNotificationQuickAdd)"),
    );

    expect(localNotifications, contains("_quickAddChannelId"));
    expect(localNotifications, contains("duoyi_quick_add_ongoing_v1"));
    expect(localNotifications, contains("quickAddNotificationId = 880016"));
    expect(localNotifications, contains("showQuickAddOngoing"));
    expect(localNotifications, contains("ongoing: true"));
    expect(localNotifications, contains("autoCancel: false"));
    expect(localNotifications, contains("playSound: false"));
    expect(localNotifications, contains("enableVibration: false"));
    expect(localNotifications, contains("AndroidNotificationAction("));
    expect(localNotifications, contains("'quick_todo'"));
    expect(localNotifications, contains("AndroidNotificationActionInput"));
    expect(localNotifications, contains("'quick_focus'"));
    expect(localNotifications, contains("duoyi://action/quick_todo'"));
    expect(localNotifications, contains("Uri.encodeComponent(text)"));
    expect(localNotifications, contains("duoyi://action/start_pomodoro"));
    expect(localNotificationsStub, contains("showQuickAddOngoing"));
    expect(localNotificationsStub, contains("quickAddNotificationId = 880016"));

    expect(preferencesScreen, contains("p.notificationQuickAdd"));
    expect(
      preferencesScreen,
      contains("preferences.notification_quick_add.title"),
    );
    expect(preferencesScreen, contains("setNotificationQuickAdd"));

    expect(main, contains("_syncNotificationQuickAdd"));
    expect(
      main,
      contains("preferencesProvider.addListener(syncNotificationQuickAdd)"),
    );
    expect(main, contains("LocalNotifications.instance.showQuickAddOngoing"));
    expect(main, contains("LocalNotifications.instance.cancel"));
    expect(main, contains("LocalNotifications.quickAddNotificationId"));
    expect(main, contains("uri.queryParameters['text']"));
    expect(main, contains("SmartTodoDraftBuilder.fromText(text)"));
    expect(main, contains("todos.addTodo(draft.toTodo())"));
    expect(main, contains("action == 'quick_todo'"));
    expect(main, contains("action == 'start_pomodoro'"));
    expect(main, contains('DeepLinkService.takeInitialLink()'));
    expect(deepLinkService, contains('takeInitialLink'));
    expect(deepLinkService, contains('_isDuoyiDeepLink(uri)'));
    expect(mainActivity, contains('pendingInitialDeepLink'));
    expect(mainActivity, contains('duoyiDeepLinkFrom(intent)'));
    expect(mainActivity, contains('"takeInitialLink"'));
    expect(mainActivity, contains('channel.invokeMethod("onLink", deepLink)'));

    for (final key in const [
      'preferences.notification_quick_add.title',
      'preferences.notification_quick_add.subtitle',
    ]) {
      expect(i18n, contains("'$key'"), reason: key);
    }
    for (final arbKey in const [
      'preferencesNotificationQuickAddTitle',
      'preferencesNotificationQuickAddSubtitle',
    ]) {
      expect(zhArb, contains('"$arbKey"'), reason: arbKey);
      expect(enArb, contains('"$arbKey"'), reason: arbKey);
    }

    expect(requirement, contains("R16.1 Android 通知栏常驻快捷入口"));
    expect(requirement, contains("**[已实现 Android 基础]**"));
  });
}
