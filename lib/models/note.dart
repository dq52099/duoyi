import '../core/diary_note_ui_copy.dart';
import '../core/i18n.dart';

class NoteAttachment {
  final String name;
  final String uri;
  final String mimeType;

  const NoteAttachment({
    required this.name,
    required this.uri,
    this.mimeType = '',
  });

  bool get isImage {
    final lowerName = name.toLowerCase();
    final lowerUri = uri.toLowerCase();
    return mimeType.toLowerCase().startsWith('image/') ||
        lowerUri.startsWith('data:image/') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif') ||
        lowerUri.endsWith('.png') ||
        lowerUri.endsWith('.jpg') ||
        lowerUri.endsWith('.jpeg') ||
        lowerUri.endsWith('.webp') ||
        lowerUri.endsWith('.gif');
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'uri': uri,
    'mimeType': mimeType,
  };

  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
    name: json['name']?.toString() ?? '附件',
    uri: json['uri']?.toString() ?? '',
    mimeType: json['mimeType']?.toString() ?? '',
  );
}

enum NoteBlockType {
  paragraph,
  heading,
  quote,
  bullet,
  checklist,
  code,
  divider,
}

class NoteBlock {
  final String id;
  final NoteBlockType type;
  final String text;
  final int level;
  final bool checked;
  final Map<String, String> attributes;

  const NoteBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.level = 0,
    this.checked = false,
    this.attributes = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'level': level,
    'checked': checked,
    'attributes': attributes,
  };

  factory NoteBlock.fromJson(Map<String, dynamic> json) => NoteBlock(
    id: json['id']?.toString() ?? '',
    type: NoteBlockType.values.firstWhere(
      (type) => type.name == json['type']?.toString(),
      orElse: () => NoteBlockType.paragraph,
    ),
    text: json['text']?.toString() ?? '',
    level: (json['level'] as num?)?.toInt() ?? 0,
    checked: json['checked'] == true,
    attributes:
        (json['attributes'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ) ??
        const {},
  );

  String toMarkdownLine() {
    return switch (type) {
      NoteBlockType.heading => '${'#' * level.clamp(1, 6)} $text',
      NoteBlockType.quote => '> $text',
      NoteBlockType.bullet => '- $text',
      NoteBlockType.checklist => '- [${checked ? 'x' : ' '}] $text',
      NoteBlockType.code => '`$text`',
      NoteBlockType.divider => '---',
      NoteBlockType.paragraph => text,
    };
  }

  static List<NoteBlock> fromMarkdown(String content) {
    final lines = content.split('\n');
    return [
      for (var i = 0; i < lines.length; i++) fromMarkdownLine(lines[i], i),
    ];
  }

  static NoteBlock fromMarkdownLine(String line, int index) {
    final trimmed = line.trimLeft();
    final id = 'b$index';
    if (RegExp(r'^#{1,6} ').hasMatch(trimmed)) {
      final level = trimmed.indexOf(' ');
      return NoteBlock(
        id: id,
        type: NoteBlockType.heading,
        level: level,
        text: trimmed.substring(level + 1),
      );
    }
    if (trimmed == '---' || trimmed == '***') {
      return NoteBlock(id: id, type: NoteBlockType.divider);
    }
    if (trimmed.startsWith('> ')) {
      return NoteBlock(
        id: id,
        type: NoteBlockType.quote,
        text: trimmed.substring(2),
      );
    }
    if (trimmed.startsWith('- [ ] ') ||
        trimmed.startsWith('- [x] ') ||
        trimmed.startsWith('- [X] ')) {
      return NoteBlock(
        id: id,
        type: NoteBlockType.checklist,
        checked: trimmed.startsWith('- [x] ') || trimmed.startsWith('- [X] '),
        text: trimmed.substring(6),
      );
    }
    if (trimmed.startsWith('- ')) {
      return NoteBlock(
        id: id,
        type: NoteBlockType.bullet,
        text: trimmed.substring(2),
      );
    }
    if (trimmed.startsWith('`') &&
        trimmed.endsWith('`') &&
        trimmed.length >= 2) {
      return NoteBlock(
        id: id,
        type: NoteBlockType.code,
        text: trimmed.substring(1, trimmed.length - 1),
      );
    }
    return NoteBlock(id: id, type: NoteBlockType.paragraph, text: line);
  }

  /// Toggles a Markdown checklist item (`- [ ] ` <-> `- [x] `) at [lineIndex].
  static String toggleChecklistLine(String content, int lineIndex) {
    final lines = content.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return content;
    final line = lines[lineIndex];
    final trimmed = line.trimLeft();
    final indent = line.substring(0, line.length - trimmed.length);
    if (trimmed.startsWith('- [ ] ')) {
      lines[lineIndex] = '$indent- [x] ${trimmed.substring(6)}';
      return lines.join('\n');
    }
    if (trimmed.startsWith('- [x] ') || trimmed.startsWith('- [X] ')) {
      lines[lineIndex] = '$indent- [ ] ${trimmed.substring(6)}';
      return lines.join('\n');
    }
    return content;
  }
}

