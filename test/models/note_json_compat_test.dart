import 'package:duoyi/models/note.dart';
import 'package:test/test.dart';

void main() {
  test('NoteItem keeps legacy plain text notes readable', () {
    final note = NoteItem.fromJson({
      'id': 'n1',
      'content': '标题\n正文',
      'createdAt': '2026-05-18T10:00:00.000',
      'updatedAt': '2026-05-18T10:10:00.000',
    });

    expect(note.format, 'markdown');
    expect(note.attachments, isEmpty);
    expect(note.pinned, isFalse);
    expect(note.archived, isFalse);
    expect(note.title, '标题');
    expect(note.blocks, hasLength(2));
    expect(note.blocks.first.type, NoteBlockType.paragraph);
    expect(note.blocks.first.text, '标题');
  });

  test('NoteItem serializes markdown attachments and blocks', () {
    final note = NoteItem(
      id: 'n2',
      content: '# 会议\n- [ ] 整理材料',
      attachments: const [
        NoteAttachment(
          name: '会议资料',
          uri: 'https://example.com/doc',
          mimeType: 'application/pdf',
        ),
      ],
      pinned: true,
      archived: true,
      createdAt: DateTime(2026, 5, 18, 10),
      updatedAt: DateTime(2026, 5, 18, 11),
    );

    final restored = NoteItem.fromJson(note.toJson());
    expect(restored.format, 'markdown');
    expect(restored.blocks, hasLength(2));
    expect(restored.blocks.first.type, NoteBlockType.heading);
    expect(restored.blocks.first.level, 1);
    expect(restored.blocks.first.text, '会议');
    expect(restored.blocks.last.type, NoteBlockType.checklist);
    expect(restored.blocks.last.checked, isFalse);
    expect(restored.blocks.last.text, '整理材料');
    expect(restored.attachments.single.name, '会议资料');
    expect(restored.attachments.single.uri, 'https://example.com/doc');
    expect(restored.attachments.single.mimeType, 'application/pdf');
    expect(restored.pinned, isTrue);
    expect(restored.archived, isTrue);
  });

  test('NoteItem copyWith preserves management flags by default', () {
    final note = NoteItem(
      id: 'n4',
      content: '置顶归档',
      pinned: true,
      archived: true,
      createdAt: DateTime(2026, 5, 18, 10),
      updatedAt: DateTime(2026, 5, 18, 11),
    );

    final edited = note.copyWith(content: '更新内容');
    expect(edited.content, '更新内容');
    expect(edited.pinned, isTrue);
    expect(edited.archived, isTrue);
  });

  test('NoteBlock preserves explicit block json and markdown projection', () {
    final restored = NoteItem.fromJson({
      'id': 'n3',
      'content': '旧内容',
      'format': 'markdown-blocks',
      'blocks': [
        {'id': 'a', 'type': 'heading', 'text': '标题', 'level': 2},
        {'id': 'b', 'type': 'quote', 'text': '引用'},
        {'id': 'c', 'type': 'bullet', 'text': '项目'},
        {'id': 'd', 'type': 'checklist', 'text': '完成', 'checked': true},
        {'id': 'e', 'type': 'code', 'text': 'print(1)'},
        {'id': 'f', 'type': 'divider'},
      ],
      'createdAt': '2026-05-18T10:00:00.000',
      'updatedAt': '2026-05-18T10:10:00.000',
    });

    expect(restored.format, 'markdown-blocks');
    expect(restored.blocks.map((block) => block.type), [
      NoteBlockType.heading,
      NoteBlockType.quote,
      NoteBlockType.bullet,
      NoteBlockType.checklist,
      NoteBlockType.code,
      NoteBlockType.divider,
    ]);
    expect(restored.blocks[0].toMarkdownLine(), '## 标题');
    expect(restored.blocks[1].toMarkdownLine(), '> 引用');
    expect(restored.blocks[2].toMarkdownLine(), '- 项目');
    expect(restored.blocks[3].toMarkdownLine(), '- [x] 完成');
    expect(restored.blocks[4].toMarkdownLine(), '`print(1)`');
    expect(restored.blocks[5].toMarkdownLine(), '---');
  });

  test('NoteAttachment detects image attachments for inline preview', () {
    expect(
      const NoteAttachment(
        name: 'photo',
        uri: 'content://media/photo/1',
        mimeType: 'image/jpeg',
      ).isImage,
      isTrue,
    );
    expect(
      const NoteAttachment(
        name: 'diagram.png',
        uri: 'https://example.com/asset',
      ).isImage,
      isTrue,
    );
    expect(
      const NoteAttachment(
        name: '文档',
        uri: 'https://example.com/doc.pdf',
        mimeType: 'application/pdf',
      ).isImage,
      isFalse,
    );
  });
}
