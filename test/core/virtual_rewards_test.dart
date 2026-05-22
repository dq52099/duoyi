import 'package:test/test.dart';

import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/core/virtual_rewards.dart';

void main() {
  test('forEvent grants coins for completed work events', () {
    final todoGrant = VirtualRewardRules.forEvent(
      DomainEvent(type: DomainEventType.todoCompleted, objectId: 'todo-1'),
    );
    final habitGrant = VirtualRewardRules.forEvent(
      DomainEvent(
        type: DomainEventType.habitCheckedIn,
        objectId: 'habit-1',
        metadata: const {'date': '2026-05-20', 'count': 1},
      ),
    );
    final focusGrant = VirtualRewardRules.forEvent(
      DomainEvent(
        type: DomainEventType.pomodoroCompleted,
        objectId: 'focus-1',
        metadata: const {'durationSeconds': 25 * 60},
      ),
    );

    expect(todoGrant?.coins, 5);
    expect(habitGrant?.id, 'event:habit:habit-1:2026-05-20:1');
    expect(habitGrant?.coins, 3);
    expect(focusGrant?.coins, 5);
  });

  test('forEvent does not reward setup-only events', () {
    final grant = VirtualRewardRules.forEvent(
      DomainEvent(type: DomainEventType.todoCreated, objectId: 'todo-1'),
    );

    expect(grant, isNull);
  });

  test('forAchievement grants bonus coins per unlocked badge', () {
    final grant = VirtualRewardRules.forAchievement(
      id: 'first_todo',
      title: '启程',
      description: '完成第一个待办',
    );

    expect(grant.id, 'achievement:first_todo');
    expect(grant.title, '解锁成就：启程');
    expect(grant.coins, 50);
  });
}
