import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  test('旧版底部导航偏好升级后保留我的并加入小组件', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_default_tab': 5,
      'pref_bottom_nav_order': <String>['0', '1', '2', '3', '4', '5'],
      'pref_bottom_nav_visible': <String>['0', '1', '2', '3', '4', '5'],
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.defaultTab, 6);
    expect(provider.bottomNavOrder, <int>[0, 1, 2, 3, 4, 5, 6]);
    expect(provider.bottomNavVisible.contains(5), isTrue);
    expect(provider.bottomNavVisible.contains(6), isTrue);
  });

  test('小组件和我的入口不能被隐藏', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_bottom_nav_order': <String>['0', '1', '2', '3', '4', '5', '6'],
      'pref_bottom_nav_visible': <String>['0', '1', '2', '3', '4'],
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.bottomNavVisible.contains(5), isTrue);
    expect(provider.bottomNavVisible.contains(6), isTrue);

    await provider.setBottomNavVisible(5, false);
    await provider.setBottomNavVisible(6, false);

    expect(provider.bottomNavVisible.contains(5), isTrue);
    expect(provider.bottomNavVisible.contains(6), isTrue);
  });

  test('偏好设置页将小组件和我的标记为固定显示', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(source, contains('lockedVisible = tab == 5 || tab == 6'));
    expect(source, contains("I18n.tr('preferences.nav.fixed')"));
    expect(source, contains('onChanged: lockedVisible'));
    expect(source, contains('? null'));
  });

  test('通知记录保留数量可配置并按范围归一化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_notification_history_limit': 2000,
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.notificationHistoryLimit, 2000);

    await provider.setNotificationHistoryLimit(20);
    expect(provider.notificationHistoryLimit, 100);

    await provider.setNotificationHistoryLimit(9000);
    expect(provider.notificationHistoryLimit, 5000);
  });

  test('偏好设置页提供通知记录保留数量控制', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_notificationHistoryLimitOptions'));
    expect(source, contains("title: '通知记录保留'"));
    expect(source, contains('p.notificationHistoryLimit'));
    expect(source, contains('setNotificationHistoryLimit'));
    expect(source, contains('notif.setHistoryLimit'));
  });

  test('应用时区默认跟随手机，切换固定时区后触发提醒重同步回调', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'America/Mexico_City';

    var resyncCount = 0;
    final provider = PreferencesProvider()
      ..onAppTimeZoneChanged = () async {
        resyncCount++;
      };

    await provider.loadFromStorage();
    expect(provider.followSystemTimeZone, isTrue);
    expect(provider.appTimeZone, 'America/Mexico_City');

    await provider.setAppTimeZone('Asia/Tokyo');

    expect(provider.followSystemTimeZone, isFalse);
    expect(provider.appTimeZone, 'Asia/Tokyo');
    expect(resyncCount, 1);
  });
}
