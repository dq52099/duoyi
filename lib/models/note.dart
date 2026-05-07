class NoteItem {
  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteItem({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

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
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NoteItem.fromJson(Map<String, dynamic> json) => NoteItem(
    id: json['id'],
    content: json['content'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );
}
