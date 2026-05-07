import 'package:flutter/material.dart';

class HabitTemplate {
  final String name;
  final int targetCount;
  final int colorValue;
  final IconData icon;
  final String category;

  HabitTemplate({
    required this.name,
    required this.targetCount,
    required this.colorValue,
    required this.icon,
    required this.category,
  });
}

class HabitTemplates {
  static final List<HabitTemplate> all = [
    // Health
    HabitTemplate(
      name: '每日喝水',
      targetCount: 8,
      colorValue: 0xFF2196F3,
      icon: Icons.local_drink,
      category: '身体健康',
    ),
    HabitTemplate(
      name: '早起',
      targetCount: 1,
      colorValue: 0xFFFF9800,
      icon: Icons.wb_sunny,
      category: '身体健康',
    ),
    HabitTemplate(
      name: '跑步 5km',
      targetCount: 1,
      colorValue: 0xFFE91E63,
      icon: Icons.directions_run,
      category: '身体健康',
    ),
    HabitTemplate(
      name: '早睡',
      targetCount: 1,
      colorValue: 0xFF3F51B5,
      icon: Icons.bedtime,
      category: '身体健康',
    ),

    // Study
    HabitTemplate(
      name: '阅读 30分钟',
      targetCount: 1,
      colorValue: 0xFF4CAF50,
      icon: Icons.book,
      category: '学习提升',
    ),
    HabitTemplate(
      name: '背 50个单词',
      targetCount: 1,
      colorValue: 0xFF9C27B0,
      icon: Icons.translate,
      category: '学习提升',
    ),
    HabitTemplate(
      name: '复习当日笔记',
      targetCount: 1,
      colorValue: 0xFF00BCD4,
      icon: Icons.edit_note,
      category: '学习提升',
    ),

    // Life
    HabitTemplate(
      name: '每日冥想',
      targetCount: 1,
      colorValue: 0xFF607D8B,
      icon: Icons.self_improvement,
      category: '心理调节',
    ),
    HabitTemplate(
      name: '记账',
      targetCount: 1,
      colorValue: 0xFF795548,
      icon: Icons.account_balance_wallet,
      category: '生活习惯',
    ),
    HabitTemplate(
      name: '整理房间',
      targetCount: 1,
      colorValue: 0xFF8BC34A,
      icon: Icons.cleaning_services,
      category: '生活习惯',
    ),
  ];

  static Map<String, List<HabitTemplate>> get byCategory {
    final map = <String, List<HabitTemplate>>{};
    for (final t in all) {
      map.putIfAbsent(t.category, () => []).add(t);
    }
    return map;
  }
}
