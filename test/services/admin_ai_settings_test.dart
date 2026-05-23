import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('admin AI test button uses the admin diagnostic endpoint', () {
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(adminApi, contains('Future<Map<String, dynamic>> testAi()'));
    expect(adminApi, contains("client.post('/api/admin/ai/test'"));
    expect(adminApi, contains("const Duration(seconds: 75)"));
    expect(adminApi, isNot(contains("testAiChatProxy")));
    expect(adminScreen, contains("widget.api.getSettings(scope: 'ai')"));
    expect(adminScreen, contains('widget.api.testAi()'));
    expect(adminScreen, contains("res['content'] ?? res['sample']"));
    expect(adminScreen, contains("res['enabled'] == false"));
    expect(adminScreen, contains('配置完整，但 AI 功能开关未启用'));
    expect(adminScreen, isNot(contains('widget.api.testAiChatProxy()')));

    final backend = File('backend/main.py').readAsStringSync();
    expect(backend, contains('def _ai_chat_completions_url'));
    expect(backend, contains('base.endswith("/v1")'));
    expect(backend, contains('"enabled": False'));
    expect(backend, contains('未发起上游请求'));
    expect(
      backend,
      isNot(contains('raise HTTPException(status_code=503, detail="AI 未启用")')),
    );
  });
}
