import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('today detail fallback routes keep branded background', () {
    final source = File(
      'lib/screens/today_detail_router.dart',
    ).readAsStringSync();

    expect(source, contains('BrandRouteSurface(child: child)'));
    expect(source, contains('return _brandRoute(_DetailFallback('));
    expect(
      source,
      contains('await Navigator.push(\n        context,\n        _brandRoute('),
    );
    expect(
      source,
      isNot(contains('builder: (_) => _DetailFallback(')),
      reason: 'Fallback routes should not expose a transparent/black backing.',
    );
  });

  test('recovery retains locale state and replaces its own guarded route', () {
    final source = File(
      'lib/screens/today_detail_router.dart',
    ).readAsStringSync();
    expect(source, contains('implements LocaleStatePreservingRoute'));
    expect(source, contains('if (!context.mounted) return;'));
    expect(source, contains('ModalRoute.of(context)?.isCurrent != true'));
    expect(source, contains('origin.accountGeneration'));
    expect(source, contains('pushReplacement<void, void>(route)'));
    expect(source, contains('SingleChildScrollView('));
    expect(source, isNot(contains(r"message: '打开失败：$")));
  });
}
