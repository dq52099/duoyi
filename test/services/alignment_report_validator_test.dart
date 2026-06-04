import 'dart:io';

import 'package:test/test.dart';

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
      contains('summary.tsv must contain exactly 8 group rows'),
    );
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
}

Future<ProcessResult> _runValidator(Directory reportDir) {
  return Process.run(
    'bash',
    ['scripts/validate_alignment_report.sh'],
    workingDirectory: Directory.current.path,
    environment: {'REPORT_DIR': reportDir.path},
    includeParentEnvironment: true,
  );
}

void _writeReport(Directory dir, {String? omitGroup, String? emptyLogFor}) {
  final groups = <String>[
    '1/8 404 and route contracts',
    '2/8 style layout and readable selection',
    '3/8 notification ringtone and status progress',
    '4/8 widgets Android and iOS static contracts',
    '5/8 admin groups default coins and permissions',
    '6/8 Flutter analyzer',
    '7/8 debug APK build',
    '8/8 device-only notification alarm widget regression',
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
    final status = group.startsWith('8/8') ? 'failed(2)' : 'passed';
    summary.writeln('$group\t$status\t1\t${log.path}');
    markdown.writeln('| $group | $status | 1s | `${log.path}` |');
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
