import 'dart:io';

import 'package:test/test.dart';

import '../test_support/bash_test_utils.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duoyi-alignment-report-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'alignment report validator passes complete eight-group report',
    () async {
      _writeReport(tempDir);

      final result = await _runValidator(tempDir);

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      expect(result.stdout, contains('Alignment report validation passed.'));
    },
  );

  test('alignment report validator fails when a group is missing', () async {
    _writeReport(tempDir, omitGroup: '7/8 debug APK build');

    final result = await _runValidator(tempDir);

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('summary.tsv missing group: 7/8 debug APK build'),
    );
  });

  test('alignment report validator fails when a log is empty', () async {
    _writeReport(
      tempDir,
      emptyLogFor: '8/8 device-only notification alarm widget regression',
    );

    final result = await _runValidator(tempDir);

    expect(result.exitCode, isNot(0));
    expect(_combinedOutput(result), contains('empty file:'));
  });

  for (final count in [1, 4]) {
    test(
      'alignment report accepts $count recognized acceptance groups',
      () async {
        _writeReport(
          tempDir,
          extraGroups: _acceptanceGroups.take(count).toList(),
        );
        final result = await _runValidator(tempDir);
        expect(result.exitCode, 0, reason: _combinedOutput(result));
      },
    );
  }

  for (final group in ['7/8 debug APK build', ..._acceptanceGroups]) {
    test('alignment report rejects duplicate $group', () async {
      _writeReport(tempDir, extraGroups: [..._acceptanceGroups, group]);
      final result = await _runValidator(tempDir);
      expect(result.exitCode, isNot(0));
      expect(_combinedOutput(result), contains('duplicate group: $group'));
    });
  }

  test('expanded rows cannot replace a mandatory legacy gate', () async {
    _writeReport(
      tempDir,
      omitGroup: '7/8 debug APK build',
      extraGroups: _acceptanceGroups,
    );
    final result = await _runValidator(tempDir);
    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('missing group: 7/8 debug APK build'),
    );
  });

  for (final unknown in ['other acceptance', 'group']) {
    test('alignment report rejects unknown row $unknown', () async {
      _writeReport(tempDir, extraGroups: [unknown]);
      final result = await _runValidator(tempDir);
      expect(result.exitCode, isNot(0));
      expect(_combinedOutput(result), contains('unknown group: $unknown'));
    });
  }

  test('the final acceptance row is validated without a trailing newline', () async {
    _writeReport(tempDir, extraGroups: _acceptanceGroups);
    final summary = File('${tempDir.path}/summary.tsv');
    final lines = summary.readAsLinesSync();
    final fields = lines.last.split('\t');
    fields[1] = 'unverified';
    lines[lines.length - 1] = fields.join('\t');
    summary.writeAsStringSync(lines.join('\n'));
    final result = await _runValidator(tempDir);
    expect(result.exitCode, isNot(0));
    expect(_combinedOutput(result), contains('invalid status'));
  });

  test(
    'expanded rows retain status duration column and log validation',
    () async {
      _writeReport(
        tempDir,
        extraGroups: _acceptanceGroups,
        emptyLogFor: _acceptanceGroups.first,
      );
      final summary = File('${tempDir.path}/summary.tsv');
      final lines = summary.readAsLinesSync();
      final fields = lines.last.split('\t');
      fields[1] = 'approved';
      fields[2] = 'later';
      lines[lines.length - 1] = '${fields.join('\t')}\textra';
      summary.writeAsStringSync('${lines.join('\n')}\n');
      final result = await _runValidator(tempDir);
      expect(result.exitCode, isNot(0));
      for (final message in [
        'exactly four columns',
        'invalid status',
        'invalid duration',
        'empty file:',
      ]) {
        expect(_combinedOutput(result), contains(message));
      }
    },
  );
}

const _acceptanceGroups = [
  'default iOS visual acceptance',
  'global localization acceptance',
  'settings flow acceptance',
  'mobile performance acceptance',
];

Future<ProcessResult> _runValidator(Directory reportDir) {
  return Process.run(
    'bash',
    ['scripts/validate_alignment_report.sh'],
    workingDirectory: Directory.current.path,
    environment: bashEnvironment(
      {'REPORT_DIR': reportDir.path},
      pathVariables: {'REPORT_DIR'},
    ),
    includeParentEnvironment: true,
  );
}

void _writeReport(
  Directory dir, {
  String? omitGroup,
  String? emptyLogFor,
  List<String> extraGroups = const [],
}) {
  final groups = <String>[
    '1/8 404 and route contracts',
    '2/8 style layout and readable selection',
    '3/8 notification ringtone and status progress',
    '4/8 widgets Android and iOS static contracts',
    '5/8 admin groups default coins and permissions',
    '6/8 Flutter analyzer',
    '7/8 debug APK build',
    '8/8 device-only notification alarm widget regression',
    ...extraGroups,
  ];

  final summary = StringBuffer('group\tstatus\tduration_seconds\tlog\n');
  final markdown = StringBuffer('''# Alignment Regression Gate

| Group | Status | Duration | Log |
| --- | --- | ---: | --- |
''');
  for (final group in groups) {
    if (group == omitGroup) {
      continue;
    }
    final log = File('${dir.path}/${_slug(group)}.log');
    log.writeAsStringSync(group == emptyLogFor ? '' : 'log for $group');
    final logPath = bashPath(log.path);
    final status = group.startsWith('8/8') ? 'failed(2)' : 'passed';
    summary.writeln('$group\t$status\t1\t$logPath');
    markdown.writeln('| $group | $status | 1s | `$logPath` |');
  }
  File('${dir.path}/summary.tsv').writeAsStringSync(summary.toString());
  File('${dir.path}/summary.md').writeAsStringSync(markdown.toString());
}

String _slug(String value) {
  return value.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
}

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}
