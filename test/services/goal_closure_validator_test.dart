import 'dart:io';

import 'package:test/test.dart';

import '../test_support/bash_test_utils.dart';

const _closureValidatorTimeout = Timeout(Duration(minutes: 2));

void main() {
  late Directory tempDir;
  late Directory reportDir;
  late Directory androidDir;
  late Directory iosDir;
  late Directory goalReportDir;
  late Directory statusDir;
  late File matrixFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duoyi-goal-closure-');
    reportDir = Directory('${tempDir.path}/report')..createSync();
    androidDir = Directory('${tempDir.path}/android')..createSync();
    iosDir = Directory('${tempDir.path}/ios')..createSync();
    goalReportDir = Directory('${tempDir.path}/goal-report');
    statusDir = Directory('${tempDir.path}/status-report');
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
    'goal closure validator rejects missing expanded gates despite passing legacy gates and devices',
    () async {
      _writeReport(reportDir, eighthStatus: 'passed');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
      );

      expect(result.exitCode, isNot(0), reason: _combinedOutput(result));
      expect(result.stdout, contains('alignment_report: passed'));
      expect(result.stdout, contains('alignment_report_freshness: passed'));
      expect(result.stdout, contains('goal_requirement_matrix: passed'));
      expect(result.stdout, contains('android_device_evidence: passed'));
      expect(result.stdout, contains('ios_device_evidence: passed'));
      expect(result.stdout, contains('goal_requirement_status: passed'));
      expect(
        result.stdout,
        contains('goal_requirement_status_validation: passed'),
      );
      expect(result.stdout, contains('all_requirements_closed: failed(1)'));
      expect(
        _combinedOutput(result),
        contains('Goal closure validation failed'),
      );
      expect(File('${goalReportDir.path}/summary.tsv').existsSync(), isTrue);
      expect(
        File('${goalReportDir.path}/alignment_report.log').existsSync(),
        isTrue,
      );
      expect(
        File('${goalReportDir.path}/goal_requirement_matrix.log').existsSync(),
        isTrue,
      );
      expect(
        File('${goalReportDir.path}/android_device_evidence.log').existsSync(),
        isTrue,
      );
      expect(
        File('${goalReportDir.path}/ios_device_evidence.log').existsSync(),
        isTrue,
      );
      expect(File('${statusDir.path}/status.tsv').existsSync(), isTrue);
      expect(
        File(
          '${goalReportDir.path}/goal_requirement_status.log',
        ).readAsStringSync(),
        contains(
          'Goal requirement status written to ${bashPath(statusDir.path)}',
        ),
      );
      expect(
        File(
          '${goalReportDir.path}/goal_requirement_status_validation.log',
        ).readAsStringSync(),
        contains('Goal requirement status validation passed.'),
      );
      _expectLegacyGatesLeaveExpandedRequirementsOpen(statusDir);
    },
    timeout: _closureValidatorTimeout,
  );

  test(
    'goal closure validator fails when requirement matrix is missing',
    () async {
      _writeReport(reportDir, eighthStatus: 'passed');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);
      matrixFile.deleteSync();

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('goal_requirement_matrix: failed(1)'));
      expect(
        _combinedOutput(result),
        contains('goal requirement matrix is incomplete or malformed'),
      );
      expect(
        File(
          '${goalReportDir.path}/goal_requirement_matrix.log',
        ).readAsStringSync(),
        contains('missing file:'),
      );
    },
    timeout: _closureValidatorTimeout,
  );

  test(
    'twelve passing synthetic gates close all fourteen fixture requirements',
    () async {
      _writeReport(
        reportDir,
        eighthStatus: 'passed',
        extraGroups: _expandedGates.keys.toList(),
      );
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);
      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
      );
      expect(result.exitCode, 0, reason: _combinedOutput(result));
      expect(result.stdout, contains('all_requirements_closed: passed'));
      final rows = File(
        '${statusDir.path}/status.tsv',
      ).readAsLinesSync().skip(1);
      expect(rows, hasLength(14));
      expect(rows.every((row) => row.split('\t')[1] == 'closed'), isTrue);
    },
    timeout: _closureValidatorTimeout,
  );

  for (final scenario in [
    (
      name: 'unchanged source survives append',
      source: -5,
      laterLogs: false,
      olderSummary: false,
      missingLog: false,
      runtime: false,
      olderOptional: false,
      fresh: true,
    ),
    (
      name: 'append cannot renew stale legacy evidence',
      source: 10,
      laterLogs: false,
      olderSummary: false,
      missingLog: false,
      runtime: false,
      olderOptional: false,
      fresh: false,
    ),
    (
      name: 'source change between legacy groups stays stale',
      source: 10,
      laterLogs: true,
      olderSummary: false,
      missingLog: false,
      runtime: false,
      olderOptional: false,
      fresh: false,
    ),
    (
      name: 'older summary still bounds freshness',
      source: -5,
      laterLogs: false,
      olderSummary: true,
      missingLog: false,
      runtime: false,
      olderOptional: false,
      fresh: false,
    ),
    (
      name: 'missing legacy log is unverifiable',
      source: -5,
      laterLogs: false,
      olderSummary: false,
      missingLog: true,
      runtime: false,
      olderOptional: false,
      fresh: false,
    ),
    (
      name: 'runtime churn survives append',
      source: 10,
      laterLogs: false,
      olderSummary: false,
      missingLog: false,
      runtime: true,
      olderOptional: false,
      fresh: true,
    ),
    (
      name: 'optional logs do not move the legacy bound',
      source: -5,
      laterLogs: false,
      olderSummary: false,
      missingLog: false,
      runtime: false,
      olderOptional: true,
      fresh: true,
    ),
  ]) {
    test(
      'legacy freshness bound: ${scenario.name}',
      () async {
        _writeReport(reportDir, eighthStatus: 'passed');
        _writeAndroidEvidence(androidDir);
        _writeIosEvidence(iosDir);
        final sourceRoot = _emptySourceRoot(reportDir);
        final base = DateTime.now().subtract(const Duration(minutes: 5));
        DateTime timestamp(int seconds) => base.add(Duration(seconds: seconds));
        for (final name in ['pubspec.yaml', 'pubspec.lock']) {
          File('${sourceRoot.path}/$name').setLastModifiedSync(timestamp(-100));
        }
        final summary = File('${reportDir.path}/summary.tsv');
        final legacyLogs = summary
            .readAsLinesSync()
            .skip(1)
            .map(
              (line) => File(
                '${reportDir.path}/${line.split('\t').first.hashCode}.log',
              ),
            )
            .toList();
        for (var index = 0; index < legacyLogs.length; index++) {
          legacyLogs[index].setLastModifiedSync(
            timestamp(scenario.laterLogs && index > 0 ? 20 : 0),
          );
        }
        final originalLogTimes = legacyLogs
            .map((log) => log.lastModifiedSync())
            .toList();
        // Append only the expanded results; the eight original logs stay intact.
        for (final group in _expandedGates.keys) {
          final log = File('${reportDir.path}/${group.hashCode}.log')
            ..writeAsStringSync('synthetic expanded result for $group');
          log.setLastModifiedSync(timestamp(scenario.olderOptional ? -20 : 40));
          summary.writeAsStringSync(
            '$group\tpassed\t1\t${bashPath(log.path)}\n',
            mode: FileMode.append,
          );
          File('${reportDir.path}/summary.md').writeAsStringSync(
            '| $group | passed | 1s | `${bashPath(log.path)}` |\n',
            mode: FileMode.append,
          );
        }
        summary.setLastModifiedSync(
          timestamp(scenario.olderSummary ? -10 : 40),
        );
        expect(
          legacyLogs.map((log) => log.lastModifiedSync()),
          originalLogTimes,
        );
        final path = scenario.runtime
            ? 'backend/uploads/new.png'
            : 'lib/changed.dart';
        final changed = File('${sourceRoot.path}/$path');
        changed.parent.createSync(recursive: true);
        changed.writeAsStringSync('controlled source or runtime mutation\n');
        changed.setLastModifiedSync(timestamp(scenario.source));
        if (scenario.missingLog) legacyLogs.first.deleteSync();
        final result = await _runValidator(
          reportDir,
          androidDir,
          iosDir,
          goalReportDir,
          statusDir,
          matrixFile,
          sourceRoot: sourceRoot.path,
        );
        expect(
          result.exitCode,
          scenario.fresh ? 0 : isNot(0),
          reason: _combinedOutput(result),
        );
        expect(
          result.stdout,
          contains(
            scenario.fresh
                ? 'alignment_report_freshness: passed'
                : 'alignment_report_freshness: failed(1)',
          ),
        );
        if (!scenario.fresh) {
          final diagnostic = File(
            '${goalReportDir.path}/alignment_report_freshness.log',
          ).readAsStringSync();
          expect(
            diagnostic,
            contains(
              scenario.missingLog
                  ? 'freshness could not be verified'
                  : 'alignment regression report is stale',
            ),
          );
        }
      },
      timeout: _closureValidatorTimeout,
    );
  }

  for (final entry in _expandedGates.entries) {
    for (final missing in [true, false]) {
      test(
        'expanded gate ${entry.key} ${missing ? 'missing' : 'failed'} blocks closure',
        () async {
          _writeReport(
            reportDir,
            eighthStatus: 'passed',
            extraGroups: _expandedGates.keys
                .where((gate) => !missing || gate != entry.key)
                .toList(),
            gateStatuses: missing ? const {} : {entry.key: 'failed(7)'},
          );
          _writeAndroidEvidence(androidDir);
          _writeIosEvidence(iosDir);
          final result = await _runValidator(
            reportDir,
            androidDir,
            iosDir,
            goalReportDir,
            statusDir,
            matrixFile,
          );
          expect(result.exitCode, isNot(0), reason: _combinedOutput(result));
          expect(result.stdout, contains('alignment_report: passed'));
          expect(result.stdout, contains('all_requirements_closed: failed(1)'));
          final row = File('${statusDir.path}/status.tsv')
              .readAsLinesSync()
              .map((line) => line.split('\t'))
              .singleWhere((fields) => fields.first == entry.value);
          expect(row[1], missing ? 'open(gate_missing)' : 'open(gate_failed)');
        },
        timeout: _closureValidatorTimeout,
      );
    }
  }

  for (final gate in ['6/8 Flutter analyzer', '7/8 debug APK build']) {
    test(
      'all expanded passes cannot close a failed legacy gate $gate',
      () async {
        _writeReport(
          reportDir,
          eighthStatus: 'passed',
          extraGroups: _expandedGates.keys.toList(),
          gateStatuses: {gate: 'failed(7)'},
        );
        _writeAndroidEvidence(androidDir);
        _writeIosEvidence(iosDir);
        final result = await _runValidator(
          reportDir,
          androidDir,
          iosDir,
          goalReportDir,
          statusDir,
          matrixFile,
        );
        expect(result.exitCode, isNot(0));
        expect(result.stdout, contains('alignment_report: passed'));
        expect(_combinedOutput(result), contains('failed(7)'));
        expect(result.stdout, contains('alignment_gates_passed: failed(1)'));
      },
      timeout: _closureValidatorTimeout,
    );
  }

  test(
    'twelve passing gates do not mask a failed source scan',
    () async {
      _writeReport(
        reportDir,
        eighthStatus: 'passed',
        extraGroups: _expandedGates.keys.toList(),
      );
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);
      final sourceRoot = _emptySourceRoot(reportDir);
      Directory('${sourceRoot.path}/lib').deleteSync();
      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
        sourceRoot: sourceRoot.path,
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('alignment_report_freshness: failed(1)'));
      expect(
        File(
          '${goalReportDir.path}/alignment_report_freshness.log',
        ).readAsStringSync(),
        contains('source scan failed'),
      );
    },
    timeout: _closureValidatorTimeout,
  );

  test(
    'goal closure validator fails while device-only group is failed',
    () async {
      _writeReport(reportDir, eighthStatus: 'failed(2)');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          '8/8 device-only notification alarm widget regression is not closed: failed(2)',
        ),
      );
      expect(result.stdout, contains('alignment_report: passed'));
      expect(result.stdout, contains('android_device_evidence: passed'));
      expect(result.stdout, contains('ios_device_evidence: passed'));
      expect(
        result.stderr,
        contains('Report written to ${bashPath(goalReportDir.path)}'),
      );
    },
    timeout: _closureValidatorTimeout,
  );

  test(
    'goal closure validator rejects stale alignment report',
    () async {
      _writeReport(reportDir, eighthStatus: 'passed');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);
      final sourceRoot = _emptySourceRoot(reportDir);
      final sourceFile = File('${sourceRoot.path}/lib/changed.dart');
      sourceFile.parent.createSync(recursive: true);
      sourceFile.writeAsStringSync('// changed after alignment report\n');
      sourceFile.setLastModifiedSync(
        File(
          '${reportDir.path}/summary.tsv',
        ).lastModifiedSync().add(const Duration(seconds: 10)),
      );

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
        sourceRoot: sourceRoot.path,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('alignment_report_freshness: failed(1)'));
      expect(
        File(
          '${goalReportDir.path}/alignment_report_freshness.log',
        ).readAsStringSync(),
        contains('alignment regression report is stale'),
      );
    },
    timeout: _closureValidatorTimeout,
  );

  test(
    'goal closure freshness ignores generated build caches',
    () async {
      _writeReport(reportDir, eighthStatus: 'passed');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);
      final sourceRoot = _emptySourceRoot(reportDir);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final path in [
        'android/.gradle/8.14/fileHashes/fileHashes.lock',
        'android/build/generated/build.log',
        'android/app/build/intermediates/build.log',
        'backend/__pycache__/main.cpython-310.pyc',
      ]) {
        final cache = File('${sourceRoot.path}/$path');
        cache.parent.createSync(recursive: true);
        cache.writeAsStringSync('generated after the alignment report\n');
      }

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
        sourceRoot: sourceRoot.path,
      );

      expect(result.exitCode, isNot(0), reason: _combinedOutput(result));
      expect(result.stdout, contains('alignment_report_freshness: passed'));
      expect(result.stdout, contains('all_requirements_closed: failed(1)'));
      _expectLegacyGatesLeaveExpandedRequirementsOpen(statusDir);
    },
    timeout: _closureValidatorTimeout,
  );
  test(
    'source scan failure cannot pass alignment freshness',
    () async {
      _writeReport(reportDir, eighthStatus: 'passed');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);
      final sourceRoot = _emptySourceRoot(reportDir);
      Directory('${sourceRoot.path}/lib').deleteSync();
      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
        sourceRoot: sourceRoot.path,
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('alignment_report_freshness: failed(1)'));
      expect(
        File(
          '${goalReportDir.path}/alignment_report_freshness.log',
        ).readAsStringSync(),
        contains('source scan failed'),
      );
    },
    timeout: _closureValidatorTimeout,
  );

  const runtimeOnlyPaths = <String>[
    'backend/backups',
    'backend/uploads',
    'backend/backups/current.zip',
    'backend/backups/nested/2026-11-07/duoyi.db-wal',
    'backend/backups/nested/backup script.py',
    'backend/uploads/avatar.png',
    'backend/uploads/nested/user notes/file.txt',
    'backend/uploads/nested/main.py',
    'backend/duoyi.db',
    'backend/duoyi.db-wal',
    'backend/duoyi.db-shm',
    'backend/duoyi.db-journal',
    'backend/fingertip_time.db',
    'backend/fingertip_time.db-wal',
    'backend/fingertip_time.db-shm',
    'backend/fingertip_time.db-journal',
  ];
  const sourcePaths = <String>[
    'backend/main.py',
    'backend/test_workspaces.py',
    'backend/tests/test_schema.py',
    'backend/schema.sql',
    'backend/migrations/001.sql',
    'backend/requirements.txt',
    'backend/pyproject.toml',
    'backend/config.json',
    'backend/.env.example',
    'backend/other.db',
    'backend/schema.db',
    'backend/duoyi.db.bak',
    'backend/duoyi.db-wal.extra',
    'backend/fingertip_time.db-journal.extra',
    'backend/duoyi.db-extra',
    'backend/fingertip_time.db-extra',
    'backend/nested/duoyi.db',
    'backend/nested/fingertip_time.db-wal',
    'backend/tests/fixtures/duoyi.db',
    'backend/tests/fixtures/fingertip_time.db-journal',
    'backend/backups-old/current.zip',
    'backend/uploads-old/avatar.png',
    'backend/backups.py',
    'backend/uploads.py',
    'backend/Backups/current.zip',
    'backend/Uploads/avatar.png',
    'backend/nested/backups/current.zip',
    'backend/nested/uploads/avatar.png',
    'lib/backend/duoyi.db',
    'test/backend/uploads/data.json',
    'docs/backend/backups/current.zip',
    'scripts/validate_goal_closure.sh',
    'lib/changed.dart',
    'test/changed_test.dart',
    'pubspec.yaml',
    'pubspec.lock',
  ];

  Future<void> expectFreshnessForMutations(
    List<String> mutations, {
    required bool expectStale,
    List<String> diagnosticPaths = const [],
    bool emptyDataDirectories = false,
  }) async {
    _writeReport(reportDir, eighthStatus: 'passed');
    _writeAndroidEvidence(androidDir);
    _writeIosEvidence(iosDir);
    final sourceRoot = _emptySourceRoot(reportDir);
    final summary = File('${reportDir.path}/summary.tsv');
    final afterReport = summary.lastModifiedSync().add(
      const Duration(seconds: 10),
    );
    if (emptyDataDirectories) {
      for (final path in ['backend/backups', 'backend/uploads']) {
        Directory('${sourceRoot.path}/$path').createSync(recursive: true);
      }
    }
    for (final path in mutations) {
      final changed = File('${sourceRoot.path}/$path');
      changed.parent.createSync(recursive: true);
      changed.writeAsStringSync('isolated mutation after alignment\n');
      changed.setLastModifiedSync(afterReport);
    }
    final result = await _runValidator(
      reportDir,
      androidDir,
      iosDir,
      goalReportDir,
      statusDir,
      matrixFile,
      sourceRoot: sourceRoot.path,
    );
    // Legacy/device fixture passes do not close the four expanded requirements.
    expect(result.exitCode, isNot(0), reason: _combinedOutput(result));
    expect(result.stdout, contains('alignment_report: passed'));
    expect(result.stdout, contains('android_device_evidence: passed'));
    expect(result.stdout, contains('ios_device_evidence: passed'));
    expect(
      result.stdout,
      contains(
        expectStale
            ? 'alignment_report_freshness: failed(1)'
            : 'alignment_report_freshness: passed',
      ),
    );
    expect(result.stdout, contains('all_requirements_closed: failed(1)'));
    _expectLegacyGatesLeaveExpandedRequirementsOpen(statusDir);
    final log = File(
      '${goalReportDir.path}/alignment_report_freshness.log',
    ).readAsStringSync();
    if (expectStale) {
      expect(log, contains('alignment regression report is stale'));
      for (final path in diagnosticPaths) {
        expect(log, contains(bashPath('${sourceRoot.path}/$path')));
      }
    } else {
      expect(log, isEmpty);
    }
  }

  for (final path in runtimeOnlyPaths) {
    test(
      'freshness ignores exact runtime path $path',
      () async {
        await expectFreshnessForMutations([path], expectStale: false);
      },
      timeout: _closureValidatorTimeout,
    );
  }
  for (final path in sourcePaths) {
    test(
      'freshness still rejects source or lookalike path $path',
      () async {
        await expectFreshnessForMutations(
          [path],
          expectStale: true,
          diagnosticPaths: [path],
        );
      },
      timeout: _closureValidatorTimeout,
    );
  }
  test(
    'pruned empty runtime directory names never appear as stale files',
    () async {
      await expectFreshnessForMutations(
        [],
        expectStale: false,
        emptyDataDirectories: true,
      );
    },
    timeout: _closureValidatorTimeout,
  );
  test(
    'runtime churn cannot mask a real backend edit',
    () async {
      // More than the diagnostic 20-line limit of ignored runtime entries.
      final runtimeChurn = List<String>.generate(
        25,
        (i) => 'backend/backups/active-$i.zip',
      );
      await expectFreshnessForMutations(
        [
          ...runtimeChurn,
          'backend/uploads/current/avatar.png',
          'backend/duoyi.db-wal',
          'backend/fingertip_time.db-shm',
          'backend/main.py',
        ],
        expectStale: true,
        diagnosticPaths: ['backend/main.py'],
      );
      final log = File(
        '${goalReportDir.path}/alignment_report_freshness.log',
      ).readAsStringSync();
      expect(log, isNot(contains('/backend/backups/')));
      expect(log, isNot(contains('/backend/uploads/')));
      expect(log, isNot(contains('/backend/duoyi.db-wal')));
      expect(log, isNot(contains('/backend/fingertip_time.db-shm')));
    },
    timeout: _closureValidatorTimeout,
  );
}

