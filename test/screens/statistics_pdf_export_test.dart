// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Observe the real locale notifier during export teardown; keep this test-only probe.
bool _localeHasListenersForLifecycleProbe() {
  // ignore: invalid_use_of_protected_member
  return I18n.localeListenable.hasListeners;
}

void main() {
  final share = _Share();
  final originalPaths = PathProviderPlatform.instance;
  final originalShare = SharePlatform.instance;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharePlatform.instance = share;
    share.reset();
  });
  tearDown(() {
    PathProviderPlatform.instance = originalPaths;
    I18n.setLocale(AppLocale.zh);
  });
  tearDownAll(() => SharePlatform.instance = originalShare);

  for (final locale in [AppLocale.en, AppLocale.zh]) {
    testWidgets(
      'archive PDF keeps $locale across a pending export and preserves Latin/CJK data',
      (tester) async {
        I18n.setLocale(locale);
        final evidenceDirectory = Directory(
          'evidence/widget-settings-polish-20261012/report-export',
        ).absolute;
        evidenceDirectory.createSync(recursive: true);
        final directory = evidenceDirectory.createTempSync('pdf-${locale.name}-');
        final paths = _Paths(directory.path);
        PathProviderPlatform.instance = paths;
        final audit = TimeAuditProvider();
        final now = DateTime.now();
        await audit.add(
          TimeEntry(
            title: 'literal / 保留原文',
            startAt: now.subtract(const Duration(minutes: 45)),
            endAt: now,
            category: TimeEntryCategory.work,
          ),
        );
        await _mount(tester, audit);
        await tester.tap(
          find.byTooltip(
            locale == AppLocale.en ? 'Report share image' : '报告分享图',
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text(locale == AppLocale.en ? 'Archive' : '归档版'),
        );
        await tester.tap(find.text(locale == AppLocale.en ? 'Archive' : '归档版'));
        await tester.pump();
        await tester.ensureVisible(
          find.text(locale == AppLocale.en ? 'Save PDF' : '保存 PDF'),
        );
        await tester.pumpAndSettle();
        final selectedTemplate =
            (tester.widget(
                      find.byWidgetPredicate(
                        (widget) =>
                            widget is SegmentedButton &&
                            widget.segments.any(
                              (segment) =>
                                  segment.label is Text &&
                                  (segment.label as Text).data ==
                                      (locale == AppLocale.en
                                          ? 'Archive'
                                          : '归档版'),
                            ),
                      ),
                    )
                    as SegmentedButton)
                .selected
                .single;
        expect(selectedTemplate.toString(), endsWith('.archive'));
        final save = tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '保存 PDF').evaluate().isEmpty
                  ? find.widgetWithText(OutlinedButton, 'Save PDF')
                  : find.widgetWithText(OutlinedButton, '保存 PDF'),
            )
            .onPressed!;
        await tester.runAsync(() async {
          final latin = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
          final cjk = await rootBundle.load(
            'assets/fonts/DroidSansFallbackFull.ttf',
          );
          expect(latin.lengthInBytes, greaterThan(1000));
          expect(cjk.lengthInBytes, greaterThan(1000));
          save();
          save();
          await paths.started.future.timeout(const Duration(seconds: 8));
        });
        I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
        paths.release.complete(directory.path);
        for (var attempt = 0; attempt < 100 && share.calls.isEmpty; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(share.calls, hasLength(1));
        expect(paths.requests, 1);
        final params = share.calls.single;
        expect(params.text, contains('literal / 保留原文'));
        expect(params.text, contains(locale == AppLocale.en ? 'Work' : '工作'));
        expect(
          params.subject,
          locale == AppLocale.en ? 'Duoyi Time Report PDF' : '多仪时光报告 PDF',
        );
        final exported = File(params.files!.single.path);
        expect(exported.lengthSync(), greaterThan(1000));
        final name = locale == AppLocale.en
            ? 'archive-en-to-zh.pdf'
            : 'archive-zh-to-en.pdf';
        exported.copySync('${directory.path}/$name');
        exported.deleteSync();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'PDF notifier lifecycle cancels pending export on owner unmount',
    (tester) async {
      const waitLimit = Duration(seconds: 8);
      final previousPaths = PathProviderPlatform.instance;
      final previousShare = SharePlatform.instance;
      final previousLocale = I18n.current;
      final evidenceDirectory = Directory(
        'evidence/widget-settings-polish-20261012/report-export',
      ).absolute;
      evidenceDirectory.createSync(recursive: true);
      final directory = evidenceDirectory.createTempSync(
        'pdf-notifier-lifecycle-',
      );
      final paths = _Paths(directory.path);
      final audit = TimeAuditProvider();
      final observations = <String, Object?>{
        'case': 'PDF notifier lifecycle cancels pending export on owner unmount',
        'bodyPassed': false,
        'cleanupErrors': <String>[],
      };
      final tracked = <(Future<void>, Future<void>)>[];
      var clipboardWrites = 0;
      var terminalCollected = false;

      Future<void> track(Future<void> future, String name) {
        observations['${name}Settled'] = false;
        final observer = future.then<void>(
          (_) { observations['${name}Settled'] = true; },
          onError: (Object error, StackTrace stack) {
            observations['${name}Settled'] = true;
            observations['${name}Error'] = error.toString();
            observations['${name}Stack'] = stack.toString();
          },
        );
        tracked.add((future, observer));
        return future;
      }

      void checkFramework(String stage) {
        final error = tester.takeException();
        observations['${stage}FrameworkError'] = error?.toString();
        expect(error, isNull, reason: stage);
      }

      void expectNoExportEffects() {
        expect(paths.requests, 1);
        expect(clipboardWrites, 0);
        expect(share.calls, isEmpty);
        expect(directory.listSync(), isEmpty);
        expect(find.byType(StatisticsScreen), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(_localeHasListenersForLifecycleProbe(), isFalse);
      }

      Future<void> collectTerminal() async {
        if (terminalCollected) return;
        terminalCollected = true;
        Object? cleanupFailure;
        StackTrace? cleanupStack;

        Future<void> attempt(Future<void> Function() action) async {
          try {
            await action();
          } catch (error, stack) {
            cleanupFailure ??= error;
            cleanupStack ??= stack;
            (observations['cleanupErrors']! as List<String>).add(
              error.toString(),
            );
          }
        }

        try {
          // Cancel through actual owner removal before releasing any held path.
          await attempt(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          });
          if (!paths.release.isCompleted) {
            paths.release.complete(directory.path);
          }
          await attempt(() async {
            await tester.runAsync(() async {
              for (final pair in tracked) {
                await pair.$2.timeout(waitLimit);
                await pair.$1.timeout(waitLimit);
              }
            });
          });
          await attempt(() async {
            await tester.pump();
            checkFramework('terminal');
          });
        } finally {
          // All handlers are case-owned; _mount also retains its original resets.
          PathProviderPlatform.instance = previousPaths;
          SharePlatform.instance = previousShare;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
          I18n.setLocale(previousLocale);
          observations['finishedAt'] = DateTime.now().toUtc().toIso8601String();
          observations['pathRequests'] = paths.requests;
          observations['pathReleased'] = paths.release.isCompleted;
          observations['clipboardWrites'] = clipboardWrites;
          observations['shareCalls'] = share.calls.length;
          observations['auditDisposedAtTerminal'] = audit.isDisposed;
          observations['localeHasListenersAtTerminal'] =
              _localeHasListenersForLifecycleProbe();
          observations['trackedExportFutures'] = tracked.length;
          observations['terminalJoinSucceeded'] = cleanupFailure == null;
          observations['filesBeforeDiagnostics'] =
              directory.listSync().map((file) => file.path).toList();
          File('${directory.path}/lifecycle-diagnostics.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(observations),
            flush: true,
          );
        }
        if (cleanupFailure != null) {
          Error.throwWithStackTrace(cleanupFailure!, cleanupStack!);
        }
      }

      // Failure/timeout teardown retains diagnostics and never manually disposes.
      addTearDown(collectTerminal);
      try {
        var assertionsEnabled = false;
        assert(() {
          assertionsEnabled = true;
          return true;
        }());
        expect(assertionsEnabled, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        observations['localeListenerBaseline'] =
            _localeHasListenersForLifecycleProbe();
        expect(observations['localeListenerBaseline'], isFalse);
        I18n.setLocale(AppLocale.en);
        PathProviderPlatform.instance = paths;
        await _mount(tester, audit);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') clipboardWrites++;
            return null;
          },
        );
        await tester.tap(find.byTooltip('Report share image'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        await tester.ensureVisible(find.text('Archive'));
        await tester.tap(find.text('Archive'));
        await tester.pump();
        await tester.ensureVisible(find.text('Save PDF'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        final screenContext = tester.element(find.byType(StatisticsScreen));
        final theme = Provider.of<ThemeProvider>(screenContext, listen: false);
        expect(
          Provider.of<TimeAuditProvider>(screenContext, listen: false),
          same(audit),
        );
        observations['themeAliveBeforeUnmount'] =
            ChangeNotifier.debugAssertNotDisposed(theme);
        observations['auditDisposedBeforeUnmount'] = audit.isDisposed;
        expect(observations['themeAliveBeforeUnmount'], isTrue);
        expect(audit.isDisposed, isFalse);
        expect(_localeHasListenersForLifecycleProbe(), isTrue);
        final template = tester.widget<SegmentedButton>(
          find.byWidgetPredicate(
            (widget) => widget is SegmentedButton &&
                widget.segments.any(
                  (segment) => segment.label is Text &&
                      (segment.label as Text).data == 'Archive',
                ),
          ),
        ).selected.single;
        expect(template.toString(), endsWith('.archive'));
        final callback = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Save PDF'),
        ).onPressed!;
        expect(callback, isA<Future<void> Function()>());
        final save = callback as Future<void> Function();
        late Future<void> pending;
        await tester.runAsync(() async {
          pending = track(save(), 'pending');
          await paths.started.future.timeout(waitLimit);
        });
        expect(paths.requests, 1);
        expect(paths.release.isCompleted, isFalse);
        expect(observations['pendingSettled'], isFalse);
        expect(clipboardWrites, 0);
        expect(share.calls, isEmpty);
        expect(directory.listSync(), isEmpty);
        checkFramework('heldPath');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        observations['auditDisposedAfterUnmount'] = audit.isDisposed;
        expect(audit.isDisposed, isTrue);
        var themeDisposed = false;
        try {
          ChangeNotifier.debugAssertNotDisposed(theme);
        } on FlutterError catch (error) {
          expect(error.toString(), contains('was used after being disposed'));
          themeDisposed = true;
        }
        observations['themeDisposedAfterUnmount'] = themeDisposed;
        expect(themeDisposed, isTrue);
        expect(_localeHasListenersForLifecycleProbe(), isFalse);
        expect(paths.release.isCompleted, isFalse);
        expect(observations['pendingSettled'], isFalse);
        checkFramework('unmounted');

        I18n.setLocale(AppLocale.zh);
        await tester.runAsync(() async {
          paths.release.complete(directory.path);
          await pending.timeout(waitLimit);
          await tracked.single.$2.timeout(waitLimit);
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(observations['pendingSettled'], isTrue);
        expect(observations['pendingError'], isNull);
        expectNoExportEffects();
        checkFramework('releasedAfterUnmount');

        await tester.runAsync(() async {
          await track(save(), 'retained').timeout(waitLimit);
          await tracked.last.$2.timeout(waitLimit);
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(observations['retainedSettled'], isTrue);
        expect(observations['retainedError'], isNull);
        expectNoExportEffects();
        checkFramework('retainedAfterUnmount');
        observations['bodyPassed'] = true;
      } catch (error, stack) {
        observations['bodyError'] = error.toString();
        observations['bodyStack'] = stack.toString();
        rethrow;
      } finally {
        await collectTerminal();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

}

Future<void> _mount(WidgetTester tester, TimeAuditProvider audit) async {
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (message) async {
      final key = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      final file = File(key);
      if (file.existsSync()) {
        return ByteData.sublistView(file.readAsBytesSync());
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    ),
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TodoProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => PomodoroProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => audit),
        ChangeNotifierProvider(create: (_) => AiService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(home: StatisticsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  final started = Completer<void>.sync();
  final release = Completer<String>.sync();
  int requests = 0;
  @override
  Future<String?> getTemporaryPath() {
    requests++;
    if (!started.isCompleted) started.complete();
    return release.future;
  }
}

class _Share extends SharePlatform {
  final calls = <ShareParams>[];
  Completer<void> called = Completer<void>.sync();
  void reset() {
    calls.clear();
    called = Completer<void>.sync();
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    if (!called.isCompleted) called.complete();
    return const ShareResult('mocked', ShareResultStatus.success);
  }
}
