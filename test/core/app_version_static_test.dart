import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppVersion constants match pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appVersion = File('lib/core/app_version.dart').readAsStringSync();
    final pubspecMatch = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    final nameMatch = RegExp(
      r"static const name = '([^']+)';",
    ).firstMatch(appVersion);
    final buildMatch = RegExp(
      r'static const build = ([0-9]+);',
    ).firstMatch(appVersion);

    expect(pubspecMatch, isNotNull);
    expect(nameMatch, isNotNull);
    expect(buildMatch, isNotNull);
    expect(nameMatch!.group(1), pubspecMatch!.group(1));
    expect(buildMatch!.group(1), pubspecMatch.group(2));
  });
}