void _expectLegacyGatesLeaveExpandedRequirementsOpen(Directory statusDir) {
  const closedIds = [
    'REQ-404',
    'REQ-STYLE',
    'REQ-ADMIN',
    'REQ-HABIT',
    'REQ-MINE',
    'REQ-COUNTDOWN',
    'REQ-ALMANAC',
    'REQ-NOTIFY',
    'REQ-WIDGET',
    'REQ-DEVICE',
  ];
  const missingGates = {
    'REQ-DEFAULT-IOS': 'default iOS visual acceptance',
    'REQ-I18N': 'global localization acceptance',
    'REQ-SETTINGS': 'settings flow acceptance',
    'REQ-FLUENCY': 'mobile performance acceptance',
  };
  final lines = File('${statusDir.path}/status.tsv').readAsLinesSync();
  expect(lines, hasLength(15));
  expect(lines.first, 'id\tstatus\treason\tgroups\trequirement');
  final rows = lines.skip(1).map((line) => line.split('\t')).toList();
  for (final row in rows) {
    expect(row, hasLength(5));
  }
  final rowsById = {for (final row in rows) row.first: row};
  expect(rowsById.keys, unorderedEquals([...closedIds, ...missingGates.keys]));
  for (final id in closedIds) {
    expect(rowsById[id]!.sublist(0, 3), [
      id,
      'closed',
      'all mapped gates passed',
    ]);
  }
  for (final entry in missingGates.entries) {
    expect(rowsById[entry.key]!.sublist(0, 3), [
      entry.key,
      'open(gate_missing)',
      'mapped gate is missing: ${entry.value}',
    ]);
  }
}

