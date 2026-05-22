import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('统计页四象限分布是可用分析卡片而不是未完成占位', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('四象限分布 (未完成)')));
    expect(source, isNot(contains('四象限分布(未完成)')));
    expect(source, contains('_buildQuadrantStats'));
    expect(source, contains('_QuadrantDistributionCard'));
    expect(source, contains('_QuadrantDistributionRow'));
    expect(source, contains('_QuadrantMetric'));
    expect(source, contains('四象限执行分布'));
    expect(source, contains('当前待办池'));
    expect(source, contains('按重要/紧急象限拆解未完成压力、今日到期和已完成沉淀。'));
    expect(source, contains('未完成 \${stat.activeCount} 项'));
    expect(source, contains('逾期 \${stat.overdueCount} 项'));
    expect(source, contains('今日到期 \${stat.dueTodayCount} 项'));
    expect(source, contains('完成 \${stat.completedCount} 项'));
  });

  test('统计页四象限分析覆盖四类行动建议', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    for (final text in [
      '重要紧急',
      '立即处理',
      '重要不紧急',
      '安排计划',
      '紧急不重要',
      '委派或限时',
      '不重要不紧急',
      '清理剔除',
      '优先清空逾期和今天到期事项。',
      '保持推进节奏，避免滚入紧急区。',
      '用批量处理减少被打断时间。',
      '定期归档，避免待办池膨胀。',
    ]) {
      expect(source, contains(text));
    }
  });
}
