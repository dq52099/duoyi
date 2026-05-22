import 'domain_event_bus.dart';

class RewardGrant {
  final String id;
  final String title;
  final int coins;
  final String reason;

  const RewardGrant({
    required this.id,
    required this.title,
    required this.coins,
    required this.reason,
  });
}

class VirtualRewardRules {
  const VirtualRewardRules._();

  static RewardGrant? forEvent(DomainEvent event) {
    return switch (event.type) {
      DomainEventType.todoCompleted => RewardGrant(
        id: 'event:todo:${event.objectId}',
        title: '完成待办',
        coins: 5,
        reason: '待办完成奖励',
      ),
      DomainEventType.habitCheckedIn => RewardGrant(
        id: 'event:habit:${event.objectId}:${event.metadata['date'] ?? event.occurredAt.toIso8601String()}:${event.metadata['count'] ?? 1}',
        title: '习惯打卡',
        coins: 3,
        reason: '习惯打卡奖励',
      ),
      DomainEventType.pomodoroCompleted => RewardGrant(
        id: 'event:focus:${event.objectId}',
        title: '完成专注',
        coins: _focusCoins(event.metadata['durationSeconds']),
        reason: '专注时长奖励',
      ),
      DomainEventType.goalAchieved => RewardGrant(
        id: 'event:goal:${event.objectId}',
        title: '达成目标',
        coins: 30,
        reason: '目标达成奖励',
      ),
      DomainEventType.goalMilestoneCompleted => RewardGrant(
        id: 'event:milestone:${event.objectId}',
        title: '完成里程碑',
        coins: 12,
        reason: '目标里程碑奖励',
      ),
      DomainEventType.diaryWritten => RewardGrant(
        id: 'event:diary:${event.objectId}',
        title: '写下日记',
        coins: 4,
        reason: '日记记录奖励',
      ),
      DomainEventType.todoCreated ||
      DomainEventType.habitCreated ||
      DomainEventType.goalCreated ||
      DomainEventType.themeSwitched => null,
    };
  }

  static RewardGrant forAchievement({
    required String id,
    required String title,
    required String description,
  }) {
    return RewardGrant(
      id: 'achievement:$id',
      title: '解锁成就：$title',
      coins: 50,
      reason: description,
    );
  }

  static int _focusCoins(Object? rawSeconds) {
    final seconds = rawSeconds is int ? rawSeconds : 0;
    final minutes = seconds <= 0 ? 25 : (seconds / 60).round();
    return (minutes / 5).ceil().clamp(1, 12);
  }
}
