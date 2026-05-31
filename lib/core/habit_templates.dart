import 'package:flutter/material.dart';

import 'i18n.dart';
import '../models/habit.dart';

class HabitTemplate {
  final String id;
  final String name;
  final String nameEn;
  final int targetCount;
  final String unit;
  final String unitEn;
  final int? flexTarget;
  final HabitFlexPeriod? flexPeriod;
  final int colorValue;
  final IconData icon;
  final String category;
  final String categoryEn;

  HabitTemplate({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.targetCount,
    this.unit = '次',
    this.unitEn = 'times',
    this.flexTarget,
    this.flexPeriod,
    required this.colorValue,
    required this.icon,
    required this.category,
    required this.categoryEn,
  });

  String get localizedName => I18n.current == AppLocale.en ? nameEn : name;

  String get localizedCategory =>
      I18n.current == AppLocale.en ? categoryEn : category;

  String get localizedUnit => I18n.current == AppLocale.en ? unitEn : unit;

  bool get hasFlexRule =>
      flexTarget != null && flexTarget! > 0 && flexPeriod != null;

  String get localizedFrequencyLabel {
    if (!hasFlexRule) return I18n.current == AppLocale.en ? 'Daily' : '每天';
    return switch (flexPeriod!) {
      HabitFlexPeriod.week =>
        I18n.current == AppLocale.en
            ? 'Period target $flexTarget times/week'
            : '周期目标 $flexTarget 次/周',
      HabitFlexPeriod.month =>
        I18n.current == AppLocale.en
            ? 'Period target $flexTarget times/month'
            : '周期目标 $flexTarget 次/月',
    };
  }
}

