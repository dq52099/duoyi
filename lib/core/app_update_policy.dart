String normalizeAppVersion(String value) =>
    value.replaceFirst(RegExp(r'^v'), '').split('-').first.split('+').first;

int compareAppVersions(String left, String right) {
  final leftParts = normalizeAppVersion(
    left,
  ).split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final rightParts = normalizeAppVersion(
    right,
  ).split('.').map((part) => int.tryParse(part) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final a = i < leftParts.length ? leftParts[i] : 0;
    final b = i < rightParts.length ? rightParts[i] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}

bool shouldForceAppUpdate({
  required String currentVersion,
  required String? latestVersion,
  required String? minimumSupportedVersion,
  required bool forceUpdateRequired,
}) {
  if (!forceUpdateRequired) return false;
  final latest = latestVersion?.trim();
  if (latest != null &&
      latest.isNotEmpty &&
      compareAppVersions(latest, currentVersion) > 0) {
    return true;
  }
  final minimum = minimumSupportedVersion?.trim();
  if (minimum == null || minimum.isEmpty) return false;
  return compareAppVersions(currentVersion, minimum) < 0;
}

String formatUpdateNotesForDisplay(String? notes) {
  final raw = notes?.trim();
  if (raw == null || raw.isEmpty) return '';
  final normalized = raw
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'),
        (match) => match.group(1) ?? '',
      );
  final summaryLines = <String>[];
  for (final rawLine in normalized.split('\n')) {
    final line = updateNoteSummaryLine(rawLine);
    if (line == null || summaryLines.contains(line)) continue;
    summaryLines.add(line);
    if (summaryLines.length >= 8) break;
  }
  if (summaryLines.isEmpty) return '';
  return '本次更新摘要：\n${summaryLines.map((line) => '- $line').join('\n')}';
}

String? updateNoteSummaryLine(String rawLine) {
  var line = rawLine
      .trim()
      .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
      .replaceFirst(RegExp(r'^[>\-\*\u2022\d\.\)\s]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (line.isEmpty) return null;

  final normalized = line
      .replaceFirst(RegExp(r'^[*_\\s]+'), '')
      .replaceAll('*', '')
      .replaceAll('_', '')
      .trim()
      .toLowerCase();
  if (normalized.startsWith('full changelog') ||
      normalized.startsWith('compare changes') ||
      normalized == 'what\'s changed' ||
      normalized == '更新内容' ||
      normalized == '更新说明' ||
      normalized == '本次更新' ||
      normalized == '本次更新摘要') {
    return null;
  }
  if (normalized.contains('github.com') &&
      (normalized.contains('/compare/') ||
          normalized.contains('/releases/tag/'))) {
    return null;
  }
  line = line
      .replaceFirst(RegExp(r'^本次更新[：:]\s*'), '')
      .replaceFirst(RegExp(r'^更新内容[：:]\s*'), '')
      .trim();
  return line.isEmpty ? null : line;
}
