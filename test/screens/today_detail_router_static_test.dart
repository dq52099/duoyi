import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('today detail fallback routes keep branded background', () {
    final source = File(
      'lib/screens/today_detail_router.dart',
    ).readAsStringSync();

    expect(source, contains('BrandRouteSurface(child: child)'));
    expect(source, contains('return _brandRoute(\n      _DetailFallback('));
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
}
