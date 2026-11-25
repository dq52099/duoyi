import 'dart:async';

import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replayed requests keep their original account generation', () {
    var generation = 12;
    final requests = WidgetNavigationRequests(
      accountGeneration: () => generation,
    );
    final pending = requests.capture();
    expect(pending.isCurrentAccount, isTrue);
    generation++;
    expect(pending.isCurrentAccount, isFalse);
    expect(requests.capture().isCurrentAccount, isTrue);
  });

  test('a request keeps its receipt order through queue and retries', () {
    final requests = WidgetNavigationRequests();
    final first = requests.capture();
    final pending = [first];
    expect(first.isLatest, isTrue);
    final second = requests.capture();
    expect(pending.single.isLatest, isFalse);
    expect(second.isLatest, isTrue);
    expect(identical(pending.single, first), isTrue);
  });

  test('a late older hydration cannot overtake a newer navigation', () async {
    final requests = WidgetNavigationRequests();
    final older = requests.capture();
    final olderHydration = Completer<void>();
    final navigations = <String>[];
    final olderWork = () async {
      await olderHydration.future;
      if (older.isLatest) navigations.add('older');
    }();

    final newer = requests.capture();
    expect(newer.isLatest, isTrue);
    navigations.add('newer');
    olderHydration.complete();
    await olderWork;

    expect(navigations, ['newer']);
    expect(older.isLatest, isFalse);
  });

  test('another entry supersedes a date before deferred frame delivery', () {
    final requests = WidgetNavigationRequests();
    final date = requests.capture();
    final anotherEntry = requests.capture();
    expect(date.isLatest, isFalse);
    expect(anotherEntry.isLatest, isTrue);
  });
}
