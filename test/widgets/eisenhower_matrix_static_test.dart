import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('四象限预览任务按逾期完成临期状态区分显示', () {
    final source = File(
      'lib/widgets/eisenhower_matrix.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("import '../core/completion_visibility_policy.dart';"),
    );
    expect(source, contains('CompletionVisibilityPolicy.visualState'));
    expect(source, contains('CompletionVisibilityPolicy.colorFor'));
    expect(source, contains('TodoVisualState.completed'));
    expect(source, contains('TodoVisualState.overdue'));
    expect(source, contains('TodoVisualState.dueSoon'));
    expect(source, contains("isCompleted ? '已完成' : '逾期'"));
    expect(source, contains('TextDecoration.lineThrough'));
  });
}
