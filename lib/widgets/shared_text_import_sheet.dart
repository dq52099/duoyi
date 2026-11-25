import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import 'surface_components.dart';

/// Target destination choice when importing shared text.
enum SharedTextImportChoice { todo, note }

/// Modal bottom sheet content for importing text shared into the application.
///
/// Designed to be used as the builder child of [showAppModalSheet]:
/// ```dart
/// final choice = await showAppModalSheet<SharedTextImportChoice>(
///   context: context,
///   builder: (sheetContext) => SharedTextImportSheet(
///     text: sharedText,
///     canChoose: () => isAccountValid,
///   ),
/// );
/// ```
class SharedTextImportSheet extends StatefulWidget {
  final String text;
  final bool Function() canChoose;

  const SharedTextImportSheet({
    super.key,
    required this.text,
    required this.canChoose,
  });

  @override
  State<SharedTextImportSheet> createState() => _SharedTextImportSheetState();
}

class _SharedTextImportSheetState extends State<SharedTextImportSheet> {
  ModalRoute<dynamic>? _ownedRoute;
  NavigatorState? _ownedNavigator;
  late final ScrollController _previewScrollController;

  @override
  void initState() {
    super.initState();
    _previewScrollController = ScrollController();
    I18n.localeListenable.addListener(_handleLocaleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownedRoute = ModalRoute.of(context);
    _ownedNavigator = Navigator.maybeOf(context);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _previewScrollController.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _choose(SharedTextImportChoice? choice) {
    if (!mounted || !widget.canChoose()) {
      return;
    }
    final route = _ownedRoute ?? (mounted ? ModalRoute.of(context) : null);
    if (route == null || !route.isCurrent) {
      return;
    }
    final navigator =
        _ownedNavigator ?? (mounted ? Navigator.maybeOf(context) : null);
    if (navigator == null) {
      return;
    }
    navigator.pop<SharedTextImportChoice?>(choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);

    final isEn =
        I18n.current == AppLocale.en ||
        I18n.localeListenable.value == AppLocale.en;
    final title = isEn ? 'Import shared text' : '导入分享文本';
    final subtitle = isEn ? 'Choose where to save' : '选择保存位置';
    final createTaskLabel = isEn ? 'Create task' : '创建待办';
    final saveNoteLabel = isEn ? 'Save note' : '保存笔记';
    final cancelLabel = I18n.tr('action.cancel');

    final availableHeight = (media.size.height - media.viewInsets.bottom).clamp(
      0.0,
      media.size.height,
    );
    final maxPreviewHeight = (availableHeight * 0.32).clamp(96.0, 220.0);

    return AppModalSheet(
      title: title,
      subtitle: subtitle,
      actions: [
        TextButton(
          key: const ValueKey('shared_text_import_cancel_button'),
          onPressed: () => _choose(null),
          child: Text(
            cancelLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        OutlinedButton(
          key: const ValueKey('shared_text_import_note_button'),
          onPressed: () => _choose(SharedTextImportChoice.note),
          child: Text(
            saveNoteLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        FilledButton(
          key: const ValueKey('shared_text_import_todo_button'),
          onPressed: () => _choose(SharedTextImportChoice.todo),
          child: Text(
            createTaskLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      child: SizedBox(
        width: double.infinity,
        child: AppSurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: cs.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.35 : 0.45,
          ),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.16 : 0.22),
            width: 0.5,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPreviewHeight),
            child: Scrollbar(
              controller: _previewScrollController,
              child: SingleChildScrollView(
                controller: _previewScrollController,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    widget.text,
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .copyWith(
                          color: cs.onSurface,
                          fontSize: DesignTokens.fontSizeBase,
                          fontWeight: FontWeight.normal,
                          height: 1.45,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
