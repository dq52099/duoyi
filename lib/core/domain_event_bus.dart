import 'dart:async';

enum DomainEventType {
  todoCreated,
  todoCompleted,
  habitCreated,
  habitCheckedIn,
  pomodoroCompleted,
  goalCreated,
  goalAchieved,
  goalMilestoneCompleted,
  diaryWritten,
  themeSwitched,
}

class DomainEvent {
  final DomainEventType type;
  final String objectId;
  final DateTime occurredAt;
  final Map<String, Object?> metadata;

  DomainEvent({
    required this.type,
    required this.objectId,
    DateTime? occurredAt,
    Map<String, Object?>? metadata,
  }) : occurredAt = occurredAt ?? DateTime.now(),
       metadata = Map.unmodifiable(metadata ?? const <String, Object?>{});
}

class DomainEventBus {
  DomainEventBus._();

  static final DomainEventBus instance = DomainEventBus._();

  final StreamController<DomainEvent> _controller =
      StreamController<DomainEvent>.broadcast(sync: true);

  Stream<DomainEvent> get events => _controller.stream;

  void publish(DomainEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }
}
