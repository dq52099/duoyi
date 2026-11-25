import 'dart:io';

import 'package:test/test.dart';

// Admit only the pinned pure style helper and its sole measurement consumer.
// Any new reference, escape, rendered widget, part, or body change fails closed.
String _maskReturnedAccessibilityMeasurement(String path, String source) {
  final String helperName;
  final String helperEndMarker;
  final String consumerMarker;
  final String consumerEndMarker;
  final String expectedConsumer;
  if (path == 'lib/screens/today_screen.dart') {
    helperName = '_todayEffectiveTextStyle';
    helperEndMarker = 'double _measureTodayTextWidth(';
    consumerMarker = 'double _measureTodayTextWidth(';
    consumerEndMarker = 'double _overdueBadgeEstimatedWidth(';
    expectedConsumer = r'''
double _measureTodayTextWidth(
  BuildContext context,
  String text,
  TextStyle? style,
) {
  final effectiveStyle = _todayEffectiveTextStyle(context, style);
  final locale = Localizations.maybeLocaleOf(context);
  final painter = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle, locale: locale),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: locale,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
''';
  } else if (path == 'lib/widgets/eisenhower_matrix.dart') {
    helperName = '_matrixEffectiveTextStyle';
    helperEndMarker = 'class _QuadrantCard';
    consumerMarker = 'Size measuredSize(';
    consumerEndMarker = 'const dotAndGap = 14.0;';
    expectedConsumer = r'''
Size measuredSize(
                                String text,
                                TextStyle style, {
                                int? maxLines,
                                double maxWidth = double.infinity,
                              }) {
                                final painter = TextPainter(
                                  text: TextSpan(
                                    text: text,
                                    style: _matrixEffectiveTextStyle(
                                      context,
                                      style,
                                    ),
                                    locale: locale,
                                  ),
                                  textScaler: textScaler,
                                  textDirection: textDirection,
                                  locale: locale,
                                  maxLines: maxLines,
                                )..layout(
                                    maxWidth: maxWidth.isFinite
                                        ? math.max(1.0, maxWidth)
                                        : double.infinity,
                                  );
                                final size = painter.size;
                                painter.dispose();
                                return size;
                              }
''';
  } else {
    return source;
  }

  if (RegExp(r'\bpart\b').hasMatch(source)) {
    return source;
  }
  int uniqueMarker(String marker) {
    final index = source.indexOf(marker);
    if (index < 0 || source.indexOf(marker, index + marker.length) >= 0) {
      return -1;
    }
    return index;
  }
  String compact(String value) => value.replaceAll(RegExp(r'\s+'), '');
  final helperMarker =
      'TextStyle $helperName(BuildContext context, TextStyle? style) {';
  final helperStart = uniqueMarker(helperMarker);
  final helperEnd = uniqueMarker(helperEndMarker);
  final consumerStart = uniqueMarker(consumerMarker);
  final consumerEnd = uniqueMarker(consumerEndMarker);
  if (helperStart < 0 ||
      helperEnd <= helperStart ||
      consumerStart < helperEnd ||
      consumerEnd <= consumerStart) {
    return source;
  }
  final helper = source.substring(helperStart, helperEnd);
  final consumer = source.substring(consumerStart, consumerEnd);
  final expectedHelper = r'''
TextStyle _todayEffectiveTextStyle(BuildContext context, TextStyle? style) {
  final defaultTextStyle = DefaultTextStyle.of(context);
  var effectiveTextStyle = style;
  if (style == null || style.inherit) {
    effectiveTextStyle = defaultTextStyle.style.merge(style);
  }
  if (MediaQuery.boldTextOf(context)) {
    effectiveTextStyle = effectiveTextStyle!.merge(
      const TextStyle(fontWeight: FontWeight.bold),
    );
  }
  final lineHeightScaleFactor =
      MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  if (lineHeightScaleFactor != null ||
      letterSpacing != null ||
      wordSpacing != null) {
    final overrideTextStyle = TextStyle(
      height: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
    );
    effectiveTextStyle =
        effectiveTextStyle?.merge(overrideTextStyle) ?? overrideTextStyle;
  }
  return effectiveTextStyle ?? const TextStyle();
}
'''.replaceAll('_todayEffectiveTextStyle', helperName);
  if (compact(helper) != compact(expectedHelper) ||
      compact(consumer) != compact(expectedConsumer)) {
    return source;
  }

  final reference = RegExp(r'\b' + RegExp.escape(helperName) + r'\b');
  final outside =
      source.substring(0, helperStart) +
      source.substring(helperEnd, consumerStart) +
      source.substring(consumerEnd);
  if (reference.allMatches(helper).length != 1 ||
      reference.allMatches(consumer).length != 1 ||
      reference.hasMatch(outside)) {
    return source;
  }
  final renderedWidget = RegExp(
    r'\b(?:Text|RichText|SelectableText|Widget)(?:\.\w+)?\s*\(',
  );
  final bannedWeight = RegExp(r'FontWeight\.(bold|w[5-9]00)');
  final bannedToken = RegExp(r'\bDesignTokens\.fontWeightMedium\b');
  if (renderedWidget.hasMatch(helper) ||
      renderedWidget.hasMatch(consumer) ||
      bannedWeight.allMatches(helper).length != 1 ||
      bannedWeight.hasMatch(consumer) ||
      bannedToken.hasMatch(helper) ||
      bannedToken.hasMatch(consumer) ||
      !consumer.contains('final painter = TextPainter(') ||
      !consumer.contains('painter.dispose();')) {
    return source;
  }
  final guards = RegExp(
    r'if\s*\(MediaQuery\.boldTextOf\(context\)\)\s*\{[^{}]*\}',
  ).allMatches(helper).toList();
  if (guards.length != 1 ||
      compact(guards.single.group(0)!) !=
          'if(MediaQuery.boldTextOf(context)){'
          'effectiveTextStyle=effectiveTextStyle!.merge('
          'constTextStyle(fontWeight:FontWeight.bold),);}') {
    return source;
  }
  final guard = guards.single;
  // Mask only the platform branch; preserve all other source and line numbers.
  return source.replaceRange(
    helperStart + guard.start,
    helperStart + guard.end,
    guard.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
}

// These local styles only measure the system's accessibility typography.
// Fail closed if they escape into rendered UI or lose their platform guard.
String _maskAccessibilityMeasurement(String path, String source) {
  final String endMarker;
  final String expectedGuard;
  final List<String> localNames;
  if (path == 'lib/screens/diary_screen.dart') {
    endMarker = 'final requiredWidth = badgesWidth + timeWidth;';
    expectedGuard =
        'if(isBold){effective=effective.merge(constTextStyle(fontWeight:FontWeight.bold),);}';
    localNames = [
      'effectiveTimeStyle',
      'effectiveBadgeStyle',
      'resolveEffectiveTextStyle',
    ];
  } else if (path == 'lib/widgets/pomodoro_session_card.dart') {
    endMarker =
        'final minMetadataWidth = math.max(timeItemWidth, durItemWidth);';
    expectedGuard =
        'if(MediaQuery.maybeBoldTextOf(context)??false){effectiveMetadataStyle=effectiveMetadataStyle.merge(constTextStyle(fontWeight:FontWeight.bold),);}';
    localNames = ['effectiveMetadataStyle'];
  } else {
    return source;
  }
  const startMarker = 'final defaultTextStyle = DefaultTextStyle.of(context);';
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start < 0 ? 0 : start);
  if (start < 0 ||
      end <= start ||
      source.indexOf(startMarker, start + 1) >= 0 ||
      source.indexOf(endMarker, end + 1) >= 0) {
    return source;
  }
  final region = source.substring(start, end);
  final outside = source.substring(0, start) + source.substring(end);
  if (RegExp(r'\b(?:Text|Widget)(?:\.\w+)?\s*\(').hasMatch(region) ||
      localNames.any((name) => RegExp('\\b$name\\b').hasMatch(outside)) ||
      !region.contains('TextPainter(') ||
      !region.contains('.dispose();') ||
      (path == 'lib/screens/diary_screen.dart' &&
          !region.contains('final isBold = MediaQuery.boldTextOf(context);'))) {
    return source;
  }
  final guards = RegExp(
    r'if\s*\([^{}]*\)\s*\{[^{}]*FontWeight\.bold[^{}]*\}',
  ).allMatches(region).toList();
  if (guards.length != 1 ||
      RegExp(r'FontWeight\.(bold|w[5-9]00)').allMatches(region).length != 1) {
    return source;
  }
  final guard = guards.single;
  if (guard.group(0)!.replaceAll(RegExp(r'\s+'), '') != expectedGuard) {
    return source;
  }
  return source.replaceRange(
    start + guard.start,
    start + guard.end,
    guard.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
}

void main() {
  for (final path in [
    'lib/screens/today_screen.dart',
    'lib/widgets/eisenhower_matrix.dart',
  ]) {
    final helperName = path == 'lib/screens/today_screen.dart'
        ? '_todayEffectiveTextStyle'
        : '_matrixEffectiveTextStyle';
    test('returned measurement guard requires its platform branch in $path', () {
      final source = File(path).readAsStringSync();
      final masked = _maskReturnedAccessibilityMeasurement(path, source);
      expect(masked, isNot(source));
      expect(masked.split('\n'), hasLength(source.split('\n').length));
      expect(RegExp(r'FontWeight\.(bold|w[5-9]00)').hasMatch(masked), isFalse);
    });
    test('returned measurement guard rejects duplicate helper in $path', () {
      final original = File(path).readAsStringSync();
      final start = original.indexOf('TextStyle $helperName(');
      final endMarker = path == 'lib/screens/today_screen.dart'
          ? 'double _measureTodayTextWidth('
          : 'class _QuadrantCard';
      final end = original.indexOf(endMarker, start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final source = '$original\n${original.substring(start, end)}';
      expect(_maskReturnedAccessibilityMeasurement(path, source), source);
    });
    test('returned measurement guard rejects rendered widget in $path', () {
      final source = File(path).readAsStringSync().replaceFirst(
        'var effectiveTextStyle = style;',
        "var effectiveTextStyle = style; Text('unexpected');",
      );
      expect(_maskReturnedAccessibilityMeasurement(path, source), source);
    });
    test('returned measurement guard rejects unconditional bold in $path', () {
      final source = File(path).readAsStringSync().replaceFirst(
        'if (MediaQuery.boldTextOf(context))',
        'if (true)',
      );
      expect(_maskReturnedAccessibilityMeasurement(path, source), source);
    });
    test('returned measurement guard rejects helper tear-off in $path', () {
      final source = '${File(path).readAsStringSync()}\n'
          'final escapedMeasurementStyle = $helperName;';
      expect(_maskReturnedAccessibilityMeasurement(path, source), source);
    });
    test('returned measurement guard rejects another call in $path', () {
      final source = '${File(path).readAsStringSync()}\n'
          'final escapedMeasurementStyle = '
          '$helperName(context, const TextStyle());';
      expect(_maskReturnedAccessibilityMeasurement(path, source), source);
    });
    test('returned measurement guard rejects returned style escape in $path', () {
      final original = File(path).readAsStringSync();
      final startMarker = path == 'lib/screens/today_screen.dart'
          ? 'double _measureTodayTextWidth('
          : 'Size measuredSize(';
      final endMarker = path == 'lib/screens/today_screen.dart'
          ? 'double _overdueBadgeEstimatedWidth('
          : 'const dotAndGap = 14.0;';
      final start = original.indexOf(startMarker);
      final end = original.indexOf(endMarker, start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final region = original.substring(start, end);
      final returnValue = path == 'lib/screens/today_screen.dart'
          ? 'return width;'
          : 'return size;';
      expect(region, contains(returnValue));
      final source = original.replaceRange(
        start,
        end,
        region.replaceFirst(returnValue, 'return const TextStyle();'),
      );
      expect(_maskReturnedAccessibilityMeasurement(path, source), source);
    });
    test('returned measurement guard rejects a library part in $path', () {
      final source = "part 'escaped_measurement.dart';\n${File(path).readAsStringSync()}";
      expect(_maskReturnedAccessibilityMeasurement(path, source), source);
    });
    test('returned measurement guard preserves other global bold in $path', () {
      const extra =
          "Widget unexpected() => Text('unexpected', "
          'style: TextStyle(fontWeight: FontWeight.bold));';
      final source = '${File(path).readAsStringSync()}\n$extra';
      final masked = _maskReturnedAccessibilityMeasurement(path, source);
      expect(masked, isNot(source));
      expect(masked, contains(extra));
      expect(
        RegExp(r'FontWeight\.(bold|w[5-9]00)').allMatches(masked),
        hasLength(1),
      );
    });
  }

  for (final path in [
    'lib/screens/diary_screen.dart',
    'lib/widgets/pomodoro_session_card.dart',
  ]) {
    test('measurement guard rejects an added rendered widget in $path', () {
      final source = File(path).readAsStringSync().replaceFirst(
        'final defaultTextStyle = DefaultTextStyle.of(context);',
        "final defaultTextStyle = DefaultTextStyle.of(context); Text('unexpected');",
      );
      expect(_maskAccessibilityMeasurement(path, source), source);
    });
    test('measurement guard preserves added global bold in $path', () {
      final source =
          '${File(path).readAsStringSync()}\n'
          "Widget unexpected() => Text('unexpected', style: TextStyle(fontWeight: FontWeight.bold));";
      final masked = _maskAccessibilityMeasurement(path, source);
      expect(
        RegExp(r'FontWeight\.(bold|w[5-9]00)').allMatches(masked),
        hasLength(1),
      );
      expect(
        masked,
        contains(
          "Widget unexpected() => Text('unexpected', style: TextStyle(fontWeight: FontWeight.bold));",
        ),
      );
    });
    test('measurement guard rejects an unconditional override in $path', () {
      final source = File(path)
          .readAsStringSync()
          .replaceFirst('if (isBold)', 'if (true)')
          .replaceFirst(
            'if (MediaQuery.maybeBoldTextOf(context) ?? false)',
            'if (true)',
          );
      expect(_maskAccessibilityMeasurement(path, source), source);
    });
  }

  test('应用 UI 不再引入全局粗体字重', () {
    final bannedWeight = RegExp(r'FontWeight\.(bold|w[5-9]00)');
    final bannedTokenUse = RegExp(r'\bDesignTokens\.fontWeightMedium\b');
    final offenders = <String>[];

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final originalSource = file.readAsStringSync();
      final returnedMeasurementSource =
          _maskReturnedAccessibilityMeasurement(file.path, originalSource);
      if (file.path == 'lib/screens/today_screen.dart' ||
          file.path == 'lib/widgets/eisenhower_matrix.dart') {
        expect(
          returnedMeasurementSource,
          isNot(originalSource),
          reason: 'Require exact platform guard, unique helper, and sole '
              'non-rendering measurement consumer; no returned style escapes.',
        );
      }
      var lines = _maskAccessibilityMeasurement(
        file.path,
        returnedMeasurementSource,
      ).split('\n');
      if (file.path == 'lib/screens/widget_screen.dart') {
        // This pure helper measures Text's system accessibility typography.
        final source = lines.join('\n');
        final start = source.indexOf('TextStyle _widgetMeasurementStyle(');
        expect(start, greaterThanOrEqualTo(0));
        final end = source.indexOf('\nAxis _widgetSegmentDirection(', start);
        expect(end, greaterThan(start));
        final measurementHelper = source.substring(start, end);
        expect(
          measurementHelper,
          matches(
            RegExp(
              r'^TextStyle _widgetMeasurementStyle\(BuildContext context, TextStyle style\) \{[^{}]*\}\s*$',
            ),
          ),
        );
        expect(
          measurementHelper,
          matches(
            RegExp(
              r'fontWeight:\s*MediaQuery\.boldTextOf\(context\)\s*\?\s*FontWeight\.bold\s*:\s*inherited\.fontWeight',
            ),
          ),
        );
        expect(
          measurementHelper,
          contains('MediaQuery.maybeLineHeightScaleFactorOverrideOf(context)'),
        );
        expect(
          RegExp(
            r'\b(?:Text|Widget)(?:\.\w+)?\s*\(',
          ).hasMatch(measurementHelper),
          isFalse,
        );
        expect(bannedWeight.allMatches(measurementHelper), hasLength(1));
        expect(bannedTokenUse.hasMatch(measurementHelper), isFalse);
        // Keep every original line number in the rest of the global scan.
        lines = source
            .replaceRange(
              start,
              end,
              measurementHelper.replaceAll(RegExp(r'[^\n]'), ' '),
            )
            .split('\n');
      }
      if (file.path == 'lib/widgets/calendar_day_agenda.dart') {
        // Text itself applies the platform's bold accessibility setting.
        // The numeric gutter calculation must measure that same typography;
        // this helper never creates a widget or changes the rendered style.
        final source = lines.join('\n');
        const signature =
            '  static double _resolveTimeColumnWidth(BuildContext context) {';
        final start = source.indexOf(signature);
        expect(start, greaterThanOrEqualTo(0));
        final end = source.indexOf('\n  @override', start);
        expect(end, greaterThan(start));
        final measurementHelper = source.substring(start, end);
        expect(source.split(signature), hasLength(2));
        expect(
          measurementHelper,
          matches(
            RegExp(
              r'if \(MediaQuery\.boldTextOf\(context\)\) \{\s*labelStyle = labelStyle\.merge\(const TextStyle\(fontWeight: FontWeight\.bold\)\);\s*\}',
            ),
          ),
        );
        expect(
          RegExp(
            r'\b(?:Text|Widget)(?:\.\w+)?\s*\(',
          ).hasMatch(measurementHelper),
          isFalse,
        );
        expect(measurementHelper, contains('final painter = TextPainter('));
        expect(measurementHelper, contains('painter.dispose();'));
        expect(
          measurementHelper,
          contains('return math.max(_timeColumnWidth, maxLabelWidth);'),
        );
        expect(bannedWeight.allMatches(measurementHelper), hasLength(1));
        expect(bannedTokenUse.hasMatch(measurementHelper), isFalse);
        lines = source
            .replaceRange(
              start,
              end,
              measurementHelper.replaceAll(RegExp(r'[^\n]'), ' '),
            )
            .split('\n');
        final cardSource = lines.join('\n');
        const cardSignature = '  static double _measureCompactEventWidth(';
        final cardStart = cardSource.indexOf(cardSignature);
        expect(cardStart, greaterThanOrEqualTo(0));
        final cardEnd = cardSource.indexOf(
          '\n  (List<_CalendarEventPlacement>, double) _computeEventPlacements(',
          cardStart,
        );
        expect(cardEnd, greaterThan(cardStart));
        final cardHelper = cardSource.substring(cardStart, cardEnd);
        expect(cardSource.split(cardSignature), hasLength(2));
        for (final style in ['titleStyle', 'timeStyle', 'badgeStyle']) {
          expect(
            cardHelper,
            matches(
              RegExp(
                r'if \(MediaQuery\.boldTextOf\(context\)\) \{\s*'
                '$style = $style'
                r'\.merge\(const TextStyle\(fontWeight: FontWeight\.bold\)\);\s*\}',
              ),
            ),
          );
        }
        expect(
          RegExp(r'\b(?:Text|Widget)(?:\.\w+)?\s*\(').hasMatch(cardHelper),
          isFalse,
        );
        expect(cardHelper, contains('titlePainter.dispose();'));
        expect(cardHelper, contains('timePainter.dispose();'));
        expect(cardHelper, contains('badgePainter.dispose();'));
        expect(bannedWeight.allMatches(cardHelper), hasLength(3));
        expect(bannedTokenUse.hasMatch(cardHelper), isFalse);
        lines = cardSource
            .replaceRange(
              cardStart,
              cardEnd,
              cardHelper.replaceAll(RegExp(r'[^\n]'), ' '),
            )
            .split('\n');
      }
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (bannedWeight.hasMatch(line) || bannedTokenUse.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '用户要求去掉全局粗体；新增 UI 请使用主题默认字重或 FontWeight.normal，不再正向使用 DesignTokens.fontWeightMedium。',
    );
  });

  test('全局设计令牌和管理后台不再提供粗体入口', () {
    final bannedWeight = RegExp(r'FontWeight\.(bold|w[5-9]00)');
    final designTokens = File('lib/core/design_tokens.dart').readAsStringSync();
    final appBrand = File('lib/core/app_brand.dart').readAsStringSync();
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final surface = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    for (final source in [designTokens, appBrand, admin, surface]) {
      expect(source, isNot(contains('DesignTokens.fontWeightMedium')));
      expect(source, isNot(bannedWeight));
    }

    final adminExplicitWeights = RegExp(
      r'fontWeight:\s+FontWeight\.(\w+)',
    ).allMatches(admin).map((match) => match.group(1)).toSet();

    expect(
      adminExplicitWeights,
      everyElement(equals('normal')),
      reason: '管理员后台用户明确要求不要粗体，显式字重只能是 normal。',
    );

    final adminFontWeightAssignments = RegExp(
      r'fontWeight:\s*([^,\n)]+)',
    ).allMatches(admin).map((match) => match.group(1)!.trim()).toList();

    expect(
      adminFontWeightAssignments,
      everyElement(equals('FontWeight.normal')),
      reason: '管理员后台不应通过局部 TextStyle 或主题样式恢复粗体；如需显式声明，只允许 FontWeight.normal。',
    );
  });
}
