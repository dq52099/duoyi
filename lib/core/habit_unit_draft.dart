import 'package:flutter/widgets.dart';

/// Keeps semantic units separate from the editable, authored text. Locale
/// changes only rebuild hints; they never write into the controller or IME.
class HabitUnitDraft {
  final TextEditingController controller;
  String? _literal;
  String? _generatedKey;
  bool _edited = false;

  HabitUnitDraft({String? authoredUnit, String? generatedUnitKey})
    : controller = TextEditingController(text: authoredUnit ?? ''),
      _literal = authoredUnit,
      _generatedKey = generatedUnitKey;

  String? get authoredUnit => _edited
      ? (controller.text.trim().isEmpty ? null : controller.text.trim())
      : _literal;

  String? get generatedUnitKey => _edited ? null : _generatedKey;

  /// Only TextField.onChanged calls this, including an explicitly typed label
  /// equal to the generated hint. Programmatic selections do not call it.
  void recordEdit(String _) {
    _edited = true;
  }

  void selectGenerated(String? key) {
    _literal = null;
    _generatedKey = key;
    _edited = false;
    controller.clear();
  }

  void dispose() => controller.dispose();
}
