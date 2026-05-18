import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
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