Future<ProcessResult> _runValidator(
  Directory reportDir,
  Directory androidDir,
  Directory iosDir,
  Directory goalReportDir,
  Directory statusDir,
  File matrixFile, {
  String? sourceRoot,
}) {
  return Process.run(
    'bash',
    ['scripts/validate_goal_closure.sh'],
    workingDirectory: Directory.current.path,
    environment: bashEnvironment(
      {
        'ROOT_DIR_OVERRIDE': sourceRoot ?? _emptySourceRoot(reportDir).path,
        // These fixtures validate report rules, not the host's device inventory.
        // Missing tools keep every case isolated from Flutter/ADB/SDK probes.
        'FLUTTER_BIN': '${reportDir.parent.path}/missing-tools/flutter',
        'ADB_BIN': '${reportDir.parent.path}/missing-tools/adb',
        'ANDROID_SDK_ROOT': '${reportDir.parent.path}/missing-sdk',
        'KVM_DEVICE': '${reportDir.parent.path}/missing-kvm',
        'REPORT_DIR': reportDir.path,
        'GOAL_REPORT_DIR': goalReportDir.path,
        'ANDROID_EVIDENCE_DIR': androidDir.path,
        'IOS_EVIDENCE_DIR': iosDir.path,
        'STATUS_DIR': statusDir.path,
        'MATRIX_FILE': matrixFile.path,
      },
      pathVariables: {
        'ROOT_DIR_OVERRIDE',
        'FLUTTER_BIN',
        'ADB_BIN',
        'ANDROID_SDK_ROOT',
        'KVM_DEVICE',
        'REPORT_DIR',
        'GOAL_REPORT_DIR',
        'ANDROID_EVIDENCE_DIR',
        'IOS_EVIDENCE_DIR',
        'STATUS_DIR',
        'MATRIX_FILE',
      },
    ),
    includeParentEnvironment: true,
  );
}

