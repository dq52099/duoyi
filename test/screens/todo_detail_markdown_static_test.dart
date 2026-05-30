import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('任务详情复用笔记 Markdown 模型渲染任务描述预览', () {
    final source = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        "import '../models/note.dart' show NoteAttachment, NoteBlock, NoteBlockType;",
      ),
    );
    expect(source, contains('bool _notesPreview = false'));
    expect(source, contains('_TodoMarkdownDescriptionEditor'));
    expect(source, contains('_TodoMarkdownToolbar'));
    expect(source, contains('_TodoMarkdownPreview'));
    expect(source, contains('_TodoMarkdownPreviewBlock'));
    expect(source, contains('_TodoInlineMarkdownText'));
    expect(source, contains('NoteBlock.fromMarkdown(content)'));
    expect(source, contains("content: controller.text"));
    expect(source, contains("'暂无描述'"));
  });

  test('任务描述 Markdown 预览覆盖常用块级语法', () {
    final source = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('NoteBlockType.heading'));
    expect(source, contains('NoteBlockType.quote'));
    expect(source, contains('NoteBlockType.checklist'));
    expect(source, contains('NoteBlockType.bullet'));
    expect(source, contains('NoteBlockType.code'));
    expect(source, contains('NoteBlockType.divider'));
    expect(source, contains('Icons.check_box'));
    expect(source, contains('Icons.check_box_outline_blank'));
    expect(source, contains('Icons.circle'));
  });

  test('任务描述工具栏提供标题加粗斜体引用列表清单代码和链接', () {
    final source = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Icons.title'));
    expect(source, contains('Icons.format_bold'));
    expect(source, contains('Icons.format_italic'));
    expect(source, contains('Icons.format_quote'));
    expect(source, contains('Icons.format_list_bulleted'));
    expect(source, contains('Icons.checklist'));
    expect(source, contains('Icons.code'));
    expect(source, contains('Icons.link'));
    expect(source, contains("tooltip: '标题'"));
    expect(source, contains("tooltip: '加粗'"));
    expect(source, contains("tooltip: '斜体'"));
    expect(source, contains("tooltip: '引用'"));
    expect(source, contains("tooltip: '列表'"));
    expect(source, contains("tooltip: '清单'"));
    expect(source, contains("tooltip: '代码'"));
    expect(source, contains("tooltip: '链接'"));
  });

  test('任务描述编辑动作写入现有 notes 字段保持旧数据兼容', () {
    final source = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_insertNotePrefix'));
    expect(source, contains('_wrapNoteSelection'));
    expect(source, contains('_insertNoteLink'));
    expect(source, contains("_insertNotePrefix('## ')"));
    expect(source, contains("_wrapNoteSelection('**')"));
    expect(source, contains("_wrapNoteSelection('*')"));
    expect(source, contains("_insertNotePrefix('> ')"));
    expect(source, contains("_insertNotePrefix('- ')"));
    expect(source, contains("_insertNotePrefix('- [ ] ')"));
    expect(source, contains("_wrapNoteSelection('`')"));
    expect(
      source,
      contains(
        "final nextTodo = _todo.copyWith(\n      title: title,\n      notes: _notesCtrl.text.trim(),\n    );",
      ),
    );
  });
}
