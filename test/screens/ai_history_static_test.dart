import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('AI 回顾历史列表支持默认折叠和逐条展开', () {
    final source = File(
      'lib/screens/ai_history_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class AiHistoryScreen extends StatefulWidget'));
    expect(
      source,
      contains('final Set<String> _expandedReviewIds = <String>{}'),
    );
    expect(source, contains("ValueKey('ai_history_toggle_\${e.id}')"));
    expect(source, contains("ValueKey('ai_history_content_\${e.id}')"));
    expect(source, contains("tooltip: expanded ? '收起回顾' : '展开回顾'"));
    expect(source, contains('overflow: TextOverflow.ellipsis'));
    expect(source, contains('maxLines: 1'));
    expect(source, contains('_expandedReviewIds.remove(e.id)'));
    expect(source, contains('_expandedReviewIds.add(e.id)'));
    expect(source, contains('AnimatedSize('));
    expect(source, contains('expanded'));
    expect(source, contains('const SizedBox.shrink()'));
  });
}