Directory _emptySourceRoot(Directory reportDir) {
  final root = Directory('${reportDir.parent.path}/source-root');
  for (final name in [
    'android',
    'backend',
    'docs',
    'ios',
    'lib',
    'scripts',
    'test',
  ]) {
    Directory('${root.path}/$name').createSync(recursive: true);
  }
  final files = [
    File('${root.path}/pubspec.yaml')..writeAsStringSync('name: duoyi_test\n'),
    File('${root.path}/pubspec.lock')..writeAsStringSync('# lock\n'),
  ];
  final summary = File('${reportDir.path}/summary.tsv');
  if (summary.existsSync()) {
    final staleTime = summary.lastModifiedSync().subtract(
      const Duration(seconds: 1),
    );
    for (final file in files) {
      file.setLastModifiedSync(staleTime);
    }
  }
  return root;
}

const _expandedGates = {
  'default iOS visual acceptance': 'REQ-DEFAULT-IOS',
  'global localization acceptance': 'REQ-I18N',
  'settings flow acceptance': 'REQ-SETTINGS',
  'mobile performance acceptance': 'REQ-FLUENCY',
};

void _writeReport(
  Directory dir, {
  required String eighthStatus,
  List<String> extraGroups = const [],
  Map<String, String> gateStatuses = const {},
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
    final log = File('${dir.path}/${group.hashCode}.log');
    log.writeAsStringSync('log for $group');
    final logPath = bashPath(log.path);
    final status =
        gateStatuses[group] ??
        (group.startsWith('8/8') ? eighthStatus : 'passed');
    summary.writeln('$group\t$status\t1\t$logPath');
    markdown.writeln('| $group | $status | 1s | `$logPath` |');
  }
  File('${dir.path}/summary.tsv').writeAsStringSync(summary.toString());
  File('${dir.path}/summary.md').writeAsStringSync(markdown.toString());
}

