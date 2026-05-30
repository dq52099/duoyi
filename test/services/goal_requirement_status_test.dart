import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory alignmentDir;
  late Directory goalDir;
  late Directory outputDir;
  late File matrixFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duoyi-req-status-');
    alignmentDir = Directory('${tempDir.path}/alignment')..createSync();
    goalDir = Directory('${tempDir.path}/goal')..createSync();
    outputDir = Directory('${tempDir.path}/out');
    matrixFile = File('${tempDir.path}/goal-requirement-matrix.md')
      ..writeAsStringSync(
        File('docs/goal-requirement-matrix.md').readAsStringSync(),
      );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'requirement status report keeps device-backed items open as device evidence when group 8 has no device',
    () async {
      _writeAlignmentSummary(alignmentDir, eighthStatus: 'failed(2)');
      _writeGoalSummary(
        goalDir,
        androidStatus: 'failed(1)',
        iosStatus: 'failed(1)',
      );

      final result = await _runGenerator(
        matrixFile: matrixFile,
        alignmentDir: alignmentDir,
        goalDir: goalDir,
        outputDir: outputDir,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final status = _readStatus(outputDir);
      expect(status['REQ-404'], 'closed');
      expect(status['REQ-STYLE'], 'closed');
      expect(status['REQ-ADMIN'], 'closed');
      expect(status['REQ-HABIT'], 'closed');
      expect(status['REQ-MINE'], 'closed');
      expect(status['REQ-COUNTDOWN'], 'closed');
      expect(status['REQ-ALMANAC'], 'closed');
      expect(status['REQ-NOTIFY'], 'open(device_evidence)');
      expect(status['REQ-WIDGET'], 'open(device_evidence)');
      expect(status['REQ-DEVICE'], 'open(device_evidence)');
      expect(
        _readReasons(outputDir)['REQ-DEVICE'],
        allOf(
          contains(
            'device gate=failed(2)',
          ),
          contains('android_device_evidence=failed(1)'),
          contains('ios_device_evidence=failed(1)'),
        ),
      );
      expect(
        File('${outputDir.path}/status.md').readAsStringSync(),
        contains('REQ-DEVICE'),
      );
    },
  );

  test(
    'requirement status report marks device-backed items open when only evidence is missing',
    () async {
      _writeAlignmentSummary(alignmentDir, eighthStatus: 'passed');
      _writeGoalSummary(
        goalDir,
        androidStatus: 'failed(1)',
        iosStatus: 'failed(1)',
      );

      final result = await _runGenerator(
        matrixFile: matrixFile,
        alignmentDir: alignmentDir,
        goalDir: goalDir,
        outputDir: outputDir,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final status = _readStatus(outputDir);
      expect(status['REQ-NOTIFY'], 'open(device_evidence)');
      expect(status['REQ-WIDGET'], 'open(device_evidence)');
      expect(status['REQ-DEVICE'], 'open(device_evidence)');
    },
  );

  test(
    'requirement status report is replaced instead of appended on repeated runs',
    () async {
      _writeAlignmentSummary(alignmentDir, eighthStatus: 'failed(2)');
      _writeGoalSummary(
        goalDir,
        androidStatus: 'failed(1)',
        iosStatus: 'failed(1)',
      );

      final first = await _runGenerator(
        matrixFile: matrixFile,
        alignmentDir: alignmentDir,
        goalDir: goalDir,
        outputDir: outputDir,
      );
      final second = await _runGenerator(
        matrixFile: matrixFile,
        alignmentDir: alignmentDir,
        goalDir: goalDir,
        outputDir: outputDir,
      );

      expect(first.exitCode, 0, reason: _combinedOutput(first));
      expect(second.exitCode, 0, reason: _combinedOutput(second));
      expect(
        File('${outputDir.path}/status.tsv').readAsLinesSync(),
        hasLength(11),
      );
    },
  );

  test('requirement status validator rejects duplicate rows', () async {
    outputDir.createSync(recursive: true);
    File('${outputDir.path}/status.tsv').writeAsStringSync(
      '''id\tstatus\treason\tgroups\trequirement
REQ-404\tclosed\tok\t1/8 404 and route contracts\tfirst
REQ-404\tclosed\tok\t1/8 404 and route contracts\tduplicate
''',
    );
    File(
      '${outputDir.path}/status.md',
    ).writeAsStringSync('# Goal Requirement Status\nREQ-404\nREQ-DEVICE\n');

    final result = await _runStatusValidator(outputDir);

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('status.tsv must contain exactly 10 requirement rows'),
    );
    expect(
      _combinedOutput(result),
      contains('status.tsv must contain exactly one row for REQ-404'),
    );
  });

  test(
    'requirement status validator rejects closed or gate-failed device rows without evidence',
    () async {
      _writeAlignmentSummary(alignmentDir, eighthStatus: 'failed(2)');
      _writeGoalSummary(
        goalDir,
        androidStatus: 'failed(1)',
        iosStatus: 'failed(1)',
      );
      outputDir.createSync(recursive: true);
      File('${outputDir.path}/status.tsv').writeAsStringSync(
        '''id\tstatus\treason\tgroups\trequirement
REQ-404\tclosed\tok\t1/8 404 and route contracts\t404
REQ-STYLE\tclosed\tok\t2/8 style layout and readable selection\tstyle
REQ-ADMIN\tclosed\tok\t5/8 admin groups default coins and permissions\tadmin
REQ-HABIT\tclosed\tok\t2/8 style layout and readable selection\thabit
REQ-MINE\tclosed\tok\t2/8 style layout and readable selection\tmine
REQ-COUNTDOWN\tclosed\tok\t2/8 style layout and readable selection\tcountdown
REQ-ALMANAC\tclosed\tok\t2/8 style layout and readable selection\talmanac
REQ-NOTIFY\topen(gate_failed)\t8/8 device-only notification alarm widget regression is failed(2)\t3/8 notification ringtone and status progress; 8/8 device-only notification alarm widget regression\tnotify
REQ-WIDGET\tclosed\tok\t4/8 widgets Android and iOS static contracts; 8/8 device-only notification alarm widget regression\twidget
REQ-DEVICE\topen(gate_failed)\t8/8 device-only notification alarm widget regression is failed(2)\t8/8 device-only notification alarm widget regression\tdevice
''',
      );
      File(
        '${outputDir.path}/status.md',
      ).writeAsStringSync('# Goal Requirement Status\nREQ-404\nREQ-DEVICE\n');

      final result = await _runStatusValidator(
        outputDir,
        alignmentDir: alignmentDir,
        goalDir: goalDir,
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'REQ-NOTIFY must stay open(device_evidence) until Android and iOS device evidence pass',
        ),
      );
      expect(
        _combinedOutput(result),
        contains(
          'REQ-WIDGET must stay open(device_evidence) until Android and iOS device evidence pass',
        ),
      );
      expect(
        _combinedOutput(result),
        contains(
          'REQ-DEVICE must stay open(device_evidence) until Android and iOS device evidence pass',
        ),
      );
    },
  );
}

