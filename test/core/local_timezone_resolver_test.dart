import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:duoyi/core/local_timezone_resolver.dart';

void main() {
  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
  });

  test('默认跟随手机系统时区，例如墨西哥城', () async {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'America/Mexico_City';

    await LocalTimezoneResolver.init();

    expect(LocalTimezoneResolver.currentIana, 'America/Mexico_City');
    expect(tz.local.name, 'America/Mexico_City');
  });

  test('系统只返回 UTC 时才回退应用默认时区', () async {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';

    await LocalTimezoneResolver.refresh();

    expect(LocalTimezoneResolver.currentIana, 'Asia/Shanghai');
    expect(tz.local.name, isNot('UTC'));
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
