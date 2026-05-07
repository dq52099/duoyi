class CountdownItem {
  final String id;
  final String title;
  final DateTime targetDate;
  final bool isPinned;

  CountdownItem({
    required this.id,
    required this.title,
    required this.targetDate,
    this.isPinned = false,
  });

  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    return target.difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'targetDate': targetDate.toIso8601String(),
    'isPinned': isPinned,
  };

  factory CountdownItem.fromJson(Map<String, dynamic> json) => CountdownItem(
    id: json['id'],
    title: json['title'],
    targetDate: DateTime.parse(json['targetDate']),
    isPinned: json['isPinned'] ?? false,
  );
}
