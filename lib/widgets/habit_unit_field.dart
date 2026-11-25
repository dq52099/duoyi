import 'package:flutter/material.dart';

import '../core/habit_ui_copy.dart';
import '../core/habit_unit_draft.dart';
import '../core/i18n.dart';

class HabitUnitField extends StatelessWidget {
  final HabitUnitDraft draft;
  final TextEditingController targetController;
  final AppLocale locale;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final int? maximumTarget;

  const HabitUnitField({
    super.key,
    required this.draft,
    required this.targetController,
    required this.locale,
    required this.enabled,
    required this.onChanged,
    this.maximumTarget,
  });

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: targetController,
        builder: (context, target, _) {
          final parsed = int.tryParse(target.text.trim()) ?? 1;
          final normalized = parsed < 1
              ? 1
              : maximumTarget != null && parsed > maximumTarget!
              ? maximumTarget!
              : parsed;
          return TextField(
            controller: draft.controller,
            enabled: enabled,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: I18n.trForLocale('habit.field.unit', locale),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              hintText: draft.authoredUnit == null
                  ? HabitUiCopy.measurementUnit(
                      normalized,
                      generatedUnitKey: draft.generatedUnitKey,
                      locale: locale,
                    )
                  : null,
            ),
          );
        },
      );
}