Future<ProcessResult> _runGenerator({
  required File matrixFile,
  required Directory alignmentDir,
  required Directory goalDir,
  required Directory outputDir,
}) {
  return Process.run(
    'bash',
    ['scripts/generate_goal_requirement_status.sh'],
    workingDirectory: Directory.current.path,
    environment: {
      'MATRIX_FILE': matrixFile.path,
      'ALIGNMENT_REPORT_DIR': alignmentDir.path,
      'GOAL_REPORT_DIR': goalDir.path,
      'OUTPUT_DIR': outputDir.path,
    },
    includeParentEnvironment: true,
  );
}

Future<ProcessResult> _runStatusValidator(
  Directory outputDir, {
  Directory? alignmentDir,
  Directory? goalDir,
}) {
  return Process.run(
    'bash',
    ['scripts/validate_goal_requirement_status.sh'],
    workingDirectory: Directory.current.path,
    environment: {
      'STATUS_DIR': outputDir.path,
      if (alignmentDir != null) 'REPORT_DIR': alignmentDir.path,
      if (goalDir != null) 'GOAL_REPORT_DIR': goalDir.path,
    },
    includeParentEnvironment: true,
  );
}

void _writeAlignmentSummary(Directory dir, {required String eighthStatus}) {
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
  for (final group in groups) {
    final log = File('${dir.path}/${group.hashCode}.log')
      ..writeAsStringSync(group);
    final status = group.startsWith('8/8') ? eighthStatus : 'passed';
    summary.writeln('$group\t$status\t1\t${log.path}');
  }
  File('${dir.path}/summary.tsv').writeAsStringSync(summary.toString());
}

void _writeGoalSummary(
  Directory dir, {
  required String androidStatus,
  required String iosStatus,
}) {
  final rows = <String, String>{
    'alignment_report': 'passed',
    'goal_requirement_matrix': 'passed',
    'android_device_evidence': androidStatus,
    'ios_device_evidence': iosStatus,
  };
  final summary = StringBuffer('check\tstatus\tlog\n');
  for (final entry in rows.entries) {
    final log = File('${dir.path}/${entry.key}.log')
      ..writeAsStringSync(entry.key);
    summary.writeln('${entry.key}\t${entry.value}\t${log.path}');
  }
  File('${dir.path}/summary.tsv').writeAsStringSync(summary.toString());
}

Map<String, String> _readStatus(Directory dir) {
  final rows = File('${dir.path}/status.tsv').readAsLinesSync().skip(1);
  return {for (final row in rows) row.split('\t')[0]: row.split('\t')[1]};
}

Map<String, String> _readReasons(Directory dir) {
  final rows = File('${dir.path}/status.tsv').readAsLinesSync().skip(1);
  return {for (final row in rows) row.split('\t')[0]: row.split('\t')[2]};
}

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}
