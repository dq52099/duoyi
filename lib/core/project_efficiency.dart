class ProjectEfficiencyTodoCompletion {
  final DateTime completedAt;
  final String projectKey;
  final String projectLabel;

  const ProjectEfficiencyTodoCompletion({
    required this.completedAt,
    required this.projectKey,
    required this.projectLabel,
  });
}

class ProjectEfficiencyGoalCompletion {
  final DateTime completedAt;
  final String projectKey;
  final String projectLabel;

  const ProjectEfficiencyGoalCompletion({
    required this.completedAt,
    required this.projectKey,
    required this.projectLabel,
  });
}

class ProjectEfficiencyTimeAllocation {
  final String projectKey;
  final String projectLabel;
  final int durationSeconds;

  const ProjectEfficiencyTimeAllocation({
    required this.projectKey,
    required this.projectLabel,
    required this.durationSeconds,
  });
}

class ProjectEfficiencyItem {
  final String projectKey;
  final String projectLabel;
  final int completedTodos;
  final int completedGoalSteps;
  final int timeSeconds;

  const ProjectEfficiencyItem({
    required this.projectKey,
    required this.projectLabel,
    required this.completedTodos,
    required this.completedGoalSteps,
    required this.timeSeconds,
  });

  int get outputCount => completedTodos + completedGoalSteps;

  int get timeMinutes => timeSeconds ~/ 60;

  bool get hasActivity => outputCount > 0 || timeSeconds > 0;

  double get outputPerHour {
    if (timeSeconds <= 0) return 0;
    return outputCount / (timeSeconds / 3600);
  }
}

class ProjectEfficiencyBreakdown {
  final List<ProjectEfficiencyItem> items;

  const ProjectEfficiencyBreakdown({required this.items});

  bool get hasData => items.any((item) => item.hasActivity);

  ProjectEfficiencyItem? get topItem =>
      rankedItems.isEmpty ? null : rankedItems.first;

  List<ProjectEfficiencyItem> get rankedItems {
    final active = items.where((item) => item.hasActivity).toList();
    active.sort((a, b) {
      final byRate = b.outputPerHour.compareTo(a.outputPerHour);
      if (byRate != 0) return byRate;
      final byOutput = b.outputCount.compareTo(a.outputCount);
      if (byOutput != 0) return byOutput;
      final byTime = b.timeSeconds.compareTo(a.timeSeconds);
      if (byTime != 0) return byTime;
      return a.projectLabel.compareTo(b.projectLabel);
    });
    return active;
  }

  int get maxOutputCount => items.fold<int>(
    0,
    (max, item) => item.outputCount > max ? item.outputCount : max,
  );

  int get maxTimeMinutes => items.fold<int>(
    0,
    (max, item) => item.timeMinutes > max ? item.timeMinutes : max,
  );

  double get maxOutputPerHour => items.fold<double>(
    0,
    (max, item) => item.outputPerHour > max ? item.outputPerHour : max,
  );
}

class ProjectEfficiencyAnalyzer {
  const ProjectEfficiencyAnalyzer._();

  static ProjectEfficiencyBreakdown build({
    required Iterable<ProjectEfficiencyTodoCompletion> todoCompletions,
    required Iterable<ProjectEfficiencyGoalCompletion> goalCompletions,
    required Iterable<ProjectEfficiencyTimeAllocation> timeAllocations,
    int limit = 8,
  }) {
    final buckets = <String, _MutableProjectEfficiency>{};

    _MutableProjectEfficiency bucket(String key, String label) =>
        buckets.putIfAbsent(
          key,
          () => _MutableProjectEfficiency(
            projectKey: key,
            projectLabel: label.trim().isEmpty ? '未命名项目' : label.trim(),
          ),
        );

    for (final completion in todoCompletions) {
      bucket(completion.projectKey, completion.projectLabel).completedTodos +=
          1;
    }
    for (final completion in goalCompletions) {
      bucket(
        completion.projectKey,
        completion.projectLabel,
      ).completedGoalSteps += 1;
    }
    for (final allocation in timeAllocations) {
      if (allocation.durationSeconds <= 0) continue;
      bucket(allocation.projectKey, allocation.projectLabel).timeSeconds +=
          allocation.durationSeconds;
    }

    final items = [
      for (final item in buckets.values)
        ProjectEfficiencyItem(
          projectKey: item.projectKey,
          projectLabel: item.projectLabel,
          completedTodos: item.completedTodos,
          completedGoalSteps: item.completedGoalSteps,
          timeSeconds: item.timeSeconds,
        ),
    ];
    final ranked = ProjectEfficiencyBreakdown(items: items).rankedItems;
    return ProjectEfficiencyBreakdown(
      items: ranked.take(limit).toList(growable: false),
    );
  }
}

class _MutableProjectEfficiency {
  final String projectKey;
  final String projectLabel;
  int completedTodos = 0;
  int completedGoalSteps = 0;
  int timeSeconds = 0;

  _MutableProjectEfficiency({
    required this.projectKey,
    required this.projectLabel,
  });
}
