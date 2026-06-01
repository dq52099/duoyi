import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android release allows the baked backend cleartext domain only', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final networkConfig = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    final appConfig = File('lib/core/app_config.dart').readAsStringSync();

    expect(appConfig, contains("defaultServerUrl = 'http://6688667.xyz'"));
    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(networkConfig, contains('cleartextTrafficPermitted="true"'));
    expect(networkConfig, contains('6688667.xyz'));
    expect(
      manifest,
      isNot(contains('android:usesCleartextTraffic="true"')),
      reason: '不要全局放开明文，只允许当前默认后端域名。',
    );
  });
}
