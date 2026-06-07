import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('AI 回顾历史条目默认折叠并支持展开收起', () {
    final source = File(
      'lib/screens/ai_history_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('class _AiHistoryEntryCard extends StatefulWidget'),
    );
    expect(source, contains('bool _expanded = false'));
    expect(source, contains('maxLines: _expanded ? null : 6'));
    expect(source, contains('TextOverflow.ellipsis'));
    expect(source, contains("I18n.tr('ai_history.expand')"));
    expect(source, contains("I18n.tr('ai_history.collapse')"));
    expect(source, contains("ValueKey('ai_history_entry_\${e.id}')"));
    expect(source, contains("'ai_history_content_collapsed_\${entry.id}'"));
    expect(source, contains("'ai_history_content_expanded_\${entry.id}'"));
    expect(source, contains('Icons.expand_more_rounded'));
    expect(source, contains('Icons.expand_less_rounded'));
    expect(source, contains('ClipboardData(text: entry.content)'));
    expect(source, contains('deleteReview(entry.id)'));
  });
}
