import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/global_search.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/screens/search_screen.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/services/note_attachment_picker.dart';
import 'package:duoyi/services/web_file_download.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeededTodoProvider extends TodoProvider {
  _SeededTodoProvider(this.seeded);
  final List<TodoItem> seeded;

  @override
  List<TodoItem> get todos => seeded;
}

class _SeededHabitProvider extends HabitProvider {
  _SeededHabitProvider(this.seeded);
  final List<Habit> seeded;

  @override
  List<Habit> get habits => seeded;
}

class _SeededPomodoroProvider extends PomodoroProvider {
  _SeededPomodoroProvider(this.seeded);
  final List<PomodoroSession> seeded;

  @override
  List<PomodoroSession> get sessions => seeded;
}

/// Preserves explicit browser filenames on Dart VM tests, where `cross_file`'s
/// `dart:io` `XFile` constructor ignores the `name` parameter.
class _WebLikeXFile extends XFile {
  _WebLikeXFile(super.path, {required String name}) : _explicitName = name;

  final String _explicitName;

  @override
  String get name => _explicitName;
}

const _samplePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6f0AAAAASUVORK5CYII=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    WebFileDownload.debugSaveHandler = null;
    I18n.setLocale(AppLocale.zh);
  });

  group('WebFileDownload & Web Attachment Picker', () {
    test('sanitizes filenames and infers MIME types', () {
      expect(
        WebFileDownload.sanitizeFileName('a/b:c*d?"e<f>g|h.md'),
        'a_b_c_d__e_f_g_h.md',
      );
      expect(
        WebFileDownload.inferMimeType('backup.json'),
        'application/json;charset=utf-8',
      );
      expect(
        WebFileDownload.inferMimeType('export.csv'),
        'text/csv;charset=utf-8',
      );
      expect(
        WebFileDownload.inferMimeType('note.md'),
        'text/markdown;charset=utf-8',
      );
      expect(
        WebFileDownload.inferMimeType('cal.ics'),
        'text/calendar;charset=utf-8',
      );
      expect(WebFileDownload.inferMimeType('chart.png'), 'image/png');
      expect(WebFileDownload.inferMimeType('report.pdf'), 'application/pdf');
    });

    test('saveText encodes UTF-8 and honors canProceed cancellation', () async {
      WebFileDownloadRequest? captured;
      WebFileDownload.debugSaveHandler = (request) async {
        captured = request;
        return WebFileDownloadResult(saved: true, fileName: request.fileName);
      };

      final saved = await WebFileDownload.saveText(
        content: '标题\n- [ ] 待办事项',
        fileName: '工作/日报.md',
        shareSubject: '日报',
      );
      expect(saved.saved, isTrue);
      expect(saved.fileName, '工作_日报.md');
      expect(captured, isNotNull);
      expect(captured!.mimeType, 'text/markdown;charset=utf-8');
      expect(utf8.decode(captured!.bytes), '标题\n- [ ] 待办事项');

      captured = null;
      final aborted = await WebFileDownload.saveText(
        content: 'ignored',
        fileName: 'aborted.json',
        canProceed: () => false,
      );
      expect(aborted.saved, isFalse);
      expect(captured, isNull);
    });

    test('NoteAttachmentPicker.fromWebXFile inlines web images and preserves blob non-images', () async {
      final pngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final imageFile = XFile.fromData(
        pngBytes,
        path: 'screenshot.png',
        mimeType: 'image/png',
      );
      final imageAttachment = await NoteAttachmentPicker.fromWebXFile(imageFile);
      expect(imageAttachment, isNotNull);
      expect(imageAttachment!.name, 'screenshot.png');
      expect(imageAttachment.mimeType, 'image/png');
      expect(
        imageAttachment.uri,
        'data:image/png;base64,${base64Encode(pngBytes)}',
      );
      expect(imageAttachment.isImage, isTrue);

      final pdfAttachment = await NoteAttachmentPicker.fromWebXFile(
        _WebLikeXFile('blob:https://duoyi.app/doc-123', name: 'syllabus.pdf'),
      );
      expect(pdfAttachment, isNotNull);
      expect(pdfAttachment!.name, 'syllabus.pdf');
      expect(pdfAttachment.uri, 'blob:https://duoyi.app/doc-123');
      expect(pdfAttachment.mimeType, 'application/pdf');
      expect(pdfAttachment.isImage, isFalse);

      final empty = await NoteAttachmentPicker.fromWebXFile(
        _WebLikeXFile('', name: 'empty.bin'),
      );
      expect(empty, isNull);
    });
  });

  group('NoteItem tags, folder & interactive checklists', () {
    test('NoteItem backward-compatible JSON and markdown export round-trip', () {
      final legacy = NoteItem.fromJson({
        'id': 'legacy-1',
        'content': '旧格式随手记\n无标签字段',
        'createdAt': '2026-06-01T08:00:00.000',
        'updatedAt': '2026-06-01T09:00:00.000',
      });
      expect(legacy.tags, isEmpty);
      expect(legacy.folder, isNull);

      final tagged = NoteItem(
        id: 'n-tagged',
        content: '# 研发周报\n- [ ] 完成测试',
        tags: const ['研发', ' 周报 ', '研发'],
        folder: ' 工作笔记本 ',
        attachments: const [
          NoteAttachment(
            name: 'design.png',
            uri: 'data:image/png;base64,$_samplePngBase64',
          ),
        ],
        createdAt: DateTime(2026, 6, 1, 8),
        updatedAt: DateTime(2026, 6, 1, 9),
      );
      expect(tagged.tags, ['研发', '周报']);
      expect(tagged.folder, '工作笔记本');
      expect(tagged.attachments.single.isImage, isTrue);

      final roundTripped = NoteItem.fromJson(tagged.toJson());
      expect(roundTripped.tags, ['研发', '周报']);
      expect(roundTripped.folder, '工作笔记本');

      final cleared = roundTripped.copyWith(clearFolder: true);
      expect(cleared.folder, isNull);
      expect(cleared.tags, ['研发', '周报']);

      final mdDoc = tagged.toMarkdownDocument(AppLocale.zh);
      expect(mdDoc, contains('# 研发周报'));
      expect(mdDoc, contains('Folder: 工作笔记本'));
      expect(mdDoc, contains('Tags: #研发 #周报'));
      expect(mdDoc, contains('[design.png]'));
    });

    test('NoteBlock.toggleChecklistLine flips unchecked and checked boxes', () {
      const source = '# 清单\n- [ ] 第一项\n  - [X] 第二项';
      final toggledFirst = NoteBlock.toggleChecklistLine(source, 1);
      expect(toggledFirst, '# 清单\n- [x] 第一项\n  - [X] 第二项');

      final toggledSecond = NoteBlock.toggleChecklistLine(toggledFirst, 2);
      expect(toggledSecond, '# 清单\n- [x] 第一项\n  - [ ] 第二项');

      final ignoredHeading = NoteBlock.toggleChecklistLine(toggledSecond, 0);
      expect(ignoredHeading, toggledSecond);
    });
  });

  group('GlobalSearch expansion', () {
    test('matches todo tags, habit tags, note tags/folder/attachments, and pomodoro sessions', () {
      final hits = GlobalSearch.run(
        query: 'alpha',
        todos: [
          TodoItem(id: 't1', title: '普通任务', tags: ['AlphaOps']),
        ],
        habits: [
          Habit(id: 'h1', name: '晨跑', tags: ['alpha-fitness']),
        ],
        notes: [
          NoteItem(
            id: 'n1',
            content: '日常记录',
            tags: ['tagA'],
            folder: 'AlphaFolder',
            createdAt: DateTime(2026, 6, 1),
            updatedAt: DateTime(2026, 6, 1),
          ),
          NoteItem(
            id: 'n2',
            content: '会议材料',
            attachments: const [
              NoteAttachment(
                name: 'alpha_spec.pdf',
                uri: 'https://example.test/alpha.pdf',
              ),
            ],
            createdAt: DateTime(2026, 6, 1),
            updatedAt: DateTime(2026, 6, 2),
          ),
        ],
        diaries: const [],
        anniversaries: const [],
        countdowns: const [],
        goals: const [],
        courses: const [],
        pomodoroSessions: [
          PomodoroSession(
            id: 'p1',
            startTime: DateTime(2026, 6, 2, 10),
            endTime: DateTime(2026, 6, 2, 10, 25),
            durationSeconds: 1500,
            type: PomodoroType.focus,
            taskName: 'Deep Work Alpha',
            tag: 'coding',
          ),
          PomodoroSession(
            id: 'p2',
            startTime: DateTime(2026, 6, 2, 11),
            endTime: DateTime(2026, 6, 2, 11, 25),
            durationSeconds: 1500,
            type: PomodoroType.focus,
            tag: 'alpha-study',
          ),
        ],
      );

      expect(
        hits.where((h) => h.kind == SearchKind.todo).map((h) => h.sourceId),
        ['t1'],
      );
      expect(
        hits.where((h) => h.kind == SearchKind.habit).map((h) => h.sourceId),
        ['h1'],
      );
      expect(
        hits.where((h) => h.kind == SearchKind.note).map((h) => h.sourceId),
        containsAll(['n1', 'n2']),
      );
      expect(
        hits.where((h) => h.kind == SearchKind.pomodoro).map((h) => h.sourceId),
        ['p1', 'p2'],
      );
    });
  });

  group('Widget upgrades', () {
    testWidgets('NoteEditScreen toggles preview checkboxes, edits folder/tags, and exports .md', (
      tester,
    ) async {
      final noteProvider = NoteProvider();
      addTearDown(noteProvider.dispose);

      WebFileDownloadRequest? savedRequest;
      WebFileDownload.debugSaveHandler = (request) async {
        savedRequest = request;
        return WebFileDownloadResult(saved: true, fileName: request.fileName);
      };

      final draft = NoteItem(
        id: 'edit-1',
        content: '清单标题\n- [ ] 待完成事项',
        tags: const ['初始'],
        folder: '默认',
        createdAt: DateTime(2026, 6, 1, 9),
        updatedAt: DateTime(2026, 6, 1, 9),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<NoteProvider>.value(value: noteProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: const ValueKey('open_note_editor'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BrandRouteSurface(child: NoteEditScreen(note: draft)),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open_note_editor')));
      await tester.pumpAndSettle();

      // Switch to preview and toggle checkbox directly in preview.
      await tester.tap(find.byTooltip(I18n.tr('note.preview')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      await tester.tap(find.byIcon(Icons.check_box_outline_blank));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box), findsOneWidget);

      // Export current draft to .md via WebFileDownload.
      await tester.tap(find.byKey(const ValueKey('note-editor-export-md')));
      await tester.pumpAndSettle();
      expect(savedRequest, isNotNull);
      expect(savedRequest!.fileName, '清单标题.md');
      expect(utf8.decode(savedRequest!.bytes), contains('- [x] 待完成事项'));

      // Update folder via dialog chip while keeping a single inline TextField.
      await tester.tap(find.byKey(const ValueKey('note-editor-folder-chip')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '项目文档',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(find.text('项目文档'), findsOneWidget);

      // Save note and verify updated checklist, folder & tags persisted.
      await tester.tap(find.byKey(const ValueKey('note-editor-save')));
      await tester.pumpAndSettle();
      expect(noteProvider.notes, hasLength(1));
      expect(noteProvider.notes.single.content, contains('- [x] 待完成事项'));
      expect(noteProvider.notes.single.folder, '项目文档');
      expect(noteProvider.notes.single.tags, ['初始']);
    });

    testWidgets('NoteScreen supports folder/tag chips, sorting, archived highlight, and .md export', (
      tester,
    ) async {
      final noteProvider = NoteProvider();
      addTearDown(noteProvider.dispose);
      await tester.runAsync(() async {
        await noteProvider.addOrUpdateNotePersisted(
          NoteItem(
            id: 'n-b',
            content: 'Beta Note\nBody B',
            folder: 'Work',
            tags: const ['urgent'],
            createdAt: DateTime(2026, 6, 1, 8),
            updatedAt: DateTime(2026, 6, 2, 8),
          ),
        );
        await noteProvider.addOrUpdateNotePersisted(
          NoteItem(
            id: 'n-a',
            content: 'Alpha Note\nBody A',
            folder: 'Life',
            tags: const ['idea'],
            createdAt: DateTime(2026, 6, 1, 9),
            updatedAt: DateTime(2026, 6, 1, 10),
          ),
        );
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<NoteProvider>.value(value: noteProvider),
          ],
          child: const MaterialApp(
            home: BrandRouteSurface(child: NoteScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default is updatedDesc: Beta above Alpha.
      expect(
        tester.getTopLeft(find.text('Beta Note')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha Note')).dy),
      );

      // Filter by folder chip Work.
      await tester.tap(find.byKey(const ValueKey('note_folder_filter_Work')));
      await tester.pumpAndSettle();
      expect(find.text('Beta Note'), findsOneWidget);
      expect(find.text('Alpha Note'), findsNothing);

      // Clear filters and sort by title ascending.
      await tester.tap(find.byKey(const ValueKey('note_filter_clear')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Note'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标题排序'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Alpha Note')).dy,
        lessThan(tester.getTopLeft(find.text('Beta Note')).dy),
      );
    });

    testWidgets('SearchScreen filters by kind, persists recent queries, and navigates with sourceId', (
      tester,
    ) async {
      I18n.setLocale(AppLocale.en);
      final todos = _SeededTodoProvider([
        TodoItem(id: 'todo-x', title: 'Alpha release check', tags: ['release']),
      ]);
      final habits = _SeededHabitProvider([
        Habit(id: 'habit-x', name: 'Alpha reading', tags: ['daily']),
      ]);
      final pomodoros = _SeededPomodoroProvider([
        PomodoroSession(
          id: 'pomo-x',
          startTime: DateTime(2026, 6, 3, 10),
          endTime: DateTime(2026, 6, 3, 10, 25),
          durationSeconds: 1500,
          type: PomodoroType.focus,
          taskName: 'Alpha deep focus',
          tag: 'focus',
        ),
      ]);
      addTearDown(() {
        todos.dispose();
        habits.dispose();
        pomodoros.dispose();
      });

      Widget buildSearchHost() => MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<TodoProvider>.value(value: todos),
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<NoteProvider>(create: (_) => NoteProvider()),
          ChangeNotifierProvider<DiaryProvider>(create: (_) => DiaryProvider()),
          ChangeNotifierProvider<AnniversaryProvider>(
            create: (_) => AnniversaryProvider(),
          ),
          ChangeNotifierProvider<CountdownProvider>(
            create: (_) => CountdownProvider(),
          ),
          ChangeNotifierProvider<GoalProvider>(create: (_) => GoalProvider()),
          ChangeNotifierProvider<CourseProvider>(create: (_) => CourseProvider()),
          ChangeNotifierProvider<CalendarProvider>(
            create: (_) => CalendarProvider(),
          ),
          ChangeNotifierProvider<TimeAuditProvider>(
            create: (_) => TimeAuditProvider(),
          ),
          ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoros),
        ],
        child: const MaterialApp(home: BrandRouteSurface(child: SearchScreen())),
      );

      await tester.pumpWidget(buildSearchHost());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('search_filter_all')), findsOneWidget);
      expect(find.byKey(const ValueKey('search_filter_habit')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search_filter_pomodoro')),
        findsOneWidget,
      );

      // Narrow to Habit only.
      await tester.tap(find.byKey(const ValueKey('search_filter_habit')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha reading', findRichText: true), findsOneWidget);
      expect(find.text('Alpha deep focus', findRichText: true), findsNothing);

      // Tap filtered habit result -> routes to HabitDetailScreen(habitId: habit-x).
      await tester.tap(find.text('Alpha reading', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Clear search -> empty hint + persisted recent history remain visible.
      await tester.tap(find.byTooltip(I18n.tr('search.clear')).first);
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('search.empty')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search_recent_history_card')),
        findsOneWidget,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(SearchScreen.recentHistoryPrefsKey),
        contains('Alpha'),
      );

      await tester.tap(find.byKey(const ValueKey('search_clear_history')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('search_recent_history_card')),
        findsNothing,
      );
    });

    testWidgets('BackupScreen downloads JSON and CSV files via WebFileDownload', (
      tester,
    ) async {
      final saved = <WebFileDownloadRequest>[];
      WebFileDownload.debugSaveHandler = (request) async {
        saved.add(request);
        return WebFileDownloadResult(saved: true, fileName: request.fileName);
      };
      final todos = _SeededTodoProvider([
        TodoItem(id: 'bk-1', title: 'Backup Task Sample'),
      ]);
      addTearDown(todos.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<TodoProvider>.value(value: todos),
          ],
          child: const MaterialApp(
            home: BrandRouteSurface(child: BackupScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final downloadJson = find.byKey(const ValueKey('backup_download_json'));
      await tester.ensureVisible(downloadJson);
      await tester.tap(downloadJson);
      await tester.pumpAndSettle();
      expect(saved.last.fileName.endsWith('.json'), isTrue);
      expect(saved.last.mimeType, 'application/json;charset=utf-8');

      final backupScroll = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first;

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final todoCsvChip = find.widgetWithText(
        ActionChip,
        DataSettingsUiCopy.exportChipTodoCsv,
      );
      await tester.scrollUntilVisible(
        todoCsvChip,
        300,
        maxScrolls: 30,
        scrollable: backupScroll,
      );
      await tester.ensureVisible(todoCsvChip);
      await tester.pumpAndSettle();
      await tester.tap(todoCsvChip);
      await tester.pumpAndSettle();

      final downloadExported = find.byKey(
        const ValueKey('backup_download_exported'),
      );
      await tester.scrollUntilVisible(
        downloadExported,
        300,
        maxScrolls: 30,
        scrollable: backupScroll,
      );
      await tester.ensureVisible(downloadExported);
      await tester.pumpAndSettle();
      await tester.tap(downloadExported);
      await tester.pumpAndSettle();
      expect(saved.last.fileName.endsWith('.csv'), isTrue);
      expect(saved.last.mimeType, 'text/csv;charset=utf-8');
      expect(utf8.decode(saved.last.bytes), contains('Backup Task Sample'));
    });

    testWidgets('TodoDetailScreen renders local desktop path fallback & data image cleanly', (
      tester,
    ) async {
      final todos = _SeededTodoProvider([
        TodoItem(
          id: 'todo-att-1',
          title: 'Attachment Render Safety',
          attachments: const [
            NoteAttachment(
              name: 'desktop.png',
              uri: '/Users/demo/Pictures/desktop.png',
              mimeType: 'image/png',
            ),
            NoteAttachment(
              name: 'inline.png',
              uri: 'data:image/png;base64,$_samplePngBase64',
              mimeType: 'image/png',
            ),
          ],
        ),
      ]);
      addTearDown(todos.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<TodoProvider>.value(value: todos),
          ],
          child: const MaterialApp(
            home: BrandRouteSurface(
              child: TodoDetailScreen(todoId: 'todo-att-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('desktop.png'), findsOneWidget);
      expect(find.text('inline.png'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Web I/O guards & static constraints', () {
    test('Web guards cover PNG/PDF/poster/image preview without breaking native fallbacks', () {
      final stats = File('lib/screens/statistics_screen.dart').readAsStringSync();
      final ach = File('lib/screens/achievements_screen.dart').readAsStringSync();
      final notes = File('lib/screens/note_screen.dart').readAsStringSync();
      final todoDetail = File('lib/screens/todo_detail_screen.dart').readAsStringSync();
      final picker = File('lib/services/note_attachment_picker.dart').readAsStringSync();
      final exportScreen = File('lib/screens/export_screen.dart').readAsStringSync();

      expect(stats, contains('if (kIsWeb)'));
      expect(stats, contains('WebFileDownload.saveBytes'));
      expect(ach, contains('if (kIsWeb)'));
      expect(ach, contains('WebFileDownload.saveBytes'));
      expect(notes, contains('if (!kIsWeb && uri != null && uri.scheme == \'file\')'));
      expect(notes, contains('else if (!kIsWeb && attachment.uri.startsWith(\'/\'))'));
      expect(todoDetail, contains('if (!kIsWeb && uri != null && uri.scheme == \'file\')'));
      expect(todoDetail, contains('else if (!kIsWeb && attachment.uri.startsWith(\'/\'))'));
      expect(picker, contains('if (kIsWeb) return _pickWebFile();'));
      expect(exportScreen, contains('WebFileDownload.saveText'));
      expect(exportScreen, contains("ValueKey('export_download')"));
    });
  });
}