void _writeAndroidEvidence(Directory dir) {
  final manualFiles = <String, String>{
    'notification_shade_progress':
        'evidence/manual/android_notification_progress.png',
    'notification_shade_toggle_off':
        'evidence/manual/android_notification_toggle_off.png',
    'reminder_notification_popup_alarm':
        'evidence/manual/android_reminder_modes.mp4',
    'single_delivery_no_duplicate':
        'evidence/manual/android_single_delivery_no_duplicate.mp4',
    'default_soft_ringtone':
        'evidence/manual/android_default_soft_ringtone.mp4',
    'launcher_widgets_10_added':
        'evidence/manual/android_launcher_widgets_10_added.mp4',
    'android_widget_style_matrix':
        'evidence/manual/android_widget_style_matrix.mp4',
    'widget_refresh_before_after':
        'evidence/manual/android_widget_refresh_before_after.mp4',
    'widget_todo_complete': 'evidence/manual/android_widget_todo_complete.mp4',
    'widget_quick_add': 'evidence/manual/android_widget_quick_add.mp4',
    'widget_habit_checkin': 'evidence/manual/android_widget_habit_checkin.mp4',
    'calendar_countdown_deeplink':
        'evidence/manual/android_calendar_countdown_deeplink.mp4',
  };
  final files = <String, String>{
    'device_manufacturer.txt': 'Google',
    'device_model.txt': 'Pixel test device',
    'android_version.txt': '15',
    'android_sdk.txt': '35',
    'install.txt': 'Success',
    'launch.txt': 'Events injected: 1',
    'deeplink_duoyi___tab_today.txt': 'Status: ok',
    'deeplink_duoyi___calendar.txt': 'Status: ok',
    'deeplink_duoyi___countdown_device_regression_missing.txt': 'Status: ok',
    'deeplink_duoyi___action_quick_todo.txt': 'Status: ok',
    'deeplink_duoyi___action_complete_todo_id_device_regression_missing.txt':
        'Status: ok',
    'deeplink_duoyi___action_checkin_habit_id_device_regression_missing.txt':
        'Status: ok',
    'package.txt': 'package com.duoyi.duoyi',
    'appops.txt': 'POST_NOTIFICATION: allow',
    'notification_assistant.txt': 'allowed_assistant=none',
    'dumpsys_notification.txt': 'Duoyi today progress notification',
    'dumpsys_alarm.txt': 'ReminderRingtone RTC_WAKEUP duoyi_soft',
    'dumpsys_appwidget.txt': 'Duoyi appwidget hosts',
    'widget_providers.txt': _androidWidgetProviders(),
    'logcat_duoyi.txt': 'ReminderRingtone NotificationStatusBar AppWidget',
    'manual_required.md':
        'Notification shade\nReminder methods\nDefault ringtone\nLauncher widgets\nWidget style matrix\nCountdown deep link',
    'manual_evidence_manifest.md': manualFiles.entries
        .map((entry) => '- ${entry.key}: passed - ${entry.value}')
        .join('\n'),
    'shared_prefs_files.txt': 'FlutterSharedPreferences.xml',
    'reminder_preferences.txt': 'pref_reminder_ringtone_sound=soft',
    'notification_channels.txt': 'duoyi_soft',
    'notification_today_progress.txt': 'today progress Duoyi',
    'reminder_alarm_queue.txt': 'ReminderRingtone RTC_WAKEUP',
    'default_soft_ringtone.txt': 'duoyi_soft 柔和晨铃',
    'single_delivery_no_duplicate.txt': '''
reminder_id=device-regression-single-delivery
flutter_pending_count=0
native_pending_count=1
status_bar_excluded=true
delivered_count=1
duplicate_delivery_count=0
''',
  };
  _writeFiles(dir, files);
  _writeManualMedia(dir, manualFiles.values);
}

