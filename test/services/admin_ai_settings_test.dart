import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('admin AI test button uses the admin diagnostic endpoint', () {
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(
      adminApi,
      contains('Future<Map<String, dynamic>> testAi()'),
    );
    expect(adminApi, contains("client.post('/api/admin/ai/test'"));
    expect(adminApi, contains("const Duration(seconds: 75)"));
    expect(adminApi, isNot(contains("testAiChatProxy")));
    expect(adminScreen, contains("widget.api.getSettings(scope: 'ai')"));
    expect(adminScreen, contains('widget.api.testAi()'));
    expect(adminScreen, contains("res['content'] ?? res['sample']"));
    expect(adminScreen, isNot(contains('widget.api.testAiChatProxy()')));
  });
}