class HabitTemplates {
  static final List<HabitTemplate> all = [
    // 身体健康
    HabitTemplate(
      id: 'habit.water',
      name: '每日喝水',
      nameEn: 'Drink water',
      targetCount: 8,
      unit: '杯',
      unitEn: 'cups',
      colorValue: 0xFF2196F3,
      icon: Icons.local_drink,
      category: '身体健康',
      categoryEn: 'Health',
    ),
    HabitTemplate(
      id: 'habit.early_rise',
      name: '早起',
      nameEn: 'Wake up early',
      targetCount: 1,
      colorValue: 0xFFFF9800,
      icon: Icons.wb_sunny,
      category: '身体健康',
      categoryEn: 'Health',
    ),
    HabitTemplate(
      id: 'habit.run_5km',
      name: '跑步 5km',
      nameEn: 'Run 5 km',
      targetCount: 1,
      flexTarget: 4,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFFE91E63,
      icon: Icons.directions_run,
      category: '身体健康',
      categoryEn: 'Health',
    ),
    HabitTemplate(
      id: 'habit.early_sleep',
      name: '早睡',
      nameEn: 'Sleep early',
      targetCount: 1,
      colorValue: 0xFF3F51B5,
      icon: Icons.bedtime,
      category: '身体健康',
      categoryEn: 'Health',
    ),
    HabitTemplate(
      id: 'habit.strength_training',
      name: '力量训练',
      nameEn: 'Strength training',
      targetCount: 1,
      flexTarget: 3,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFFFF5722,
      icon: Icons.fitness_center,
      category: '身体健康',
      categoryEn: 'Health',
    ),

    // 学习提升
    HabitTemplate(
      id: 'habit.read_30min',
      name: '阅读 30分钟',
      nameEn: 'Read 30 min',
      targetCount: 1,
      colorValue: 0xFF4CAF50,
      icon: Icons.book,
      category: '学习提升',
      categoryEn: 'Learning',
    ),
    HabitTemplate(
      id: 'habit.words_50',
      name: '背 50 个单词',
      nameEn: 'Review 50 words',
      targetCount: 1,
      colorValue: 0xFF9C27B0,
      icon: Icons.translate,
      category: '学习提升',
      categoryEn: 'Learning',
    ),
    HabitTemplate(
      id: 'habit.review_notes',
      name: '复习当日笔记',
      nameEn: 'Review today notes',
      targetCount: 1,
      colorValue: 0xFF00BCD4,
      icon: Icons.edit_note,
      category: '学习提升',
      categoryEn: 'Learning',
    ),
    HabitTemplate(
      id: 'habit.online_course',
      name: '完成一节课',
      nameEn: 'Finish one lesson',
      targetCount: 1,
      flexTarget: 4,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF3F51B5,
      icon: Icons.school,
      category: '学习提升',
      categoryEn: 'Learning',
    ),
    HabitTemplate(
      id: 'habit.coding_practice',
      name: '编程练习',
      nameEn: 'Coding practice',
      targetCount: 1,
      flexTarget: 5,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF009688,
      icon: Icons.code,
      category: '学习提升',
      categoryEn: 'Learning',
    ),

    // 心理调节
    HabitTemplate(
      id: 'habit.meditation',
      name: '每日冥想',
      nameEn: 'Daily meditation',
      targetCount: 1,
      colorValue: 0xFF607D8B,
      icon: Icons.self_improvement,
      category: '心理调节',
      categoryEn: 'Mindfulness',
    ),
    HabitTemplate(
      id: 'habit.gratitude',
      name: '感恩记录',
      nameEn: 'Gratitude note',
      targetCount: 1,
      colorValue: 0xFFFF7043,
      icon: Icons.favorite,
      category: '心理调节',
      categoryEn: 'Mindfulness',
    ),
    HabitTemplate(
      id: 'habit.mood_check',
      name: '情绪复盘',
      nameEn: 'Mood check-in',
      targetCount: 1,
      colorValue: 0xFFFFC107,
      icon: Icons.mood,
      category: '心理调节',
      categoryEn: 'Mindfulness',
    ),
    HabitTemplate(
      id: 'habit.breathing',
      name: '呼吸放松',
      nameEn: 'Breathing exercise',
      targetCount: 1,
      colorValue: 0xFF00BCD4,
      icon: Icons.air,
      category: '心理调节',
      categoryEn: 'Mindfulness',
    ),
    HabitTemplate(
      id: 'habit.digital_sunset',
      name: '睡前远离屏幕',
      nameEn: 'Screen-free wind down',
      targetCount: 1,
      colorValue: 0xFF5C6BC0,
      icon: Icons.nightlight_round,
      category: '心理调节',
      categoryEn: 'Mindfulness',
    ),

    // 生活习惯
    HabitTemplate(
      id: 'habit.bookkeeping',
      name: '记账',
      nameEn: 'Track expenses',
      targetCount: 1,
      colorValue: 0xFF795548,
      icon: Icons.account_balance_wallet,
      category: '生活习惯',
      categoryEn: 'Life',
    ),
    HabitTemplate(
      id: 'habit.clean_room',
      name: '整理房间',
      nameEn: 'Tidy room',
      targetCount: 1,
      colorValue: 0xFF8BC34A,
      icon: Icons.cleaning_services,
      category: '生活习惯',
      categoryEn: 'Life',
    ),
    HabitTemplate(
      id: 'habit.laundry',
      name: '整理衣物',
      nameEn: 'Laundry reset',
      targetCount: 1,
      flexTarget: 2,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF03A9F4,
      icon: Icons.local_laundry_service,
      category: '生活习惯',
      categoryEn: 'Life',
    ),
    HabitTemplate(
      id: 'habit.meal_prep',
      name: '准备健康餐',
      nameEn: 'Meal prep',
      targetCount: 1,
      flexTarget: 3,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF4CAF50,
      icon: Icons.restaurant,
      category: '生活习惯',
      categoryEn: 'Life',
    ),
    HabitTemplate(
      id: 'habit.weekly_review_home',
      name: '家庭整理复盘',
      nameEn: 'Home weekly review',
      targetCount: 1,
      flexTarget: 1,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF795548,
      icon: Icons.home_repair_service,
      category: '生活习惯',
      categoryEn: 'Life',
    ),

    // 社交沟通
    HabitTemplate(
      id: 'habit.family_call',
      name: '联系家人',
      nameEn: 'Call family',
      targetCount: 1,
      flexTarget: 2,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFFE91E63,
      icon: Icons.family_restroom,
      category: '社交沟通',
      categoryEn: 'Social',
    ),
    HabitTemplate(
      id: 'habit.friend_message',
      name: '问候朋友',
      nameEn: 'Check in with a friend',
      targetCount: 1,
      flexTarget: 3,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF8BC34A,
      icon: Icons.chat_bubble_outline,
      category: '社交沟通',
      categoryEn: 'Social',
    ),
    HabitTemplate(
      id: 'habit.thank_you',
      name: '表达感谢',
      nameEn: 'Say thank you',
      targetCount: 1,
      colorValue: 0xFFFF9800,
      icon: Icons.volunteer_activism,
      category: '社交沟通',
      categoryEn: 'Social',
    ),
    HabitTemplate(
      id: 'habit.deep_talk',
      name: '深度交流',
      nameEn: 'Meaningful conversation',
      targetCount: 1,
      flexTarget: 1,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF673AB7,
      icon: Icons.groups,
      category: '社交沟通',
      categoryEn: 'Social',
    ),
    HabitTemplate(
      id: 'habit.no_late_reply',
      name: '及时回复消息',
      nameEn: 'Reply on time',
      targetCount: 1,
      colorValue: 0xFF00BCD4,
      icon: Icons.mark_chat_read,
      category: '社交沟通',
      categoryEn: 'Social',
    ),

    // 职业发展
    HabitTemplate(
      id: 'habit.work_plan',
      name: '工作日计划',
      nameEn: 'Plan workday',
      targetCount: 1,
      colorValue: 0xFF607D8B,
      icon: Icons.work,
      category: '职业发展',
      categoryEn: 'Career',
    ),
    HabitTemplate(
      id: 'habit.inbox_zero',
      name: '清理工作收件箱',
      nameEn: 'Clear work inbox',
      targetCount: 1,
      flexTarget: 5,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF2196F3,
      icon: Icons.mail_outline,
      category: '职业发展',
      categoryEn: 'Career',
    ),
    HabitTemplate(
      id: 'habit.skill_practice',
      name: '职业技能练习',
      nameEn: 'Career skill practice',
      targetCount: 1,
      flexTarget: 4,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF9C27B0,
      icon: Icons.trending_up,
      category: '职业发展',
      categoryEn: 'Career',
    ),
    HabitTemplate(
      id: 'habit.weekly_work_review',
      name: '工作周复盘',
      nameEn: 'Weekly work review',
      targetCount: 1,
      flexTarget: 1,
      flexPeriod: HabitFlexPeriod.week,
      colorValue: 0xFF3F51B5,
      icon: Icons.assignment_turned_in,
      category: '职业发展',
      categoryEn: 'Career',
    ),
    HabitTemplate(
      id: 'habit.networking',
      name: '职业连接',
      nameEn: 'Professional networking',
      targetCount: 1,
      flexTarget: 2,
      flexPeriod: HabitFlexPeriod.month,
      colorValue: 0xFFFF5722,
      icon: Icons.record_voice_over,
      category: '职业发展',
      categoryEn: 'Career',
    ),
  ];

  static Map<String, List<HabitTemplate>> get byCategory {
    final map = <String, List<HabitTemplate>>{};
    for (final t in all) {
      map.putIfAbsent(t.localizedCategory, () => []).add(t);
    }
    return map;
  }
}
