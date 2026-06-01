import 'package:flutter/material.dart';

import '../models/habit.dart';

final Map<String, IconData> _habitIconsByToken = {
  defaultHabitIconToken: Icons.check_circle_outline,
  'check': Icons.check_circle_outline,
  'star': Icons.check_circle_outline,
  'water': Icons.local_drink,
  'local_drink': Icons.local_drink,
  'wb_sunny': Icons.wb_sunny,
  'run': Icons.directions_run,
  'directions_run': Icons.directions_run,
  'directions_walk': Icons.directions_walk,
  'book': Icons.book,
  'sleep': Icons.bedtime,
  'bedtime': Icons.bedtime,
  'meditation': Icons.self_improvement,
  'self_improvement': Icons.self_improvement,
  'code': Icons.code,
  'school': Icons.school,
  'fitness': Icons.fitness_center,
  'fitness_center': Icons.fitness_center,
  'mood': Icons.mood,
  'translate': Icons.translate,
  'edit_note': Icons.edit_note,
  'favorite': Icons.favorite,
  'air': Icons.air,
  'nightlight_round': Icons.nightlight_round,
  'account_balance_wallet': Icons.account_balance_wallet,
  'cleaning_services': Icons.cleaning_services,
  'local_laundry_service': Icons.local_laundry_service,
  'restaurant': Icons.restaurant,
  'home_repair_service': Icons.home_repair_service,
  'family_restroom': Icons.family_restroom,
  'chat_bubble_outline': Icons.chat_bubble_outline,
  'volunteer_activism': Icons.volunteer_activism,
  'groups': Icons.groups,
  'mark_chat_read': Icons.mark_chat_read,
  'work': Icons.work,
  'mail_outline': Icons.mail_outline,
  'trending_up': Icons.trending_up,
  'assignment_turned_in': Icons.assignment_turned_in,
  'record_voice_over': Icons.record_voice_over,
  'local_cafe_outlined': Icons.local_cafe_outlined,
  'timer': Icons.timer,
};

final Map<int, String> _habitIconTokensByCodePoint = {
  Icons.check_circle_outline.codePoint: defaultHabitIconToken,
  Icons.local_drink.codePoint: 'local_drink',
  Icons.wb_sunny.codePoint: 'wb_sunny',
  Icons.directions_run.codePoint: 'directions_run',
  Icons.directions_walk.codePoint: 'directions_walk',
  Icons.book.codePoint: 'book',
  Icons.bedtime.codePoint: 'bedtime',
  Icons.self_improvement.codePoint: 'self_improvement',
  Icons.code.codePoint: 'code',
  Icons.school.codePoint: 'school',
  Icons.fitness_center.codePoint: 'fitness_center',
  Icons.mood.codePoint: 'mood',
  Icons.translate.codePoint: 'translate',
  Icons.edit_note.codePoint: 'edit_note',
  Icons.favorite.codePoint: 'favorite',
  Icons.air.codePoint: 'air',
  Icons.nightlight_round.codePoint: 'nightlight_round',
  Icons.account_balance_wallet.codePoint: 'account_balance_wallet',
  Icons.cleaning_services.codePoint: 'cleaning_services',
  Icons.local_laundry_service.codePoint: 'local_laundry_service',
  Icons.restaurant.codePoint: 'restaurant',
  Icons.home_repair_service.codePoint: 'home_repair_service',
  Icons.family_restroom.codePoint: 'family_restroom',
  Icons.chat_bubble_outline.codePoint: 'chat_bubble_outline',
  Icons.volunteer_activism.codePoint: 'volunteer_activism',
  Icons.groups.codePoint: 'groups',
  Icons.mark_chat_read.codePoint: 'mark_chat_read',
  Icons.work.codePoint: 'work',
  Icons.mail_outline.codePoint: 'mail_outline',
  Icons.trending_up.codePoint: 'trending_up',
  Icons.assignment_turned_in.codePoint: 'assignment_turned_in',
  Icons.record_voice_over.codePoint: 'record_voice_over',
  Icons.local_cafe_outlined.codePoint: 'local_cafe_outlined',
  Icons.timer.codePoint: 'timer',
};

IconData habitIconForToken(String token) {
  final named = _habitIconsByToken[token];
  if (named != null) return named;

  final codePoint = int.tryParse(token);
  if (codePoint != null) {
    final legacyToken = _habitIconTokensByCodePoint[codePoint];
    if (legacyToken != null) return _habitIconsByToken[legacyToken]!;
  }

  return Icons.check_circle_outline;
}

String habitIconTokenForIcon(IconData icon) =>
    _habitIconTokensByCodePoint[icon.codePoint] ?? icon.codePoint.toString();
