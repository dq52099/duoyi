import 'app_date_format.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/smart_date_parser.dart';
import 'surface_components.dart';

/// Keeps the draft open through permission waits and unsuccessful saves.
class WidgetQuickTodoDialog extends StatefulWidget {
  const WidgetQuickTodoDialog({
    super.key,
    required this.canSubmit,
    required this.onSubmit,
  });

  final bool Function() canSubmit;
  final Future<bool> Function(String) onSubmit;

  @override
  State<WidgetQuickTodoDialog> createState() => _WidgetQuickTodoDialogState();
}

class _WidgetQuickTodoDialogState extends State<WidgetQuickTodoDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  SmartDateParseResult _parsed = SmartDateParseResult.empty;
  bool _saving = false;

  bool get _isCurrent => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isCurrent || _saving || !widget.canSubmit()) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    setState(() => _saving = true);
    try {
      final saved = await widget.onSubmit(text);
      if (!mounted) return;
      if (saved && navigator.mounted && route.isActive) {
        // The accepted write may finish under a lock or another route. Remove
        // only this form; never pop the newer route above it.
        navigator.removeRoute(route, true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, locale, _) {
      final isEnglish = locale == AppLocale.en;
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final dialogSurface = theme.dialogTheme.backgroundColor ?? cs.surface;
      final primaryColor = _resolveAccessiblePrimary(
        cs,
        dialogSurface,
        isDark: theme.brightness == Brightness.dark,
      );
      final viewInsets = MediaQuery.viewInsetsOf(context);
      return PopScope(
        canPop: !_saving,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: AppDialog(
            shiftForKeyboard: false,
            icon: const Icon(Icons.add_task_outlined),
            title: Text(isEnglish ? 'Quick task' : '快速待办'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  readOnly: _saving,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: isEnglish
                        ? 'Describe your task and its date'
                        : '一句话描述（如：明天下午3点开会）',
                  ),
                  onChanged: (value) => setState(() {
                    _parsed = SmartDateParser.parse(value);
                  }),
                  onSubmitted: (_) => _submit(),
                ),
                if (_parsed.isSuccess) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${isEnglish ? 'Detected' : '识别到'}: ${AppDateFormat.smartDate(context, _parsed.dateTime!, includeTime: _parsed.hasTimeOfDay)}',
                          style: TextStyle(fontSize: 12, color: primaryColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: primaryColor),
                onPressed: _saving
                    ? null
                    : () {
                        if (_isCurrent) Navigator.of(context).pop(false);
                      },
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(I18n.tr('action.add')),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Color _resolveAccessiblePrimary(
  ColorScheme cs,
  Color surface, {
  required bool isDark,
}) {
  final effectiveSurface = surface.a < 1.0
      ? Color.alphaBlend(surface, cs.surface)
      : surface;
  final effectivePrimary = Color.alphaBlend(cs.primary, effectiveSurface);
  if (appContrastRatio(effectiveSurface, effectivePrimary) >= 4.5) {
    return cs.primary;
  }
  final target = isDark ? Colors.white : const Color(0xFF111827);
  for (var t = 0.05; t <= 0.90; t += 0.05) {
    final candidate = Color.lerp(cs.primary, target, t) ?? cs.primary;
    final effectiveCandidate = Color.alphaBlend(candidate, effectiveSurface);
    if (appContrastRatio(effectiveSurface, effectiveCandidate) >= 4.5) {
      return candidate;
    }
  }
  return appReadableForeground(effectiveSurface, cs.primary);
}
