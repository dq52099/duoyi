class GrowthLevel {
  final int level;
  final String title;
  final int currentCoins;
  final int currentLevelFloor;
  final int nextLevelCoins;

  const GrowthLevel({
    required this.level,
    required this.title,
    required this.currentCoins,
    required this.currentLevelFloor,
    required this.nextLevelCoins,
  });

  int get coinsIntoLevel => currentCoins - currentLevelFloor;

  int get coinsForNextLevel => nextLevelCoins - currentLevelFloor;

  int get coinsRemaining => (nextLevelCoins - currentCoins).clamp(0, 1 << 30);

  double get progress => coinsForNextLevel <= 0
      ? 1
      : (coinsIntoLevel / coinsForNextLevel).clamp(0.0, 1.0);
}

class GrowthLevels {
  const GrowthLevels._();

  static const List<int> thresholds = [
    0,
    100,
    260,
    520,
    900,
    1400,
    2050,
    2850,
    3800,
    4900,
    6150,
    7550,
    9100,
    10800,
    12650,
  ];

  static const List<String> titles = [
    '时间学徒',
    '清单新星',
    '节奏建立者',
    '专注行者',
    '习惯筑基者',
    '周计划达人',
    '深度工作者',
    '复盘实践家',
    '效率教练',
    '长期主义者',
    '时间掌舵人',
    '目标合伙人',
    '心流专家',
    '多仪大师',
    '时间战略家',
  ];

  static GrowthLevel fromLifetimeCoins(int coins) {
    final currentCoins = coins < 0 ? 0 : coins;
    var index = 0;
    for (var i = 0; i < thresholds.length; i++) {
      if (currentCoins >= thresholds[i]) index = i;
    }
    final isMaxLevel = index == thresholds.length - 1;
    final next = isMaxLevel ? thresholds[index] : thresholds[index + 1];
    return GrowthLevel(
      level: index + 1,
      title: titles[index.clamp(0, titles.length - 1)],
      currentCoins: currentCoins,
      currentLevelFloor: thresholds[index],
      nextLevelCoins: next,
    );
  }
}
