import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Open quick note changes locale without losing draft or selection',
    (tester) async {
      await _mount(tester);
      await _openNote(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      const draft = '项目原文 literal note';
      await tester.enterText(find.byType(TextField), draft);
      field.controller!.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      final element = tester.element(find.byType(TextField));
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Quick note'), findsOneWidget);
      expect(find.text('Write something...'), findsOneWidget);
      expect(tester.element(find.byType(TextField)), same(element));
      expect(field.controller!.text, draft);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
    },
  );

  testWidgets(
    'Retained quick note save cannot write after account invalidation',
    (tester) async {
      final notes = await _mount(tester);
      await _openNote(tester);
      await tester.enterText(
        find.byType(TextField),
        'old account private draft',
      );
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed!;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      notes.resetLocalState();
      save();
      await tester.pumpAndSettle();
      expect(notes.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_Notes> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final notes = _Notes();
  final ai = AiService();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: const MaterialApp(
        home: Scaffold(floatingActionButton: QuickCaptureFab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    notes.dispose();
    ai.dispose();
  });
  return notes;
}

Future<void> _openNote(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton).last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.edit_note));
  await tester.pumpAndSettle();
  expect(find.text('随手记'), findsOneWidget);
}

class _Notes extends NoteProvider {
  final writes = <NoteItem>[];
  @override
  void addOrUpdateNote(NoteItem note) => writes.add(note);
  @override
  Future<void> addOrUpdateNotePersisted(
    NoteItem note, {
    bool Function()? canWrite,
  }) async {
    if (canWrite?.call() == false) {
      throw const AccountPreferenceWriteCanceled();
    }
    writes.add(note);
  }
}
