import 'package:flutter/material.dart';

import '../core/date_item_ui_copy.dart';
import '../core/i18n.dart';
import '../core/account_preference_writes.dart';
import '../services/date_item_action_origin.dart';
import 'surface_components.dart';

/// Shares confirmed-write feedback while retaining each action's exact origin.
mixin DateItemMutationState<T extends StatefulWidget> on State<T> {
  bool dateItemBusy = false;
  bool _awaitingConfirmation = false;
  bool get dateItemWriting => dateItemBusy && !_awaitingConfirmation;
  String Function()? _error;
  VoidCallback? _retry;
  DateItemActionOrigin? _errorOrigin;
  DateItemOperation? _operation;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_localeChanged);
  }

  void _localeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> runDateItemMutation({
    required DateItemActionOrigin origin,
    required Future<void> Function(DateItemOperation) write,
    required String Function() failure,
    Future<bool> Function(DateItemOperation)? confirm,
    VoidCallback? onCommitted,
    VoidCallback? retry,
  }) async {
    if (!mounted || dateItemBusy || !origin.isCurrent()) return;
    final operation = DateItemOperation(origin);
    _operation = operation;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      dateItemBusy = true;
      _awaitingConfirmation = confirm != null;
      _error = null;
      _retry = null;
      _errorOrigin = null;
    });
    try {
      if (confirm != null && !await confirm(operation)) return;
      if (!operation.isCurrent()) return;
      setState(() => _awaitingConfirmation = false);
      await write(operation);
      if (operation.isCurrent()) onCommitted?.call();
    } on AccountPreferenceWriteCanceled {
      // The original route/account no longer owns this action.
    } catch (_) {
      if (!operation.isCurrent()) return;
      setState(() {
        _error = failure;
        _errorOrigin = origin;
        _retry =
            retry ??
            () => runDateItemMutation(
              origin: origin,
              write: write,
              failure: failure,
              confirm: confirm,
              onCommitted: onCommitted,
              retry: retry,
            );
      });
    } finally {
      operation.dispose();
      if (identical(_operation, operation)) _operation = null;
      if (mounted) setState(() => dateItemBusy = false);
    }
  }

  Widget dateItemStatus(Widget child, {bool showProgress = true}) {
    final showError = _errorOrigin?.isCurrent() ?? false;
    return DateItemMutationStatus(
      busy: dateItemBusy,
      showProgress: showProgress && dateItemWriting,
      error: showError ? _error : null,
      onRetry: showError ? _retry : null,
      child: child,
    );
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_localeChanged);
    _operation?.dispose();
    super.dispose();
  }
}

Future<bool> confirmDateItemDeletion(
  DateItemOperation operation,
  String title,
) async =>
    await operation.showDialog<bool>(
      (dialogContext) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (_, _, _) => AppDialog(
          icon: const Icon(Icons.delete_outline),
          title: Text(I18n.tr('anniversary.delete.title')),
          content: Text(
            '"$title" ${I18n.tr('anniversary.delete.content_suffix')}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (operation.isCurrent()) Navigator.pop(dialogContext, false);
              },
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () {
                if (operation.isCurrent()) Navigator.pop(dialogContext, true);
              },
              child: Text(I18n.tr('action.delete')),
            ),
          ],
        ),
      ),
    ) ==
    true;

class DateItemFeedbackText extends StatelessWidget {
  const DateItemFeedbackText(this.resolve, {super.key, this.style});
  final String Function() resolve;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (_, _, _) => Text(resolve(), style: style),
  );
}

/// Retains the item and gives a failed management action its own retry target.
class DateItemMutationStatus extends StatelessWidget {
  const DateItemMutationStatus({
    super.key,
    required this.child,
    required this.busy,
    this.showProgress = true,
    this.error,
    this.onRetry,
  });
  final Widget child;
  final bool busy;
  final bool showProgress;
  final String Function()? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      AbsorbPointer(absorbing: busy, child: child),
      if (busy && showProgress) ...[
        Semantics(
          liveRegion: true,
          child: DateItemFeedbackText(() => DateItemUiCopy.saving),
        ),
        const SizedBox(height: 4),
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 12),
      ],
      if (!busy && error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: DateItemFeedbackText(
                  error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onRetry,
                  child: DateItemFeedbackText(() => I18n.tr('action.retry')),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
