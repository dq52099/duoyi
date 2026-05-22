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
    return mimeType.startsWith('image/') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerUri.endsWith('.png') ||
        lowerUri.endsWith('.jpg') ||
        lowerUri.endsWith('.jpeg') ||
        lowerUri.endsWith('.webp');
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
    if (trimmed.startsWith('- [ ] ') || trimmed.startsWith('- [x] ')) {
      return NoteBlock(
        id: id,
        type: NoteBlockType.checklist,
        checked: trimmed.startsWith('- [x] '),
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
}

class NoteItem {
  final String id;
  final String content;
  final String format;
  final List<NoteBlock> blocks;
  final List<NoteAttachment> attachments;
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
    this.pinned = false,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  }) : blocks = List<NoteBlock>.unmodifiable(
         blocks ?? NoteBlock.fromMarkdown(content),
       );

  String get title {
    final lines = content.trim().split('\n');
    return lines.isNotEmpty && lines.first.isNotEmpty ? lines.first : '无标题笔记';
  }

  String get preview {
    final lines = content.trim().split('\n');
    if (lines.length > 1) {
      return lines.sublist(1).join(' ').trim();
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'format': format,
    'blocks': blocks.map((e) => e.toJson()).toList(),
    'attachments': attachments.map((e) => e.toJson()).toList(),
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
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
