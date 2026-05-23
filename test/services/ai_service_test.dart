import 'dart:convert';

import 'package:duoyi/services/ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'weekly review history keeps same-day generated result visible',
    () async {
      final today = DateTime(2026, 5, 23, 10);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ai_review_history': [
          jsonEncode({
            'id': 'weekly-today',
            'createdAt': today.toIso8601String(),
            'content': '今天已经生成过的周回顾',
            'summary': '本周数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
            'model': 'gpt-test',
            'kind': AiService.weeklyReviewKind,
          }),
          jsonEncode({
            'id': 'diary-today',
            'createdAt': today.toIso8601String(),
            'content': '日记复盘不应命中周回顾',
            'summary': '日记深度复盘',
            'kind': 'diary_review',
          }),
        ],
      });

      final service = AiService();
      await service.loadFromStorage();

      final cached = service.weeklyReviewForDay(today);
      expect(cached, isNotNull);
      expect(cached!.content, '今天已经生成过的周回顾');
      expect(cached.summary, contains('本周数据'));
    },
  );

  test('review entry keeps old history compatible without kind', () {
    final entry = AiReviewEntry.fromJson({
      'id': 'old',
      'createdAt': DateTime(2026, 5, 22).toIso8601String(),
      'content': '旧内容',
      'summary': '旧摘要',
      'model': 'gpt-test',
    });

    expect(entry.kind, isEmpty);
    expect(entry.toJson()['kind'], isEmpty);
  });

  test(
    'same-day weekly review lookup accepts legacy weekly summaries',
    () async {
      final today = DateTime(2026, 5, 23, 10);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ai_review_history': [
          jsonEncode({
            'id': 'legacy-weekly',
            'createdAt': today.toIso8601String(),
            'content': '旧版当天周回顾',
            'summary': '本周数据：完成 1 / 2 项待办，专注 30 分钟，习惯连续打卡 3 天。',
            'model': 'gpt-test',
          }),
        ],
      });

      final service = AiService();
      await service.loadFromStorage();

      expect(service.weeklyReviewForDay(today)?.content, '旧版当天周回顾');
    },
  );
}
