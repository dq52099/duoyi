import 'dart:io';

import 'package:test/test.dart';

import '../test_support/bash_test_utils.dart';

void main() {
  test(
    'goal requirement matrix maps user requests to eight regression groups',
    () async {
      final result = await Process.run(
        'bash',
        ['scripts/validate_goal_requirement_matrix.sh'],
        workingDirectory: Directory.current.path,
        includeParentEnvironment: true,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      expect(
        result.stdout,
        contains('Goal requirement matrix validation passed.'),
      );
    },
  );

  test('alignment gate includes the goal requirement matrix validator', () {
    final gate = File(
      'scripts/alignment_regression_gate.sh',
    ).readAsStringSync();
    final matrix = File('docs/goal-requirement-matrix.md').readAsStringSync();
    final validator = File(
      'scripts/validate_goal_requirement_matrix.sh',
    ).readAsStringSync();

    expect(gate, contains('test/services/goal_requirement_matrix_test.dart'));
    expect(gate, contains('test/services/goal_requirement_status_test.dart'));
    expect(matrix, contains('REQ-COUNTDOWN'));
    expect(matrix, contains('Countdown remains available'));
    expect(matrix, contains('Almanac content removes weather'));
    expect(matrix, contains('REQ-NOTIFY'));
    expect(matrix, contains('default soft ringtone'));
    expect(matrix, contains('test/services/reminder_resync_static_test.dart'));
    expect(matrix, contains('test/services/reminder_email_channel_test.dart'));
    expect(matrix, contains('lib/widgets/habit_weekly_card.dart'));
    expect(matrix, isNot(contains('test/widgets/habit_weekly_card.dart')));
    expect(matrix, contains('REQ-WIDGET'));
    expect(matrix, contains('REQ-DEVICE'));
    expect(matrix, contains('scripts/generate_device_readiness_report.sh'));
    expect(matrix, contains('scripts/validate_device_readiness_report.sh'));
    expect(matrix, contains('Device readiness must be reported'));
    expect(
      matrix,
      contains('Passing groups 1-7 is necessary but not sufficient'),
    );
    expect(validator, contains('Both Android and iOS evidence must pass'));
    expect(validator, contains('validate_goal_closure.sh'));
    expect(validator, contains('extract_local_evidence_paths'));
    expect(validator, isNot(contains('api_client_error_test.dart')));
    expect(validator, isNot(contains('habit_weekly_card.dart')));
    expect(
      File('scripts/generate_goal_requirement_status.sh').existsSync(),
      isTrue,
    );
  });

  test('matrix validator rejects missing local evidence paths', () async {
    final tempDir = await Directory.systemTemp.createTemp('duoyi-goal-matrix-');
    try {
      final matrixFile = File('${tempDir.path}/goal-requirement-matrix.md')
        ..writeAsStringSync(
          File(
            'docs/goal-requirement-matrix.md',
          ).readAsStringSync().replaceFirst(
            'test/services/api_client_error_test.dart',
            'test/services/missing_matrix_evidence_test.dart',
          ),
        );

      final result = await Process.run(
        'bash',
        ['scripts/validate_goal_requirement_matrix.sh'],
        workingDirectory: Directory.current.path,
        environment: bashEnvironment(
          {'MATRIX_FILE': matrixFile.path},
          pathVariables: {'MATRIX_FILE'},
        ),
        includeParentEnvironment: true,
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'REQ-404 evidence path is missing: '
          'test/services/missing_matrix_evidence_test.dart',
        ),
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test(
    'matrix validator rejects the old nonexistent habit card path',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'duoyi-goal-matrix-',
      );
      try {
        final matrixFile = File('${tempDir.path}/goal-requirement-matrix.md')
          ..writeAsStringSync(
            File(
              'docs/goal-requirement-matrix.md',
            ).readAsStringSync().replaceFirst(
              'lib/widgets/habit_weekly_card.dart',
              'test/widgets/habit_weekly_card.dart',
            ),
          );

        final result = await Process.run(
          'bash',
          ['scripts/validate_goal_requirement_matrix.sh'],
          workingDirectory: Directory.current.path,
          environment: bashEnvironment(
            {'MATRIX_FILE': matrixFile.path},
            pathVariables: {'MATRIX_FILE'},
          ),
          includeParentEnvironment: true,
        );

        expect(result.exitCode, isNot(0));
        expect(
          _combinedOutput(result),
          contains(
            'REQ-HABIT evidence path is missing: '
            'test/widgets/habit_weekly_card.dart',
          ),
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}
