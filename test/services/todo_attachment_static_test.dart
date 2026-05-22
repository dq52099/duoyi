import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('TodoItem persists attachments through JSON and copyWith', () {
    final model = File('lib/models/todo.dart').readAsStringSync();
    final provider = File(
      'lib/providers/todo_provider.dart',
    ).readAsStringSync();

    expect(model, contains("import 'note.dart' show NoteAttachment;"));
    expect(model, contains('List<NoteAttachment> attachments;'));
    expect(model, contains('List<NoteAttachment>? attachments'));
    expect(
      model,
      contains("'attachments': attachments.map((a) => a.toJson()).toList()"),
    );
    expect(model, contains("json['attachments'] as List<dynamic>?"));
    expect(model, contains('NoteAttachment.fromJson'));
    expect(model, contains('attachments: attachments ?? this.attachments'));
    expect(provider, contains('attachments: [...prev.attachments]'));
  });

  test('TodoDetailScreen exposes file and link attachments for tasks', () {
    final screen = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(
      screen,
      contains("import '../services/note_attachment_picker.dart';"),
    );
    expect(screen, contains('Future<void> _addAttachment()'));
    expect(screen, contains('NoteAttachmentPicker.pickFile()'));
    expect(screen, contains('Future<void> _showManualAttachmentDialog()'));
    expect(screen, contains('_TodoAttachmentPanel'));
    expect(screen, contains('_TodoAttachmentChip'));
    expect(screen, contains('_TodoAttachmentImagePreview'));
    expect(screen, contains('Icons.upload_file_outlined'));
    expect(screen, contains('Icons.add_link'));
    expect(screen, contains('Image.network'));
    expect(screen, contains('Image.file'));
    expect(screen, contains('LaunchMode.externalApplication'));
  });

  test('task module export includes todo attachment links', () {
    final exporter = File('lib/services/ics_exporter.dart').readAsStringSync();

    expect(
      exporter,
      contains('title,completed,priority,quadrant,list,due,tags,attachments'),
    );
    expect(exporter, contains('t.attachments.map((a) => a.uri).join'));
    expect(
      exporter,
      contains(
        "sb.writeln('  - 附件: [\${attachment.name}](\${attachment.uri})');",
      ),
    );
  });
}
