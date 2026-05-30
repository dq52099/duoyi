import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日记页面固定文案迁移到 I18n', () {
    final source = File('lib/screens/diary_screen.dart').readAsStringSync();

    for (final key in [
      'diary.title',
      'diary.write',
      'diary.empty.message',
      'diary.stats.tooltip',
      'diary.summary.title',
      'diary.summary.subtitle',
      'diary.summary.total',
      'diary.summary.this_month',
      'diary.summary.streak',
      'diary.recent.title',
      'diary.recent.records_suffix',
      'diary.entry.count_suffix',
      'diary.mood.stats.title',
      'diary.no_data',
      'diary.ai.insights',
      'diary.ai.deep_review.tooltip',
      'diary.ai.deep_review.title',
      'diary.ai.disabled',
      'diary.ai.review_failed_prefix',
      'diary.editor.date_title',
      'diary.editor.mood_prompt',
      'diary.editor.weather',
      'diary.editor.tag_hint',
      'diary.editor.content_hint',
      'diary.mood.awesome',
      'diary.mood.terrible',
      'diary.weather.sunny',
      'diary.weather.thunder',
      'action.close',
      'unit.day',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    for (final hardcoded in [
      "'日记'",
      "'写日记'",
      "'开始记录每天的心情吧'",
      "'心情统计'",
      "'记录概览'",
      "'累计、本月和连续写作状态'",
      "'累计'",
      "'本月'",
      "'连续'",
      "'最近日记'",
      "'近 30 天心情分布'",
      "'暂无数据'",
      "'AI 日记洞察'",
      "'AI 深度复盘'",
      "'AI 日记深度复盘'",
      "'AI 功能未启用，请联系管理员'",
      "'AI 日记复盘失败：'",
      "'日记日期'",
      "'今天心情如何？'",
      "'天气'",
      "'添加标签 (如: 学习、旅行)'",
      "'写下今天的故事...'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }
    expect(source, contains('cs.outlineVariant.withValues(alpha: 0.14)'));
    expect(source, contains('width: 0.45'));
    expect(source, isNot(contains('Border.all(color: Colors.grey.shade200)')));
  });
}
