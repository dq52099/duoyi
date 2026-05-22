class UserProfile {
  String username;
  String avatarInitials;
  String displayName;
  String email;
  bool emailVerified;
  String avatarUrl;
  String bio;
  int totalTodosCompleted;
  int totalFocusMinutes;
  int currentStreak;
  int bestStreak;
  DateTime? updatedAt;
  DateTime? lastSyncTime;

  UserProfile({
    this.username = '用户',
    this.avatarInitials = '我',
    this.displayName = '',
    this.email = '',
    this.emailVerified = false,
    this.avatarUrl = '',
    this.bio = '',
    this.totalTodosCompleted = 0,
    this.totalFocusMinutes = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.updatedAt,
    this.lastSyncTime,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'avatarInitials': avatarInitials,
    'displayName': displayName,
    'email': email,
    'emailVerified': emailVerified,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'totalTodosCompleted': totalTodosCompleted,
    'totalFocusMinutes': totalFocusMinutes,
    'currentStreak': currentStreak,
    'bestStreak': bestStreak,
    'updatedAt': updatedAt?.toIso8601String(),
    'lastSyncTime': lastSyncTime?.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    username: json['username'] ?? '用户',
    avatarInitials: json['avatarInitials'] ?? '我',
    displayName: json['displayName'] ?? '',
    email: json['email'] ?? '',
    emailVerified: json['emailVerified'] == true,
    avatarUrl: json['avatarUrl'] ?? '',
    bio: json['bio'] ?? '',
    totalTodosCompleted: json['totalTodosCompleted'] ?? 0,
    totalFocusMinutes: json['totalFocusMinutes'] ?? 0,
    currentStreak: json['currentStreak'] ?? 0,
    bestStreak: json['bestStreak'] ?? 0,
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'])
        : null,
    lastSyncTime: json['lastSyncTime'] != null
        ? DateTime.parse(json['lastSyncTime'])
        : null,
  );

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 9) return '早上好';
    if (hour < 12) return '上午好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  int get productivityScore {
    int score = 0;
    score += (totalTodosCompleted * 2).clamp(0, 30);
    score += (totalFocusMinutes ~/ 60 * 3).clamp(0, 30);
    score += (currentStreak * 5).clamp(0, 25);
    score += (bestStreak * 2).clamp(0, 15);
    return score.clamp(0, 100);
  }
}
