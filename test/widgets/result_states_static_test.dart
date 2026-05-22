import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('result_states.dart 统一导出 EmptyState/LoadingState/ErrorState', () {
    final source = File('lib/widgets/result_states.dart').readAsStringSync();
    final emptyState = File('lib/widgets/empty_state.dart').readAsStringSync();
    final auditor = File('lib/core/empty_surface_auditor.dart').readAsStringSync();
    final checklist = File('docs/empty-surface-audit.md').readAsStringSync();
    final router = File(
      'lib/screens/today_detail_router.dart',
    ).readAsStringSync();

    expect(source, contains("export 'empty_state.dart' show EmptyState;"));
    expect(source, contains('class LoadingState extends StatefulWidget'));
    expect(source, contains('class ErrorState extends StatelessWidget'));
    expect(source, contains('AnimationController'));
    expect(source, contains('ShaderMask'));
    expect(source, contains('FilledButton.tonalIcon'));
    expect(source, contains("title = '出错了'"));

    expect(emptyState, contains('class EmptyState extends StatelessWidget'));
    expect(auditor, contains("file: 'lib/widgets/result_states.dart'"));
    expect(auditor, contains('EmptyState / LoadingState / ErrorState 三件套已实现'));
    expect(auditor, contains("fixTicketId: '20'"));
    expect(checklist, contains('| `lib/widgets/result_states.dart` |'));
    expect(
      checklist,
      contains('`EmptyState / LoadingState / ErrorState` 三件套已实现并统一导出'),
    );
    expect(checklist, contains('✅ **20**'));
    expect(router, isNot(contains('Task 20 会补齐')));
  });
}
