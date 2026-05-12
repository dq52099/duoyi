import 'package:flutter/material.dart';
import 'surface_components.dart';

class StatsOverviewCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const StatsOverviewCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppMetricCard(
      title: title,
      value: value,
      icon: icon,
      color: color,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
    );
  }
}
