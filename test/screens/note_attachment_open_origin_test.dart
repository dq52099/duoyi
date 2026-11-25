import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/note_editor_ui_copy.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Editor preserves content URI and converts only bare file paths',
    (tester) async {
      final fixture = await _mount(tester);
      for (final name in ['content', 'file', 'web']) {
        await tester.tap(find.widgetWithText(InputChip, name));
        await tester.pump();
      }
      expect(fixture.launcher.urls, [
        'content://com.example.documents/document/42',
        'file:///storage/emulated/0/guide.pdf',
        'https://example.test/guide',
      ]);
      expect(
        tester
            .widget<InputChip>(find.widgetWithText(InputChip, 'unsupported'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final boundary in ['lock', 'reset', 'cover']) {
    testWidgets('Retained attachment open is blocked after $boundary', (
      tester,
    ) async {
      final fixture = await _mount(tester);
      final retained = tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'content'))
          .onPressed!;
      switch (boundary) {
        case 'lock':
          fixture.lock.change(true);
          fixture.lock.change(false);
        case 'reset':
          fixture.provider.resetLocalState();
        case 'cover':
          fixture.navigator.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          );
          fixture.navigator.currentState!.pop();
      }
      retained();
      await tester.pumpAndSettle();
      expect(fixture.launcher.urls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Opening failure reports safe feedback in current locale', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    fixture.launcher.held = Completer<bool>();
    await tester.tap(find.widgetWithText(InputChip, 'content'));
    await tester.pump();
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    fixture.launcher.held!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text(NoteEditorUiCopy.openFailed), findsOneWidget);
    expect(fixture.launcher.urls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Late opening failure is silent after authority changes', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    fixture.launcher.held = Completer<bool>();
    await tester.tap(find.widgetWithText(InputChip, 'content'));
    await tester.pump();
    fixture.lock.change(true);
    fixture.lock.change(false);
    fixture.launcher.held!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text(NoteEditorUiCopy.openFailed), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];
  Completer<bool>? held;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) {
    urls.add(url);
    return held?.future ?? Future.value(true);
  }
}

class _Lock extends AppLockProvider {
  bool locked = false;

  @override
  bool get isLocked => locked;

  void change(bool value) {
    locked = value;
    notifyListeners();
  }
}

class _Fixture {
  final provider = NoteProvider();
  final lock = _Lock();
  final gate = AppAccessRouteGate();
  final navigator = GlobalKey<NavigatorState>();
  final launcher = _Launcher();
}

Future<_Fixture> _mount(WidgetTester tester) async {
  final fixture = _Fixture();
  final previous = UrlLauncherPlatform.instance;
  UrlLauncherPlatform.instance = fixture.launcher;
  addTearDown(() async {
    if (fixture.launcher.held case final pending? when !pending.isCompleted) {
      pending.complete(false);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.provider.dispose();
    fixture.lock.dispose();
    fixture.gate.dispose();
    UrlLauncherPlatform.instance = previous;
  });
  final now = DateTime(2026, 10, 15);
  final note = NoteItem(
    id: 'attachment-note',
    content: 'Attachment draft',
    createdAt: now,
    updatedAt: now,
    attachments: [
      for (final entry in {
        'content': 'content://com.example.documents/document/42',
        'file': '/storage/emulated/0/guide.pdf',
        'web': 'https://example.test/guide',
        'unsupported': 'javascript:alert(1)',
      }.entries)
        NoteAttachment(name: entry.key, uri: entry.value),
    ],
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteProvider>.value(value: fixture.provider),
        ChangeNotifierProvider<AppLockProvider>.value(value: fixture.lock),
      ],
      child: MaterialApp(
        navigatorKey: fixture.navigator,
        navigatorObservers: [fixture.gate],
        home: NoteEditScreen(note: note),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}