String _androidWidgetProviders() {
  return [
    'DuoyiTodoWidgetProvider',
    'DuoyiHabitWidgetProvider',
    'DuoyiCalendarWidgetProvider',
    'DuoyiScheduleWidgetProvider',
    'DuoyiGoalWidgetProvider',
    'DuoyiCourseWidgetProvider',
    'DuoyiNoteWidgetProvider',
    'DuoyiAnniversaryWidgetProvider',
    'DuoyiDiaryWidgetProvider',
    'DuoyiFocusHabitWidgetProvider',
  ].join('\n');
}

void _writeIosEvidence(Directory dir) {
  final manualFiles = <String, String>{
    'widget_gallery_10_widgets': 'evidence/manual/ios_widget_gallery.png',
    'widgetkit_family_matrix': 'evidence/manual/ios_widget_family_matrix.mp4',
    'app_group_refresh': 'evidence/manual/ios_app_group_refresh.mp4',
    'widget_todo_complete': 'evidence/manual/ios_widget_todo_complete.mp4',
    'widget_quick_add': 'evidence/manual/ios_widget_quick_add.mp4',
    'widget_habit_checkin': 'evidence/manual/ios_widget_habit_checkin.mp4',
    'widget_focus_start': 'evidence/manual/ios_widget_focus_start.mp4',
    'widget_footer_navigation':
        'evidence/manual/ios_widget_footer_navigation.mp4',
    'calendar_countdown_deeplink':
        'evidence/manual/ios_calendar_countdown_deeplink.mp4',
    'ios_notification_behavior':
        'evidence/manual/ios_notification_behavior.mp4',
  };
  final files = <String, String>{
    'macos_version.txt': 'ProductVersion: 15.0',
    'xcode_version.txt': 'Xcode 16.0',
    'xctrace_devices.txt': 'Test iPhone (0000) (iPhone)',
    'xctrace_physical_ios_devices.txt': 'Test iPhone (0000) (iPhone)',
    'app_group_entitlements.txt': [
      'ios/Runner/Runner.entitlements: group.com.duoyi.duoyi',
      'ios/DuoyiWidgets/DuoyiWidgets.entitlements: group.com.duoyi.duoyi',
    ].join('\n'),
    'widget_bundle_id.txt': 'com.duoyi.duoyi.DuoyiWidgets',
    'widget_target.txt':
        'DuoyiWidgets.appex DuoyiWidgets.swift in Sources Embed App Extensions',
    'xcodebuild_device.log': 'BUILD SUCCEEDED',
    'simctl_devices.txt': 'iPhone 16',
    'widgetkit_recent.log':
        'WidgetKit duoyi://tab/today duoyi://calendar duoyi://countdown/test',
    'widgetkit_calendar_countdown_deeplink.log':
        'duoyi://calendar duoyi://countdown/test',
    'manual_required.md': [
      'Add all 10 Duoyi WidgetKit widgets',
      'App Group',
      'quick actions',
      'countdown',
      'notification',
    ].join('\n'),
    'manual_evidence_manifest.md': manualFiles.entries
        .map((entry) => '- ${entry.key}: passed - ${entry.value}')
        .join('\n'),
  };
  _writeFiles(dir, files);
  _writeManualMedia(dir, manualFiles.values);
}

void _writeFiles(Directory dir, Map<String, String> files) {
  for (final entry in files.entries) {
    File('${dir.path}/${entry.key}').writeAsStringSync(entry.value);
  }
}

void _writeManualMedia(Directory dir, Iterable<String> paths) {
  for (final path in paths) {
    final file = File('${dir.path}/$path');
    file.parent.createSync(recursive: true);
    _writeFakeMedia(file);
  }
}

void _writeFakeMedia(File file) {
  final path = file.path.toLowerCase();
  if (path.endsWith('.png')) {
    file.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  } else if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
    file.writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0]);
  } else if (path.endsWith('.mp4') || path.endsWith('.mov')) {
    file.writeAsBytesSync([
      0x00,
      0x00,
      0x00,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x69,
      0x73,
      0x6f,
      0x6d,
    ]);
  } else if (path.endsWith('.webm')) {
    file.writeAsBytesSync([0x1a, 0x45, 0xdf, 0xa3]);
  } else {
    file.writeAsStringSync('manual evidence bytes');
  }
}

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}
