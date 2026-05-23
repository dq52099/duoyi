import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('calendar project detail is a separate project action', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains("label: const Text('项目详情')"));
    expect(source, contains('Future<void> _showProjectDetail'));
    expect(source, contains('class _ProjectStat'));
    expect(source, contains("label: const Text('打开待办')"));
    expect(source, contains('const BrandRouteSurface(child: TodoScreen())'));

    expect(source, isNot(contains("title: '\${option.name} · 项目详情'")));
    expect(source, contains("title: '项目详情'"));
    expect(source, contains('subtitle: option.name'));
  });

  test('calendar detail area and paging are widened for dense views', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('isScrollable: true'));
    expect(source, contains('tabAlignment: TabAlignment.start'));
    expect(
      source,
      contains('labelPadding: const EdgeInsets.symmetric(horizontal: 18)'),
    );
    expect(
      source,
      contains("key: const ValueKey('calendar_navigation_date_button')"),
    );
    expect(source, contains('height: 60'));
    expect(source, contains('minimumSize: const Size(double.infinity, 54)'));
    expect(
      source,
      contains("key: const ValueKey('calendar_month_detail_agenda')"),
    );
    expect(source, contains('constraints.maxHeight >= 520'));
    expect(source, contains('maxWidth: 920'));
    expect(source, contains('width: 380'));
    expect(source, contains('workspaceId: workspaceId'));
  });

  test('calendar exposes shared workspace filters', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final model = File('lib/models/calendar_event.dart').readAsStringSync();
    final provider = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();
    final aggregator = File(
      'lib/core/calendar_aggregator.dart',
    ).readAsStringSync();

    expect(model, contains('final String? workspaceId;'));
    expect(aggregator, contains('workspaceId: t.workspaceId'));
    expect(provider, contains('String? workspaceId'));
    expect(provider, contains('bool _matchesWorkspace('));
    expect(source, contains("label: const Text('全部空间')"));
    expect(
      source,
      contains('List<_CalendarWorkspaceOption> _workspaceOptions('),
    );
    expect(source, contains('workspaceId: effectiveWorkspaceId'));
    expect(source, contains('class _CalendarWorkspaceOption'));
  });
}
