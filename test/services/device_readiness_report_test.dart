import 'dart:io';

import 'package:test/test.dart';

import '../test_support/bash_test_utils.dart';

void main() {
  late Directory tempDir;
  late Directory binDir;
  late Directory sdkDir;
  late Directory outputDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duoyi-device-ready-');
    binDir = Directory('${tempDir.path}/bin')..createSync(recursive: true);
    sdkDir = Directory('${tempDir.path}/android-sdk')..createSync();
    outputDir = Directory('${tempDir.path}/report');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'device readiness report records missing Android and iOS runtimes',
    () async {
      final flutter = _writeExecutable(
        '${binDir.path}/flutter',
        '''#!/usr/bin/env bash
if [[ "\$1" == "devices" && "\${2:-}" == "--machine" ]]; then
  printf '[{"name":"Linux","targetPlatform":"linux-arm64"}]\n'
else
  printf 'Found 1 connected device:\n  Linux (desktop)\n'
fi
''',
      );
      final adb = _writeExecutable('${binDir.path}/adb', '''#!/usr/bin/env bash
printf 'List of devices attached\n\n'
''');

      final result = await Process.run(
        'bash',
        ['scripts/generate_device_readiness_report.sh'],
        workingDirectory: Directory.current.path,
        environment: bashEnvironment(
          {
            'FLUTTER_BIN': flutter.path,
            'ADB_BIN': adb.path,
            'ANDROID_SDK_ROOT': sdkDir.path,
            'OUTPUT_DIR': outputDir.path,
          },
          pathVariables: {
            'FLUTTER_BIN',
            'ADB_BIN',
            'ANDROID_SDK_ROOT',
            'OUTPUT_DIR',
          },
        ),
        includeParentEnvironment: true,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final status = _readStatus(outputDir);
      expect(status['host_architecture'], 'available');
      expect(status['android_runtime'], 'missing');
      expect(status['ios_runtime'], 'missing');
      expect(status['adb_device'], 'missing');
      expect(status['android_emulator_binary'], 'missing');
      expect(status['android_emulator_launchability'], 'missing');
      expect(status['ios_host'], 'missing');
      expect(File('${outputDir.path}/host_uname.txt').existsSync(), isTrue);

      final validation = await _runValidator(outputDir);
      expect(validation.exitCode, 0, reason: _combinedOutput(validation));
    },
  );

  test(
    'device readiness treats an empty system-images directory as missing',
    () async {
      final flutter = _writeExecutable(
        '${binDir.path}/flutter',
        '''#!/usr/bin/env bash
if [[ "\$1" == "devices" && "\${2:-}" == "--machine" ]]; then
  printf '[]\n'
else
  printf 'No devices\n'
fi
''',
      );
      final adb = _writeExecutable('${binDir.path}/adb', '''#!/usr/bin/env bash
printf 'List of devices attached\n\n'
''');
      Directory('${sdkDir.path}/system-images').createSync(recursive: true);

      final result = await Process.run(
        'bash',
        ['scripts/generate_device_readiness_report.sh'],
        workingDirectory: Directory.current.path,
        environment: bashEnvironment(
          {
            'FLUTTER_BIN': flutter.path,
            'ADB_BIN': adb.path,
            'ANDROID_SDK_ROOT': sdkDir.path,
            'OUTPUT_DIR': outputDir.path,
            'KVM_DEVICE': '${tempDir.path}/missing-kvm',
          },
          pathVariables: {
            'FLUTTER_BIN',
            'ADB_BIN',
            'ANDROID_SDK_ROOT',
            'OUTPUT_DIR',
            'KVM_DEVICE',
          },
        ),
        includeParentEnvironment: true,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final status = _readStatus(outputDir);
      expect(status['android_system_images'], 'missing');
      expect(status['kvm'], 'missing');
      expect(status['android_emulator_launchability'], 'missing');
    },
  );

  test('device readiness validator rejects duplicate rows', () async {
    outputDir.createSync(recursive: true);
    File('${outputDir.path}/summary.tsv').writeAsStringSync(
      '''check\tstatus\tdetail
android_runtime\tmissing\tone
android_runtime\tmissing\ttwo
''',
    );
    File('${outputDir.path}/summary.md').writeAsStringSync(
      '# Device Readiness Report\nandroid_runtime\nios_host\n',
    );
    for (final artifact in [
      'flutter_devices.txt',
      'flutter_devices_machine.json',
      'adb_devices.txt',
      'sdkmanager_list.txt',
      'avd_list.txt',
      'host_uname.txt',
    ]) {
      File('${outputDir.path}/$artifact').writeAsStringSync(artifact);
    }

    final result = await _runValidator(outputDir);

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('summary.tsv must contain exactly one row for android_runtime'),
    );
  });

  for (final scenario in [
    (
      name: 'pretty Android',
      json: '[\n  {"targetPlatform": "android-arm64"}\n]\n',
      android: 'ready',
      ios: 'missing',
    ),
    (
      name: 'pretty iOS',
      json: '[\n  {"targetPlatform": "ios"}\n]\n',
      android: 'missing',
      ios: 'ready',
    ),
    (
      name: 'compact mobile devices',
      json: '[{"targetPlatform":"android-x64"},{"targetPlatform":"ios"}]',
      android: 'ready',
      ios: 'ready',
    ),
    (
      name: 'platform names in unrelated fields',
      json: '[{"name":"android-arm64 ios","targetPlatform":"linux-arm64"}]',
      android: 'missing',
      ios: 'missing',
    ),
    (
      name: 'invalid root object',
      json: '{"targetPlatform":"android-arm64"}',
      android: 'missing',
      ios: 'missing',
    ),
    (
      name: 'malformed device JSON',
      json: '[{"targetPlatform":"android-arm64"}',
      android: 'missing',
      ios: 'missing',
    ),
  ]) {
    test('device readiness parses ${scenario.name}', () async {
      final fixture = File('${tempDir.path}/devices.json')
        ..writeAsStringSync(scenario.json);
      final flutter = _writeExecutable(
        '${binDir.path}/flutter',
        _deviceFixtureFlutter,
      );
      final adb = _writeExecutable('${binDir.path}/adb', '''#!/usr/bin/env bash
printf 'List of devices attached\\n\\n'
''');
      final result = await Process.run(
        'bash',
        ['scripts/generate_device_readiness_report.sh'],
        workingDirectory: Directory.current.path,
        environment: bashEnvironment(
          {
            'FLUTTER_BIN': flutter.path,
            'ADB_BIN': adb.path,
            'ANDROID_SDK_ROOT': sdkDir.path,
            'OUTPUT_DIR': outputDir.path,
            'DEVICE_FIXTURE_JSON': fixture.path,
            'KVM_DEVICE': '${tempDir.path}/missing-kvm',
          },
          pathVariables: {
            'FLUTTER_BIN',
            'ADB_BIN',
            'ANDROID_SDK_ROOT',
            'OUTPUT_DIR',
            'DEVICE_FIXTURE_JSON',
            'KVM_DEVICE',
          },
        ),
      );
      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final status = _readStatus(outputDir);
      expect(status['android_runtime'], scenario.android);
      expect(status['ios_runtime'], scenario.ios);
      final validation = await _runValidator(outputDir);
      expect(validation.exitCode, 0, reason: _combinedOutput(validation));
    });
  }

  for (final platform in ['android-arm64', 'ios', 'linux-arm64']) {
    test('device gate routes pretty $platform discovery', () async {
      final fixture = File('${tempDir.path}/devices.json')
        ..writeAsStringSync('[\n  {"targetPlatform": "$platform"}\n]\n');
      final flutter = _writeExecutable(
        '${binDir.path}/flutter',
        _deviceFixtureFlutter,
      );
      final adb = _writeExecutable('${binDir.path}/adb', '''#!/usr/bin/env bash
printf 'List of devices attached\\n\\n'
''');
      final apk = File('${tempDir.path}/fixture.apk')
        ..writeAsStringSync('Synthetic smoke-phase sentinel; never installed');
      final result = await Process.run(
        'bash',
        ['scripts/device_regression_check.sh'],
        workingDirectory: Directory.current.path,
        environment: bashEnvironment(
          {
            'FLUTTER_BIN': flutter.path,
            'ADB_BIN': adb.path,
            'ANDROID_SDK_ROOT': sdkDir.path,
            'READINESS_DIR': outputDir.path,
            'DEVICE_FIXTURE_JSON': fixture.path,
            'APK_PATH': apk.path,
            'KVM_DEVICE': '${tempDir.path}/missing-kvm',
          },
          pathVariables: {
            'FLUTTER_BIN',
            'ADB_BIN',
            'ANDROID_SDK_ROOT',
            'READINESS_DIR',
            'DEVICE_FIXTURE_JSON',
            'APK_PATH',
            'KVM_DEVICE',
          },
        ),
      );
      if (platform == 'linux-arm64') {
        expect(result.exitCode, 2, reason: _combinedOutput(result));
        expect(
          _combinedOutput(result),
          isNot(contains('fixture integration phase')),
        );
        expect(
          _combinedOutput(result),
          contains('No Android or iOS device/emulator is attached'),
        );
      } else {
        expect(result.exitCode, 37, reason: _combinedOutput(result));
        expect(_combinedOutput(result), contains('fixture integration phase'));
        expect(
          _combinedOutput(result),
          isNot(contains('No Android or iOS device/emulator is attached')),
        );
      }
    });
  }

  test('missing readiness summary extracts only missing rows', () async {
    outputDir.createSync(recursive: true);
    File('${outputDir.path}/summary.tsv').writeAsStringSync(
      '''check\tstatus\tdetail
android_runtime\tmissing\tno Android runtime
ios_runtime\tmissing\tno iOS runtime
kvm\tavailable\t/dev/kvm exists
''',
    );
    File('${outputDir.path}/summary.md').writeAsStringSync(
      '# Device Readiness Report\nandroid_runtime\nios_host\n',
    );
    for (final artifact in [
      'flutter_devices.txt',
      'flutter_devices_machine.json',
      'adb_devices.txt',
      'sdkmanager_list.txt',
      'avd_list.txt',
    ]) {
      File('${outputDir.path}/$artifact').writeAsStringSync(artifact);
    }
    final missingDir = Directory('${tempDir.path}/missing');

    final result = await Process.run(
      'bash',
      ['scripts/summarize_device_readiness_missing.sh'],
      workingDirectory: Directory.current.path,
      environment: bashEnvironment(
        {'READINESS_DIR': outputDir.path, 'OUTPUT_DIR': missingDir.path},
        pathVariables: {'READINESS_DIR', 'OUTPUT_DIR'},
      ),
      includeParentEnvironment: true,
    );

    expect(result.exitCode, 0, reason: _combinedOutput(result));
    final missing = File('${missingDir.path}/missing.tsv').readAsStringSync();
    expect(missing, contains('android_runtime\tno Android runtime'));
    expect(missing, contains('ios_runtime\tno iOS runtime'));
    expect(missing, isNot(contains('kvm')));

    final validation = await Process.run(
      'bash',
      ['scripts/validate_device_readiness_missing.sh'],
      workingDirectory: Directory.current.path,
      environment: bashEnvironment(
        {'REPORT_DIR': missingDir.path},
        pathVariables: {'REPORT_DIR'},
      ),
      includeParentEnvironment: true,
    );
    expect(validation.exitCode, 0, reason: _combinedOutput(validation));
  });
}

const _deviceFixtureFlutter = r'''#!/usr/bin/env bash
if [[ "$1" == "devices" && "${2:-}" == "--machine" ]]; then
  cat "$DEVICE_FIXTURE_JSON"
elif [[ "$1" == "test" ]]; then
  printf 'fixture integration phase\n'
  exit 37
else
  printf 'Synthetic Flutter device fixture\n'
fi
''';

File _writeExecutable(String path, String content) {
  final file = File(path)..writeAsStringSync(content);
  final result = chmodForBash(path);
  if (result.exitCode != 0) {
    throw StateError(_combinedOutput(result));
  }
  return file;
}

Future<ProcessResult> _runValidator(Directory outputDir) {
  return Process.run(
    'bash',
    ['scripts/validate_device_readiness_report.sh'],
    workingDirectory: Directory.current.path,
    environment: bashEnvironment(
      {'REPORT_DIR': outputDir.path},
      pathVariables: {'REPORT_DIR'},
    ),
    includeParentEnvironment: true,
  );
}

Map<String, String> _readStatus(Directory dir) {
  final rows = File('${dir.path}/summary.tsv').readAsLinesSync().skip(1);
  return {for (final row in rows) row.split('\t')[0]: row.split('\t')[1]};
}

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}
