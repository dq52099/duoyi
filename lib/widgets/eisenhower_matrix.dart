import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../providers/theme_provider.dart';

class EisenhowerMatrix extends StatelessWidget {
  final Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups;
  final void Function(EisenhowerQuadrant) onQuadrantTap;

  const EisenhowerMatrix({super.key, required this.quadrantGroups, required this.onQuadrantTap});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _QuadrantCard(quadrant: EisenhowerQuadrant.urgentImportant, label: s.quadrantQ1Label, subLabel: s.quadrantQ1Sub, items: quadrantGroups[EisenhowerQuadrant.urgentImportant] ?? [], onTap: () => onQuadrantTap(EisenhowerQuadrant.urgentImportant))),
            const SizedBox(width: 8),
            Expanded(child: _QuadrantCard(quadrant: EisenhowerQuadrant.notUrgentImportant, label: s.quadrantQ2Label, subLabel: s.quadrantQ2Sub, items: quadrantGroups[EisenhowerQuadrant.notUrgentImportant] ?? [], onTap: () => onQuadrantTap(EisenhowerQuadrant.notUrgentImportant))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _QuadrantCard(quadrant: EisenhowerQuadrant.urgentNotImportant, label: s.quadrantQ3Label, subLabel: s.quadrantQ3Sub, items: quadrantGroups[EisenhowerQuadrant.urgentNotImportant] ?? [], onTap: () => onQuadrantTap(EisenhowerQuadrant.urgentNotImportant))),
            const SizedBox(width: 8),
            Expanded(child: _QuadrantCard(quadrant: EisenhowerQuadrant.notUrgentNotImportant, label: s.quadrantQ4Label, subLabel: s.quadrantQ4Sub, items: quadrantGroups[EisenhowerQuadrant.notUrgentNotImportant] ?? [], onTap: () => onQuadrantTap(EisenhowerQuadrant.notUrgentNotImportant))),
          ],
        ),
      ],
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  final EisenhowerQuadrant quadrant;
  final String label;
  final String subLabel;
  final List<TodoItem> items;
  final VoidCallback onTap;

  const _QuadrantCard({required this.quadrant, required this.label, required this.subLabel, required this.items, required this.onTap});

  Color _bgColor() {
    switch (quadrant) {
      case EisenhowerQuadrant.urgentImportant: return const Color(0xFFE53935);
      case EisenhowerQuadrant.notUrgentImportant: return const Color(0xFF1E88E5);
      case EisenhowerQuadrant.urgentNotImportant: return const Color(0xFFFFB300);
      case EisenhowerQuadrant.notUrgentNotImportant: return const Color(0xFF9E9E9E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bgColor();
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [bg.withValues(alpha: 0.15), bg.withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(top: BorderSide(color: bg, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: bg, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: bg.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                    child: Text('${items.length}', style: TextStyle(color: bg, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(subLabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...items.take(3).map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 6, color: bg.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Expanded(child: Text(t.title, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    )),
                if (items.length > 3)
                  Text('+${items.length - 3} 更多...', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}