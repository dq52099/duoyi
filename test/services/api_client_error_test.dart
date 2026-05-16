import 'package:flutter_test/flutter_test.dart';
import 'package:duoyi/services/api_client.dart';

void main() {
  test(
    'relative API path on mobile/desktop returns friendly configuration error',
    () async {
      final client = ApiClient(baseUrl: '');

      await expectLater(
        client.get('/api/announcements'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('未配置服务器地址'),
          ),
        ),
      );
    },
  );
}
