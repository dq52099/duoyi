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

  test('旧版底部导航偏好升级后保留我的和小组件并限制 5 个', () async {
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
    expect(provider.bottomNavVisible.length, lessThanOrEqualTo(5));
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
    expect(provider.bottomNavVisible.length, lessThanOrEqualTo(5));

    await provider.setBottomNavVisible(5, false);
    await provider.setBottomNavVisible(6, false);

    expect(provider.bottomNavVisible.contains(5), isTrue);
    expect(provider.bottomNavVisible.contains(6), isTrue);
  });

  test('底部导航最多显示 5 个入口，新增入口超过上限时不生效', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_bottom_nav_order': <String>['0', '1', '2', '3', '4', '5', '6'],
      'pref_bottom_nav_visible': <String>['0', '1', '2', '5', '6'],
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.bottomNavVisible, <int>{0, 1, 2, 5, 6});
    await provider.setBottomNavVisible(3, true);
    expect(provider.bottomNavVisible, <int>{0, 1, 2, 5, 6});

    await provider.setBottomNavVisible(2, false);
    await provider.setBottomNavVisible(3, true);
    expect(provider.bottomNavVisible, <int>{0, 1, 3, 5, 6});
  });

  test('底部导航设置将小组件和我的标记为固定显示并提示上限', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class BottomNavSettingsScreen'));
    expect(source, contains('const _BottomNavSettingsSection()'));
    expect(source, contains('lockedVisible = tab == 5 || tab == 6'));
    expect(source, contains("I18n.tr('preferences.nav.fixed')"));
    expect(source, contains('onChanged: lockedVisible'));
    expect(source, contains('PreferencesProvider.maxBottomNavTabs'));
    expect(source, contains('reachedLimit'));
    expect(source, contains('? null'));
  });

  test('主导航兜底也限制最多 5 个入口', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains('static const _fallbackVisibleTabs = <int>[1, 2, 3, 5, 6]'),
    );
    expect(source, contains('List<int> _visibleBottomNavTabs'));
    expect(source, contains('PreferencesProvider.maxBottomNavTabs'));
    expect(source, isNot(contains('const [0, 1, 2, 3, 4, 5, 6]')));
  });

  test('个性设置页二级菜单按场景分组', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class _PreferenceMenuGroup'));
    expect(source, contains('_PreferenceSectionMenu('));
    expect(source, contains("title: '入口提醒'"));
    expect(source, contains("title: '显示默认'"));
    expect(source, contains("label: '通知设置'"));
    expect(source, contains("label: '导航入口'"));
    expect(source, contains("label: '日期日历'"));
    expect(source, contains("label: '默认行为'"));
    expect(source, contains("label: '交互归档'"));
  });

  test('我的页中个性设置和底部导航栏跳转到不同页面', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();

    final preferencesStart = source.indexOf("label: '个性设置'");
    final bottomNavStart = source.indexOf("label: '底部导航栏'");
    expect(preferencesStart, greaterThanOrEqualTo(0));
    expect(bottomNavStart, greaterThan(preferencesStart));

    final preferencesEntry = source.substring(preferencesStart, bottomNavStart);
    final bottomNavEnd = source.indexOf("label: '应用锁'", bottomNavStart);
    expect(bottomNavEnd, greaterThan(bottomNavStart));
    final bottomNavEntry = source.substring(bottomNavStart, bottomNavEnd);

    expect(preferencesEntry, contains('const PreferencesScreen()'));
    expect(bottomNavEntry, contains('const BottomNavSettingsScreen()'));
    expect(
      source,
      isNot(contains('initialSection: PreferencesInitialSection.bottomNav')),
    );
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
