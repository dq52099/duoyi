import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('用户反馈 UI 静态回归', () {
    test('黄历宜忌条目在列内容区内缩放，避免 6 月 28 日宜项溢出', () {
      final source = File('lib/screens/almanac_screen.dart').readAsStringSync();
      final panel = _sourceBlock(
        source,
        'class _VerticalYijiPanel extends StatelessWidget',
        'class _VerticalYijiColumn extends StatelessWidget',
      );
      final column = _sourceBlock(
        source,
        'class _VerticalYijiColumn extends StatelessWidget',
        'class _VerticalTerm extends StatelessWidget',
      );

      expect(panel, contains('static const int _visibleTermLimit = 5'));
      expect(
        panel,
        contains(').take(_visibleTermLimit).toList(growable: false)'),
      );
      expect(column, contains('Expanded('));
      expect(column, contains('FittedBox('));
      expect(column, contains('fit: BoxFit.scaleDown'));
      expect(
        column,
        contains("ValueKey('almanac_vertical_\${keyName}_terms_box')"),
      );
      expect(column, contains('mainAxisSize: MainAxisSize.min'));
    });

    test('我的 AI 回顾默认折叠，摘要常驻，正文手动展开', () {
      final source = File('lib/screens/mine_screen.dart').readAsStringSync();
      final card = _sourceBlock(
        source,
        'class _AiWeeklyReviewCardState extends State<_AiWeeklyReviewCard>',
        'class _TileGroup extends StatelessWidget',
      );

      expect(card, contains('bool _reviewExpanded = false;'));
      expect(card, contains('_reviewExpanded = false;'));
      expect(card, contains('_reviewExpanded = true;'));
      expect(card, contains("key: const ValueKey('mine_ai_review_toggle')"));
      expect(card, contains("key: const ValueKey('mine_ai_review_content')"));
      expect(card, contains("tooltip: _reviewExpanded ? '收起回顾' : '展开回顾'"));
      expect(card, contains('ClipRect('));
      expect(card, contains('AnimatedSize('));
      expect(card, contains('_reviewExpanded'));
      expect(card, contains('const SizedBox.shrink()'));
      expect(card, contains("label: const Text('展开完整回顾')"));
    });

    test('纪念日和生日列表沿用倒数日式摘要与最近日期提示', () {
      final source = File(
        'lib/screens/anniversary_screen.dart',
      ).readAsStringSync();
      final body = _sourceBlock(
        source,
        'final listTitle = fixedType == AnniversaryType.birthday',
        'class _AnniversarySummaryStat extends StatelessWidget',
      );

      expect(body, contains('fixedType == AnniversaryType.birthday'));
      expect(body, contains('I18n.tr(\'anniversary.birthday\')'));
      expect(body, contains('I18n.tr(\'anniversary.title\')'));
      expect(body, contains('AppSectionHeader('));
      expect(body, contains("I18n.tr('countdown.nearest.prefix')"));
      expect(body, contains("I18n.tr('countdown.nearest.days_prefix')"));
      expect(body, contains("I18n.tr('countdown.summary.total')"));
      expect(body, contains("'anniversary.summary.within_30_days'"));
      expect(body, contains("'anniversary_summary_total'"));
      expect(body, contains("'anniversary_summary_within_30_days'"));
    });
  });
}

String _sourceBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNonNegative, reason: endMarker);
  return source.substring(start, end);
}
