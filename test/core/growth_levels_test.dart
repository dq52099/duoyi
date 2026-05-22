import 'package:test/test.dart';

import 'package:duoyi/core/growth_levels.dart';

void main() {
  test('GrowthLevels derives level title and progress from lifetime coins', () {
    final starter = GrowthLevels.fromLifetimeCoins(0);
    expect(starter.level, 1);
    expect(starter.title, '时间学徒');
    expect(starter.progress, 0);
    expect(starter.coinsRemaining, 100);

    final mid = GrowthLevels.fromLifetimeCoins(180);
    expect(mid.level, 2);
    expect(mid.title, '清单新星');
    expect(mid.currentLevelFloor, 100);
    expect(mid.nextLevelCoins, 260);
    expect(mid.coinsIntoLevel, 80);
    expect(mid.coinsRemaining, 80);
    expect(mid.progress, closeTo(0.5, 0.001));
  });

  test('GrowthLevels caps at max level for high lifetime coins', () {
    final maxed = GrowthLevels.fromLifetimeCoins(20000);

    expect(maxed.level, GrowthLevels.thresholds.length);
    expect(maxed.title, '时间战略家');
    expect(maxed.coinsRemaining, 0);
    expect(maxed.progress, 1);
  });
}
