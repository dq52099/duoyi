import 'package:flutter/material.dart';
import 'surface_components.dart';

class StatsOverviewCard extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final int? titleMaxLines;

  const StatsOverviewCard({
    super.key,
    required this.title,
    required this.value,
    this.unit,
    required this.icon,
    required this.color,
    this.titleMaxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return AppMetricCard(
      title: title,
      value: value,
      unit: unit,
      icon: icon,
      color: color,
      titleMaxLines: titleMaxLines,
      padding: const EdgeInsets.all(10),
    );
  }
}
