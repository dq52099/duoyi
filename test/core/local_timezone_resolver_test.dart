import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:duoyi/core/local_timezone_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  test('默认跟随手机系统时区，例如墨西哥城', () async {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'America/Mexico_City';

    await LocalTimezoneResolver.init();

    expect(LocalTimezoneResolver.currentIana, 'America/Mexico_City');
    expect(tz.local.name, 'America/Mexico_City');
  });

  test('flutter_timezone 返回 UTC 时优先使用 Android 原生手机时区', () async {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async =>
        'America/Mexico_City';

    await LocalTimezoneResolver.refresh();

    expect(LocalTimezoneResolver.currentIana, 'America/Mexico_City');
    expect(tz.local.name, 'America/Mexico_City');
  });

  test('系统和原生都只返回 UTC 类时区时才回退应用默认时区', () async {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'Etc/UTC';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async => 'GMT';

    await LocalTimezoneResolver.refresh();

    expect(LocalTimezoneResolver.currentIana, 'Asia/Shanghai');
    expect(tz.local.name, isNot(anyOf('UTC', 'Etc/UTC', 'GMT', 'Etc/GMT')));
  });

  test('Android 非 IANA 的墨西哥时区名称会归一为墨西哥城', () async {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Central Standard Time (Mexico)';

    await LocalTimezoneResolver.refresh();

    expect(LocalTimezoneResolver.currentIana, 'America/Mexico_City');
    expect(tz.local.name, 'America/Mexico_City');
  });

  test('固定保存的 UTC 会被迁移回应用默认时区', () async {
    SharedPreferences.setMockInitialValues({
      LocalTimezoneResolver.modePreferenceKey: LocalTimezoneResolver.fixedValue,
      LocalTimezoneResolver.preferenceKey: 'UTC',
    });

    await LocalTimezoneResolver.refresh();

    expect(LocalTimezoneResolver.currentIana, 'Asia/Shanghai');
    expect(tz.local.name, isNot('UTC'));
  });

  test('用户仍可手动固定应用内时区并写入本地偏好', () async {
    SharedPreferences.setMockInitialValues({});

    await LocalTimezoneResolver.setApplicationTimeZone('Asia/Tokyo');
    final prefs = await SharedPreferences.getInstance();

    expect(LocalTimezoneResolver.currentIana, 'Asia/Tokyo');
    expect(tz.local.name, 'Asia/Tokyo');
    expect(prefs.getString(LocalTimezoneResolver.preferenceKey), 'Asia/Tokyo');
  });
}