class NoteItem {
  final String id;
  final String content;
  final String format;
  final List<NoteBlock> blocks;
  final List<NoteAttachment> attachments;
  final List<String> tags;
  final String? folder;
  final bool pinned;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteItem({
    required this.id,
    required this.content,
    this.format = 'markdown',
    List<NoteBlock>? blocks,
    this.attachments = const [],
    List<String> tags = const [],
    String? folder,
    this.pinned = false,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  }) : blocks = List<NoteBlock>.unmodifiable(
         blocks ?? NoteBlock.fromMarkdown(content),
       ),
       tags = normalizeTags(tags),
       folder = normalizeFolder(folder);

  static List<String> normalizeTags(Iterable<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in raw) {
      final cleaned = item.trim();
      if (cleaned.isNotEmpty && seen.add(cleaned)) {
        out.add(cleaned);
      }
    }
    return List<String>.unmodifiable(out);
  }

  static String? normalizeFolder(String? raw) {
    final cleaned = raw?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  String get title => titleFor(I18n.current);

  String titleFor(AppLocale locale) {
    final lines = content.trim().split('\n');
    return lines.isNotEmpty && lines.first.isNotEmpty
        ? lines.first
        : DiaryNoteUiCopy(locale).untitledNote;
  }

  String get preview {
    final lines = content.trim().split('\n');
    if (lines.length > 1) {
      return lines.sublist(1).join(' ').trim();
    }
    return '';
  }

  String toMarkdownDocument([AppLocale? locale]) {
    final buffer = StringBuffer();
    final body = content.trimRight();
    if (body.isNotEmpty) {
      buffer.write(body);
    } else {
      buffer.write('# ${titleFor(locale ?? I18n.current)}');
    }
    final cleanFolder = normalizeFolder(folder);
    final hasMeta =
        cleanFolder != null || tags.isNotEmpty || attachments.isNotEmpty;
    if (hasMeta) {
      buffer.writeln();
      buffer.writeln();
      buffer.writeln('---');
      if (cleanFolder != null) {
        buffer.writeln('Folder: $cleanFolder');
      }
      if (tags.isNotEmpty) {
        buffer.writeln('Tags: ${tags.map((t) => '#$t').join(' ')}');
      }
      if (attachments.isNotEmpty) {
        buffer.writeln('Attachments:');
        for (final attachment in attachments) {
          buffer.writeln('- [${attachment.name}](${attachment.uri})');
        }
      }
    }
    return '${buffer.toString().trimRight()}\n';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'format': format,
    'blocks': blocks.map((e) => e.toJson()).toList(),
    'attachments': attachments.map((e) => e.toJson()).toList(),
    if (tags.isNotEmpty) 'tags': tags,
    if (folder != null) 'folder': folder,
    'pinned': pinned,
    'archived': archived,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NoteItem.fromJson(Map<String, dynamic> json) => NoteItem(
    id: json['id'],
    content: json['content']?.toString() ?? '',
    format: json['format']?.toString() ?? 'markdown',
    blocks: (json['blocks'] as List?)
        ?.whereType<Map>()
        .map((e) => NoteBlock.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList(),
    attachments:
        (json['attachments'] as List?)
            ?.whereType<Map>()
            .map((e) => NoteAttachment.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.uri.isNotEmpty)
            .toList() ??
        const [],
    tags:
        (json['tags'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        const [],
    folder: normalizeFolder(json['folder']?.toString()),
    pinned: json['pinned'] == true,
    archived: json['archived'] == true,
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );

  NoteItem copyWith({
    String? id,
    String? content,
    String? format,
    List<NoteBlock>? blocks,
    List<NoteAttachment>? attachments,
    List<String>? tags,
    String? folder,
    bool clearFolder = false,
    bool? pinned,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteItem(
      id: id ?? this.id,
      content: content ?? this.content,
      format: format ?? this.format,
      blocks: blocks ?? this.blocks,
      attachments: attachments ?? this.attachments,
      tags: tags ?? this.tags,
      folder: clearFolder ? null : (folder ?? this.folder),
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
