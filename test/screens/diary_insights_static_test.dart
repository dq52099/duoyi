import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日记页展示 AI 日记洞察', () {
    final source = File('lib/screens/diary_screen.dart').readAsStringSync();

    expect(source, contains("import '../core/diary_insights.dart';"));
    expect(source, contains('DiaryInsightEngine.buildInsights(entries)'));
    expect(source, contains('_DiaryInsightCard'));
    expect(source, contains("I18n.tr('diary.ai.insights')"));
    expect(source, contains('DiaryInsightKind.emotionTrend'));
    expect(source, contains('DiaryInsightKind.attention'));
  });

  test('日记页接入 AI 深度复盘入口', () {
    final screen = File('lib/screens/diary_screen.dart').readAsStringSync();
    final service = File('lib/services/ai_service.dart').readAsStringSync();

    expect(screen, contains("import '../services/ai_service.dart';"));
    expect(screen, contains("I18n.tr('diary.ai.deep_review.tooltip')"));
    expect(screen, contains('_runDeepDiaryReview(context, entries)'));
    expect(screen, contains('context.read<AiService>()'));
    expect(screen, contains('ai.deepDiaryReview(entries: entries)'));
    expect(screen, contains("I18n.tr('diary.ai.deep_review.title')"));
    expect(screen, contains("I18n.tr('diary.ai.review_failed_prefix')"));

    expect(service, contains("import '../core/diary_deep_review.dart';"));
    expect(service, contains('Future<String> deepDiaryReview('));
    expect(service, contains('DiaryDeepReviewBuilder.build('));
    expect(service, contains('maxTokens: 1200'));
    expect(service, contains('日记深度复盘：'));
  });
}
