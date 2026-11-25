import 'dart:math' as math;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/completion_visibility_policy.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/widgets/critical_storage_gate.dart';
import 'package:duoyi/widgets/result_states.dart';
import 'package:duoyi/widgets/surface_components.dart';
// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('AppBrands dark themes expose M3 surface layering, refined error, and appBar foreground', () {
    expect(AppBrands.all.length, 9);
    expect(DesignTokens.defaultPrimary, const Color(0xFF0066D6));
    expect(DesignTokens.defaultPrimarySoft, const Color(0xFFE5F1FF));
    expect(DesignTokens.defaultPrimaryPressed, const Color(0xFF0051AB));
    expect(DesignTokens.defaultTextMuted, const Color(0xFF667085));
    expect(DesignTokens.defaultPageBackground, const Color(0xFFF6F7F9));

    final darkBrands = AppBrands.all.where(
      (b) => b.theme.brightness == Brightness.dark,
    );
    expect(darkBrands, isNotEmpty);

    for (final brand in darkBrands) {
      final theme = brand.theme;
      final cs = theme.colorScheme;
      final label = brand.id;

      expect(
        cs.surfaceContainerLowest.computeLuminance(),
        lessThan(cs.surface.computeLuminance()),
        reason: '$label surfaceContainerLowest should anchor deeper than surface',
      );
      expect(
        cs.surface.computeLuminance(),
        lessThan(cs.surfaceContainerLow.computeLuminance()),
        reason: '$label surfaceContainerLow should step above surface',
      );
      expect(
        cs.surfaceContainerLow.computeLuminance(),
        lessThan(cs.surfaceContainer.computeLuminance()),
        reason: '$label surfaceContainer should step above surfaceContainerLow',
      );
      expect(
        cs.surfaceContainer.computeLuminance(),
        lessThan(cs.surfaceContainerHigh.computeLuminance()),
        reason: '$label surfaceContainerHigh should step above surfaceContainer',
      );
      expect(
        cs.surfaceContainerHigh.computeLuminance(),
        lessThan(cs.surfaceContainerHighest.computeLuminance()),
        reason:
            '$label surfaceContainerHighest should step above surfaceContainerHigh',
      );

      expect(cs.error, const Color(0xFFFF6961), reason: '$label dark error');
      expect(
        _contrastRatio(cs.error, cs.surface),
        greaterThanOrEqualTo(4.5),
        reason: '$label dark error contrast',
      );
      expect(
        theme.appBarTheme.foregroundColor,
        cs.onSurface,
        reason: '$label appBar foreground should match onSurface',
      );

      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.side.width, 0.5, reason: '$label card border width');

      final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
      expect(dialogShape.side.width, 0.5, reason: '$label dark dialog border');
    }
  });

  test('All 9 brands preserve typography rhythm without bold weights and keep accessible dialogs, snackbars, and transitions', () {
    for (final brand in AppBrands.all) {
      final theme = brand.theme;
      final tt = theme.textTheme;
      final isDark = theme.brightness == Brightness.dark;
      final label = brand.id;

      expect(tt.displayLarge?.letterSpacing, -0.3, reason: label);
      expect(tt.headlineLarge?.letterSpacing, -0.3, reason: label);
      expect(tt.bodySmall?.letterSpacing, 0.15, reason: label);
      expect(tt.labelSmall?.letterSpacing, 0.15, reason: label);

      final textStyles = <TextStyle?>[
        tt.displayLarge,
        tt.displayMedium,
        tt.displaySmall,
        tt.headlineLarge,
        tt.headlineMedium,
        tt.headlineSmall,
        tt.titleLarge,
        tt.titleMedium,
        tt.titleSmall,
        tt.bodyLarge,
        tt.bodyMedium,
        tt.bodySmall,
        tt.labelLarge,
        tt.labelMedium,
        tt.labelSmall,
      ];
      for (final s in textStyles) {
        final w = s?.fontWeight;
        expect(
          w == null || w.value <= 400,
          isTrue,
          reason: '$label textTheme must avoid bold tokens (found $w)',
        );
      }

      if (!isDark) {
        expect(theme.dialogTheme.elevation, 8, reason: '$label light dialog');
      } else {
        expect(theme.dialogTheme.elevation, 0, reason: '$label dark dialog');
      }

      final sb = theme.snackBarTheme;
      expect(sb.elevation, 4, reason: '$label snackBar elevation');
      final sbShape = sb.shape as RoundedRectangleBorder;
      expect(sbShape.side.width, 0.45, reason: '$label snackBar border');
      final sbBg = sb.backgroundColor!;
      expect(sbBg.a, 1.0, reason: '$label snackBar background must be opaque');
      expect(
        _contrastRatio(sb.contentTextStyle!.color!, sbBg),
        greaterThanOrEqualTo(4.5),
        reason: '$label snackBar content contrast',
      );
      expect(
        _contrastRatio(sb.actionTextColor!, sbBg),
        greaterThanOrEqualTo(4.5),
        reason: '$label snackBar action contrast',
      );

      final builders = theme.pageTransitionsTheme.builders;
      expect(
        builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>(),
        reason: '$label iOS page transition',
      );
      expect(
        builders[TargetPlatform.macOS],
        isA<CupertinoPageTransitionsBuilder>(),
        reason: '$label macOS page transition',
      );
      if (brand.id == AppBrands.defaultBrand.id ||
          brand.id == AppBrands.liquidGlass.id) {
        expect(
          builders[TargetPlatform.android],
          isA<CupertinoPageTransitionsBuilder>(),
          reason: '$label Android transition uses Cupertino feel',
        );
      } else {
        expect(
          builders[TargetPlatform.android],
          isA<FadeForwardsPageTransitionsBuilder>(),
          reason: '$label Android transition uses FadeForwards feel',
        );
      }
    }
  });

  test('CompletionVisibilityPolicy provides high-contrast light and dark colors', () {
    const lightSurface = Color(0xFFFFFFFF);
    const darkSurface = Color(0xFF161C30);

    for (final state in TodoVisualState.values) {
      final lightColor = CompletionVisibilityPolicy.colorFor(
        state,
        isDark: false,
      );
      final darkColor = CompletionVisibilityPolicy.colorFor(
        state,
        isDark: true,
      );
      expect(
        _contrastRatio(lightColor, lightSurface),
        greaterThanOrEqualTo(4.5),
        reason: 'light $state contrast',
      );
      expect(
        _contrastRatio(darkColor, darkSurface),
        greaterThanOrEqualTo(4.5),
        reason: 'dark $state contrast',
      );
      expect(
        darkColor,
        isNot(const Color(0xDE000000)),
        reason: 'dark $state must never fall back to black87',
      );
    }
  });

  testWidgets('AppMetricCard formats 0% without leading space, applies tabularFigures, and elevates dark surface', (tester) async {
    final darkTheme = AppBrands.starRail.theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(
          body: AppMetricCard(
            title: 'Completion',
            value: '0',
            unit: '%',
            icon: Icons.check_circle_outline,
            color: Color(0xFF7EA2FF),
          ),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (w) => w is Text && w.textSpan != null,
    );
    expect(richTextFinder, findsOneWidget);
    final richWidget = tester.widget<Text>(richTextFinder);
    final rootSpan = richWidget.textSpan! as TextSpan;
    expect(rootSpan.toPlainText(), '0%');
    expect(find.textContaining('0 %'), findsNothing);

    final valueSpan = rootSpan.children!.first as TextSpan;
    expect(
      valueSpan.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    final ink = tester.widget<Ink>(
      find.byWidgetPredicate(
        (w) => w is Ink && w.decoration is BoxDecoration,
      ),
    );
    final fillColor = (ink.decoration! as BoxDecoration).color!;
    expect(fillColor.a, 1.0);
    expect(
      fillColor.computeLuminance(),
      greaterThan(darkTheme.colorScheme.surface.computeLuminance()),
    );
  });

  testWidgets('EmptyState(embedded: true) avoids nested AppSurfaceCard and uses tonal inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: const Scaffold(
          body: EmptyState(
            icon: Icons.inbox_outlined,
            message: 'Nothing here',
            embedded: true,
          ),
        ),
      ),
    );

    expect(find.byType(AppSurfaceCard), findsNothing);
    final tonalInset = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color ==
              AppBrands.defaultBrand.theme.colorScheme.surfaceContainerLow,
    );
    expect(tonalInset, findsOneWidget);
  });

  testWidgets('AppSettingsSection(showDividers: true) inserts 0.5px hairline dividers between tiles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Scaffold(
          body: AppSettingsSection(
            title: 'Preferences',
            showDividers: true,
            children: const [
              AppSettingsTile(
                icon: Icons.palette_outlined,
                title: 'Theme',
                color: Color(0xFF0066D6),
              ),
              AppSettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Reminders',
                color: Color(0xFF0066D6),
              ),
              AppSettingsTile(
                icon: Icons.backup_outlined,
                title: 'Backup',
                color: Color(0xFF0066D6),
              ),
            ],
          ),
        ),
      ),
    );

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers.length, 2);
    for (final divider in dividers) {
      expect(divider.height, 1);
      expect(divider.thickness, 0.5);
      expect(divider.indent, 48);
    }
  });

  testWidgets('LoadingState shimmer bars adapt colors for dark and light themes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('dark-shimmer'),
        theme: AppBrands.starRail.theme,
        home: const Scaffold(body: LoadingState(lines: 2)),
      ),
    );

    final darkShimmers = tester
        .widgetList<DecoratedBox>(
          find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).gradient is LinearGradient,
          ),
        )
        .toList();
    expect(darkShimmers.length, 2);
    final darkGradient =
        (darkShimmers.first.decoration as BoxDecoration).gradient!
            as LinearGradient;
    expect(darkGradient.colors, const [
      DesignTokens.resultLoadingShimmerBaseDark,
      DesignTokens.resultLoadingShimmerHighlightDark,
      DesignTokens.resultLoadingShimmerBaseDark,
    ]);

    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('light-shimmer'),
        theme: AppBrands.defaultBrand.theme,
        home: const Scaffold(body: LoadingState(lines: 2)),
      ),
    );

    final lightShimmers = tester
        .widgetList<DecoratedBox>(
          find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).gradient is LinearGradient,
          ),
        )
        .toList();
    expect(lightShimmers.length, 2);
    final lightGradient =
        (lightShimmers.first.decoration as BoxDecoration).gradient!
            as LinearGradient;
    expect(lightGradient.colors, const [
      DesignTokens.resultLoadingShimmerBase,
      DesignTokens.resultLoadingShimmerHighlight,
      DesignTokens.resultLoadingShimmerBase,
    ]);
  });

  testWidgets('CriticalStorageGate retry button preserves accessible contrast across all 9 brands', (tester) async {
    for (final brand in AppBrands.all) {
      await tester.pumpWidget(
        MaterialApp(
          theme: brand.theme,
          home: CriticalStorageGate(
            busy: false,
            failed: true,
            onRetry: () {},
          ),
        ),
      );

      final retryBtnFinder = find.byKey(const ValueKey('critical_storage_retry'));
      expect(retryBtnFinder, findsOneWidget, reason: brand.id);

      final btnMaterial = tester.widget<Material>(
        find
            .descendant(
              of: retryBtnFinder,
              matching: find.byType(Material),
            )
            .first,
      );
      final bg =
          (btnMaterial.color ??
          brand.theme.filledButtonTheme.style?.backgroundColor?.resolve(
            const <WidgetState>{},
          ))!;
      final labelFinder = find.descendant(
        of: retryBtnFinder,
        matching: find.byType(Text),
      );
      final fg = DefaultTextStyle.of(tester.element(labelFinder.first)).style.color!;

      expect(
        _contrastRatio(fg, bg),
        greaterThanOrEqualTo(4.5),
        reason: '${brand.id} CriticalStorageGate retry contrast ($fg on $bg)',
      );
    }
  });
}
