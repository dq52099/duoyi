import 'dart:io';

Map<String, String> bashEnvironment(
  Map<String, String> environment, {
  Set<String> pathVariables = const {},
}) {
  if (!Platform.isWindows || pathVariables.isEmpty) {
    return environment;
  }

  final existing = Platform.environment['WSLENV'];
  final entries = <String>[
    if (existing != null && existing.isNotEmpty) existing,
    for (final name in pathVariables) '$name/p',
  ];
  return {...environment, 'WSLENV': entries.join(':')};
}

String bashPath(String path) {
  if (!Platform.isWindows) return path;

  final normalized = path.replaceAll('\\', '/');
  final match = RegExp(r'^([A-Za-z]):/(.*)$').firstMatch(normalized);
  if (match == null) return normalized;
  return '/mnt/${match.group(1)!.toLowerCase()}/${match.group(2)!}';
}

ProcessResult chmodForBash(String path) {
  if (!Platform.isWindows) {
    return Process.runSync('chmod', ['+x', path]);
  }
  final existing = Platform.environment['WSLENV'];
  final wslenv = [
    if (existing != null && existing.isNotEmpty) existing,
    'DUOYI_CHMOD_PATH/p',
  ].join(':');
  return Process.runSync(
    'bash',
    ['-lc', r'chmod +x "$DUOYI_CHMOD_PATH"'],
    environment: {'DUOYI_CHMOD_PATH': path, 'WSLENV': wslenv},
    includeParentEnvironment: true,
  );
}
