import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'startup keeps heavy reload sync notification and widget work staggered',
    () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(main, contains('Future<void> _runStartupIdleQueue('));
      expect(main, contains('Future<void> _runSyncReloadTasksInBatches('));
      expect(main, contains('await _yieldForNextFrame();'));
      expect(main, contains("'deferred local storage'"));
      expect(main, contains("'server config refresh'"));
      expect(main, contains("'auth profile refresh'"));
      expect(main, contains("'notification quick add'"));
      expect(main, contains("'initial home widget push'"));
      expect(main, contains('initialDelay: const Duration(seconds: 5)'));
      expect(main, contains('gap: const Duration(seconds: 3)'));
      expect(main, contains('delay: const Duration(seconds: 14)'));
      expect(main, contains('delay: const Duration(seconds: 9)'));
      expect(main, contains('Timer(const Duration(milliseconds: 2200)'));
      expect(main, contains('var homeWidgetPushInFlight = false'));
      expect(main, contains('homeWidgetPushQueued = true'));
      expect(
        main,
        isNot(contains('_builtTabs.contains(tab) && tab == safeIndex')),
        reason: '已访问底部 tab 必须保留挂载，避免返回日历/习惯/专注时整页重建。',
      );
    },
  );
}
