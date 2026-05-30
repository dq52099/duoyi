import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  test('通知栏今日任务进展开关默认关闭并可持久化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.notificationTodayProgress, isFalse);

    await provider.setNotificationTodayProgress(true);
    expect(provider.notificationTodayProgress, isTrue);

    final reloaded = PreferencesProvider();
    await reloaded.loadFromStorage();
    expect(reloaded.notificationTodayProgress, isTrue);
  });
}
