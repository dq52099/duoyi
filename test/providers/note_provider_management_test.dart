import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'NoteProvider separates active and archived notes and sorts pins first',
    () {
      final provider = NoteProvider();
      final older = NoteItem(
        id: 'older',
        content: '旧笔记',
        createdAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 5, 1),
      );
      final newer = NoteItem(
        id: 'newer',
        content: '新笔记',
        createdAt: DateTime(2026, 5, 2),
        updatedAt: DateTime(2026, 5, 2),
      );

      provider.addOrUpdateNote(older);
      provider.addOrUpdateNote(newer);

      expect(provider.activeNotes.map((note) => note.id), ['newer', 'older']);

      provider.togglePinned('older');
      expect(provider.activeNotes.map((note) => note.id), ['older', 'newer']);
      expect(provider.activeNotes.first.pinned, isTrue);

      provider.setArchived('older', true);
      expect(provider.activeNotes.map((note) => note.id), ['newer']);
      expect(provider.archivedNotes.map((note) => note.id), ['older']);
      expect(provider.archivedNotes.single.pinned, isFalse);

      provider.setArchived('older', false);
      expect(provider.activeNotes.map((note) => note.id), ['older', 'newer']);
      expect(provider.archivedNotes, isEmpty);
    },
  );
}
