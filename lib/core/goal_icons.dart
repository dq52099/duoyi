import 'package:flutter/material.dart';

const String goalFeatureIconAsset = 'assets/icons/goal_icon.png';

class GoalIconChoice {
  final String name;
  final String label;
  final IconData icon;
  final Color color;

  const GoalIconChoice({
    required this.name,
    required this.label,
    required this.icon,
    required this.color,
  });
}

const GoalIconChoice defaultGoalIconChoice = GoalIconChoice(
  name: 'flag',
  label: '旗帜',
  icon: Icons.flag,
  color: Color(0xFFFFA726),
);

const List<GoalIconChoice> goalIconChoices = <GoalIconChoice>[
  defaultGoalIconChoice,
  GoalIconChoice(
    name: 'track_changes',
    label: '靶心',
    icon: Icons.track_changes,
    color: Color(0xFF1E88E5),
  ),
  GoalIconChoice(
    name: 'flag_circle',
    label: '里程碑',
    icon: Icons.flag_circle_outlined,
    color: Color(0xFFFF8F00),
  ),
  GoalIconChoice(
    name: 'emoji_events',
    label: '奖杯',
    icon: Icons.emoji_events,
    color: Color(0xFFFFB300),
  ),
  GoalIconChoice(
    name: 'workspace_premium',
    label: '勋章',
    icon: Icons.workspace_premium,
    color: Color(0xFFEC407A),
  ),
  GoalIconChoice(
    name: 'rocket_launch',
    label: '冲刺',
    icon: Icons.rocket_launch,
    color: Color(0xFF7E57C2),
  ),
  GoalIconChoice(
    name: 'trending_up',
    label: '增长',
    icon: Icons.trending_up,
    color: Color(0xFF26A69A),
  ),
  GoalIconChoice(
    name: 'task_alt',
    label: '达成',
    icon: Icons.task_alt,
    color: Color(0xFF43A047),
  ),
  GoalIconChoice(
    name: 'local_drink',
    label: '饮水',
    icon: Icons.local_drink,
    color: Color(0xFF2196F3),
  ),
  GoalIconChoice(
    name: 'bedtime',
    label: '睡眠',
    icon: Icons.bedtime,
    color: Color(0xFF3F51B5),
  ),
  GoalIconChoice(
    name: 'self_improvement',
    label: '冥想',
    icon: Icons.self_improvement,
    color: Color(0xFF607D8B),
  ),
  GoalIconChoice(
    name: 'edit_note',
    label: '记录',
    icon: Icons.edit_note,
    color: Color(0xFF795548),
  ),
  GoalIconChoice(
    name: 'rate_review',
    label: '复盘',
    icon: Icons.rate_review,
    color: Color(0xFF009688),
  ),
  GoalIconChoice(
    name: 'directions_walk',
    label: '步行',
    icon: Icons.directions_walk,
    color: Color(0xFF4CAF50),
  ),
  GoalIconChoice(
    name: 'medical_services',
    label: '健康',
    icon: Icons.medical_services,
    color: Color(0xFFE53935),
  ),
  GoalIconChoice(
    name: 'remove_red_eye',
    label: '护眼',
    icon: Icons.remove_red_eye,
    color: Color(0xFF8E24AA),
  ),
  GoalIconChoice(
    name: 'restaurant',
    label: '饮食',
    icon: Icons.restaurant,
    color: Color(0xFFFF7043),
  ),
  GoalIconChoice(
    name: 'menu_book',
    label: '阅读',
    icon: Icons.menu_book,
    color: Color(0xFF42A5F5),
  ),
  GoalIconChoice(
    name: 'translate',
    label: '语言',
    icon: Icons.translate,
    color: Color(0xFF5C6BC0),
  ),
  GoalIconChoice(
    name: 'school',
    label: '学习',
    icon: Icons.school,
    color: Color(0xFF1E88E5),
  ),
  GoalIconChoice(
    name: 'assignment',
    label: '任务',
    icon: Icons.assignment,
    color: Color(0xFF78909C),
  ),
  GoalIconChoice(
    name: 'directions_run',
    label: '跑步',
    icon: Icons.directions_run,
    color: Color(0xFFEF5350),
  ),
  GoalIconChoice(
    name: 'fitness_center',
    label: '健身',
    icon: Icons.fitness_center,
    color: Color(0xFFD81B60),
  ),
  GoalIconChoice(
    name: 'accessibility_new',
    label: '拉伸',
    icon: Icons.accessibility_new,
    color: Color(0xFFAB47BC),
  ),
  GoalIconChoice(
    name: 'stairs',
    label: '爬楼',
    icon: Icons.stairs,
    color: Color(0xFF8D6E63),
  ),
  GoalIconChoice(
    name: 'pedal_bike',
    label: '骑行',
    icon: Icons.pedal_bike,
    color: Color(0xFF26A69A),
  ),
  GoalIconChoice(
    name: 'volunteer_activism',
    label: '陪伴',
    icon: Icons.volunteer_activism,
    color: Color(0xFFE91E63),
  ),
  GoalIconChoice(
    name: 'call',
    label: '通话',
    icon: Icons.call,
    color: Color(0xFF42A5F5),
  ),
  GoalIconChoice(
    name: 'mood',
    label: '心情',
    icon: Icons.mood,
    color: Color(0xFFFFCA28),
  ),
  GoalIconChoice(
    name: 'air',
    label: '呼吸',
    icon: Icons.air,
    color: Color(0xFF26C6DA),
  ),
  GoalIconChoice(
    name: 'message',
    label: '消息',
    icon: Icons.message,
    color: Color(0xFF5C6BC0),
  ),
  GoalIconChoice(
    name: 'calendar_today',
    label: '计划',
    icon: Icons.calendar_today,
    color: Color(0xFF607D8B),
  ),
  GoalIconChoice(
    name: 'lightbulb',
    label: '灵感',
    icon: Icons.lightbulb_outline,
    color: Color(0xFFFFB300),
  ),
  GoalIconChoice(
    name: 'local_fire_department',
    label: '热度',
    icon: Icons.local_fire_department,
    color: Color(0xFFFF7043),
  ),
];

GoalIconChoice goalIconChoiceFromName(String name) {
  for (final choice in goalIconChoices) {
    if (choice.name == name) return choice;
  }
  return defaultGoalIconChoice;
}

IconData goalIconFromName(String name) => goalIconChoiceFromName(name).icon;

String goalIconLabel(String name) => goalIconChoiceFromName(name).label;
