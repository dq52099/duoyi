import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Daily rollover recurring goal materialization is wired on startup/resume',
    () {
      final policy = File(
        'lib/core/completion_visibility_policy.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();

      expect(policy, contains('materializeTodayFromRecurring'));
      expect(policy, contains('已由冷启动和 `AppLifecycleState.resumed` 跨天路径传入'));
      expect(policy, isNot(contains('目前还未接入')));
      expect(policy, isNot(contains('先留占位')));
      expect(policy, contains('GoalProvider? goalProvider'));
      expect(policy, contains('goals: goalProvider.goals'));
      expect(policy, contains('await goalProvider.onTimezoneChanged()'));

      final startup = main.indexOf("'daily rollover'");
      final startupEnd = main.indexOf('// 提醒调度器', startup);
      expect(startup, greaterThanOrEqualTo(0));
      expect(startupEnd, greaterThan(startup));
      final startupBlock = main.substring(startup, startupEnd);
      expect(
        startupBlock,
        contains('CompletionVisibilityPolicy.runDailyRollover'),
      );
      expect(startupBlock, contains('goalProvider: goalProvider'));

      final resume = main.indexOf('void _maybeRunDailyRolloverOnResume()');
      final resumeEnd = main.indexOf('@override', resume);
      expect(resume, greaterThanOrEqualTo(0));
      expect(resumeEnd, greaterThan(resume));
      final resumeBlock = main.substring(resume, resumeEnd);
      expect(
        resumeBlock,
        contains('final goalProv = Provider.of<GoalProvider>'),
      );
      expect(
        resumeBlock,
        contains('CompletionVisibilityPolicy.runDailyRollover'),
      );
      expect(resumeBlock, contains('goalProvider: goalProv'));
    },
  );
}
