import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('更多应用入口在行动计划内并以二级页面打开隐藏功能', () {
    final main = File('lib/main.dart').readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();

    final actionPlanStart = mine.indexOf(
      "title: I18n.tr('mine.group.action_plan')",
    );
    final reviewStart = mine.indexOf("title: I18n.tr('mine.group.review')");
    final moreAppsTile = mine.indexOf("label: I18n.tr('mine.tile.more_apps')");
    expect(actionPlanStart, greaterThanOrEqualTo(0));
    expect(reviewStart, greaterThan(actionPlanStart));
    expect(moreAppsTile, inInclusiveRange(actionPlanStart, reviewStart));
    expect(mine, contains('onTap: () => _openMoreApplications(context)'));

    expect(
      main,
      isNot(
        contains(
          'onOpenHiddenBottomNavTab: (tab) => navigateTo(tab, allowHidden: true)',
        ),
      ),
    );
    expect(
      main,
      matches(
        RegExp(
          r'WidgetScreen\(\s*key:\s*widgetKey,\s*isActive:\s*tab\s*==\s*activeIndex,\s*activityRevision:\s*_widgetActivityRevision,?\s*\)',
        ),
      ),
    );
    expect(main, contains('final Set<int> _builtTabs = <int>{0}'));
    expect(main, contains('_LazyTabPlaceholder'));
    expect(main, contains('_buildTab(tab, safeVisibleTabs, safeIndex)'));
    expect(main, contains('_navigateWidgetSection(state, ctx, idx);'));
    expect(main, contains('bottomNavigationBar: showingHiddenTab'));
    expect(main, contains("? 'Back to Me' : '返回我的'"));

    expect(
      moreApps,
      isNot(contains('final openHiddenTab = onOpenHiddenBottomNavTab')),
    );
    expect(
      moreApps,
      isNot(contains('final ValueChanged<int>? onOpenHiddenTab')),
    );
    expect(moreApps, isNot(contains('final shellOpen = onOpenHiddenTab')));
    expect(moreApps, isNot(contains('shellOpen(app.tab);')));
    expect(moreApps, isNot(contains('Navigator.of(context).maybePop()')));
    expect(
      moreApps,
      isNot(contains('WidgetsBinding.instance.addPostFrameCallback')),
    );
    expect(moreApps, contains('Navigator.of(context).push('));
    expect(moreApps, contains('BrandRouteSurface('));
    expect(moreApps, contains('builder: (routeContext)'));
    expect(moreApps, contains('child: app.builder(routeContext)'));
    expect(moreApps, contains('appSecondaryMenuItemTextStyle('));
    expect(moreApps, isNot(contains('fontSize: 13')));
    expect(moreApps, contains("label: I18n.tr('nav.widget')"));
    expect(moreApps, contains('builder: (_) => const WidgetScreen()'));
    expect(moreApps, isNot(contains("label: '番茄专注'")));
    expect(moreApps, isNot(contains("label: '倒数日'")));
    expect(moreApps, isNot(contains('CountdownScreen')));
  });

  test('widget deep links keep hidden routes reachable and detail rows clickable', () {
    final main = File('lib/main.dart').readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinResultReceiver.kt',
    ).readAsStringSync();
    final providers = <String, _ProviderRouteCheck>{
      'goal': _ProviderRouteCheck(
        fileName: 'DuoyiGoalWidgetProvider.kt',
        keyPrefix: 'goal_highlight_',
        fallback: 'duoyi://goal',
      ),
      'course': _ProviderRouteCheck(
        fileName: 'DuoyiCourseWidgetProvider.kt',
        keyPrefix: 'course_highlight_',
        fallback: 'duoyi://course',
      ),
      'schedule': _ProviderRouteCheck(
        fileName: 'DuoyiScheduleWidgetProvider.kt',
        keyPrefix: 'schedule_highlight_',
        fallback: 'duoyi://calendar',
      ),
      'note': _ProviderRouteCheck(
        fileName: 'DuoyiNoteWidgetProvider.kt',
        keyPrefix: 'note_highlight_',
        fallback: 'duoyi://note',
      ),
      'anniversary': _ProviderRouteCheck(
        fileName: 'DuoyiAnniversaryWidgetProvider.kt',
        keyPrefix: 'memorial_highlight_',
        fallback: 'duoyi://anniversary',
      ),
      'diary': _ProviderRouteCheck(
        fileName: 'DuoyiDiaryWidgetProvider.kt',
        keyPrefix: 'diary_highlight_',
        fallback: 'duoyi://diary',
      ),
    };

    for (final tab in ['todo', 'habit', 'calendar', 'focus', 'widget']) {
      expect(main, contains("'$tab' => "));
    }
    expect(main, contains('_navigateWidgetSection(state, ctx, idx);'));
    expect(main, contains('_navigateWidgetSection(state, ctx, 4)'));
    expect(main, contains('_navigateWidgetSection(state, ctx, 1)'));
    expect(main, contains('_navigateWidgetSection(state, ctx, 2)'));
    expect(main, contains('_navigateWidgetSection(state, ctx, 5)'));
    expect(main, contains('_pushHiddenWidgetFallbackRoute'));
    expect(
      main,
      contains('mainShellKey.currentState?.navigateTo(6, allowHidden: true)'),
      reason:
          'Fallback module links should route through the More Apps/Mine surface so hidden pages remain reachable.',
    );
    expect(
      main,
      contains('BrandRouteSurface(child: child)'),
      reason: 'Hidden fallback pages need the same route backing surface.',
    );
    expect(
      main,
      contains(
        '_pushHiddenWidgetFallbackRoute(ctx, const GoalScreen(), access)',
      ),
    );
    expect(
      main,
      contains(
        '_pushHiddenWidgetFallbackRoute(ctx, const CourseScheduleScreen(), access)',
      ),
    );
    expect(
      main,
      contains(
        '_pushHiddenWidgetFallbackRoute(ctx, const AnniversaryScreen(), access)',
      ),
    );
    expect(
      main,
      contains(
        '_pushHiddenWidgetFallbackRoute(ctx, const NoteScreen(), access)',
      ),
    );
    expect(
      main,
      contains(
        '_pushHiddenWidgetFallbackRoute(ctx, const DiaryScreen(), access)',
      ),
    );

    expect(
      receiver,
      contains(
        'DuoyiWidgetProviderRegistry.requestUpdateForKind(context, kind)',
      ),
    );
    expect(receiver, isNot(contains('.requestUpdate(context)')));

    for (final entry in providers.entries) {
      final source = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/${entry.value.fileName}',
      ).readAsStringSync();
      if (entry.key == 'anniversary') {
        final content = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetContent.kt',
        ).readAsStringSync();
        expect(source, contains('DuoyiWidgetContent.resolveAnniversaryItems('));
        expect(
          source,
          contains('Uri.parse(item1?.target ?: "duoyi://anniversary")'),
        );
        expect(
          source,
          contains('Uri.parse(item2?.target ?: "duoyi://anniversary")'),
        );
        expect(
          source,
          contains('Uri.parse(item3?.target ?: "duoyi://anniversary")'),
        );
        expect(content, contains('fun parseAnniversaryTarget('));
        expect(
          content,
          contains(r'return "duoyi://anniversary/$encoded" to raw'),
        );
        continue;
      }
      expect(
        source,
        contains(
          'DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))',
        ),
      );
      expect(
        source,
        contains('if (rawId.isBlank()) return Uri.parse(fallback)'),
      );
      expect(
        source,
        contains('if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)'),
        reason:
            '${entry.key} should not double-encode full duoyi:// detail links saved by Flutter.',
      );
      expect(source, contains(r'Uri.parse("$fallback/${Uri.encode(rawId)}")'));
      expect(
        source,
        isNot(
          contains(
            'Uri.parse((prefs.getString(key, "") ?: "").ifBlank { fallback })',
          ),
        ),
      );
      for (var index = 1; index <= 3; index++) {
        expect(
          source,
          contains(
            'itemIntent(context, frame, "${entry.value.keyPrefix}${index}_id", "${entry.value.fallback}")',
          ),
          reason: '${entry.key} row $index should open detail or fallback page',
        );
      }
    }
  });

  test('widget click streams are deferred before opening hidden tabs', () {
    final main = File('lib/main.dart').readAsStringSync();

    final handlerStart = main.indexOf('void handleDeepLink(Uri uri)');
    final handlerEnd = main.indexOf('DeepLinkService.onLink =', handlerStart);
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = main.substring(handlerStart, handlerEnd);
    expect(handler, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(handler, contains('_widgetNavigationRequests.capture()'));
    expect(
      handler,
      contains(
        '_handleWidgetUri(uri, pomodoroProvider, navigationRequest: request)',
      ),
    );

    final widgetStreamStart = main.indexOf(
      'HomeWidgetService.widgetClickedStream.listen',
    );
    final widgetStreamEnd = main.indexOf('} catch (e, st)', widgetStreamStart);
    expect(widgetStreamStart, greaterThanOrEqualTo(0));
    expect(widgetStreamEnd, greaterThan(widgetStreamStart));
    final widgetStream = main.substring(widgetStreamStart, widgetStreamEnd);
    expect(widgetStream, contains('if (uri != null) handleDeepLink(uri);'));
    expect(
      widgetStream,
      isNot(contains('_handleWidgetUri(uri, pomodoroProvider)')),
      reason:
          'Widget stream taps should use the deferred deep-link handler so hidden tabs are not lost while the shell is attaching.',
    );

    expect(main, contains('HomeWidgetService.initialLaunchUri()'));
    expect(main, contains('DeepLinkService.takeInitialLink()'));
    expect(main, contains('_handleWidgetUri(initial, pomodoroProvider)'));
    expect(
      main,
      contains('_handleWidgetUri(initialDeepLink, pomodoroProvider)'),
    );
    expect(
      main,
      contains('final List<_PendingWidgetLaunch> _pendingWidgetUris'),
    );
    expect(main, contains('void _queuePendingWidgetUri('));
    expect(
      main,
      contains('void _drainPendingWidgetUris(PomodoroProvider pomodoro)'),
    );
    expect(
      main,
      contains("'main shell not ready after \$retry frames'"),
      reason:
          'Deep links that arrive before the shell attaches should be queued instead of dropped.',
    );
    expect(
      main,
      contains("_drainPendingWidgetUris(context.read<PomodoroProvider>())"),
    );
    expect(main, contains("debugPrint('[DeepLink] unsupported entry')"));
    final deepLinkDiagnostics = main
        .split('\n')
        .where((line) => line.contains("debugPrint('[DeepLink]"));
    for (final diagnostic in deepLinkDiagnostics) {
      expect(diagnostic, isNot(contains(r'$uri')));
      expect(diagnostic, isNot(contains(r'${uri.')));
    }
    expect(main, contains('_navigateWidgetSection(state, ctx, 6);'));
  });

  test(
    'share text note route keeps brand surface instead of transparent route',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      final start = main.indexOf('Future<void> _showSharedTextImportSheet(');
      expect(start, greaterThanOrEqualTo(0));
      final end = main.indexOf('Future<void> _showTodoCompletePrompt(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final noteBranch = main.substring(start, end);

      expect(noteBranch, contains('NoteItem('));
      expect(noteBranch, contains('await notes.addOrUpdateNotePersisted('));
      expect(noteBranch, contains('request.markActionStarted()'));
      expect(noteBranch, contains('!canDeliver()'));
      expect(noteBranch, contains('request.isCurrentAccount'));
      expect(noteBranch, contains('BrandRouteSurface(child: NoteScreen())'));
      expect(
        noteBranch,
        isNot(contains('builder: (_) => const NoteScreen()')),
        reason:
            'Share/deep-link note route must not expose a transparent Navigator background.',
      );
    },
  );
}

class _ProviderRouteCheck {
  final String fileName;
  final String keyPrefix;
  final String fallback;

  const _ProviderRouteCheck({
    required this.fileName,
    required this.keyPrefix,
    required this.fallback,
  });
}
