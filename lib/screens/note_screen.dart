import '../widgets/app_date_format.dart';
import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../core/desktop_tokens.dart';
import '../desktop_web/desktop_embedded_scope.dart';
import '../core/i18n.dart';
import '../core/image_decode_cache.dart';
import '../core/account_preference_writes.dart';
import '../core/note_editor_ui_copy.dart';
import '../providers/auth_provider.dart';
import '../providers/app_lock_provider.dart';
import '../services/app_update_service.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_access_route_gate.dart';
import '../services/note_editor_origin.dart';
import '../providers/note_provider.dart';
import '../models/note.dart';
import '../services/note_attachment_picker.dart';
import '../services/web_file_download.dart';
import '../widgets/empty_state.dart';
import '../widgets/controller_dialog.dart' show createControllerDialogRoute;
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

enum _NoteLibraryView { active, archived }

enum _NoteCardAction { pin, unpin, archive, restore, exportMarkdown, delete }

enum _NoteSortOrder { updatedDesc, createdDesc, titleAsc }

class NoteScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  final String? initialNoteId;

  const NoteScreen({super.key, this.initialNoteId});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final _searchCtrl = TextEditingController();
  final _pendingActions = <String, NoteEditorOperation>{};
  final _failedActions = <String, _NoteActionFailure>{};
  _NoteLibraryView _view = _NoteLibraryView.active;
  _NoteSortOrder _sortOrder = _NoteSortOrder.updatedDesc;
  String? _selectedFolder;
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_refresh);
    final initialId = widget.initialNoteId;
    if (initialId != null && initialId.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final provider = context.read<NoteProvider>();
        final target = provider.notes
            .where((n) => n.id == initialId)
            .firstOrNull;
        if (target != null &&
            target.archived &&
            _view != _NoteLibraryView.archived) {
          setState(() => _view = _NoteLibraryView.archived);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final operation in _pendingActions.values) {
      operation.dispose();
    }
    _pendingActions.clear();
    _searchCtrl.removeListener(_refresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) => _buildLocalized(context),
  );

  Widget _buildLocalized(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final origin = NoteEditorOrigin.capture(context);
    final allFolders = <String>{
      for (final note in provider.notes)
        if (note.folder != null && note.folder!.trim().isNotEmpty)
          note.folder!.trim(),
    }.toList()..sort();
    final allTags = <String>{
      for (final note in provider.notes) ...note.tags,
    }.toList()..sort();
    final notes = _filterNotes(
      _view == _NoteLibraryView.active
          ? provider.activeNotes
          : provider.archivedNotes,
      _searchCtrl.text,
    );
    final hasAnyNotes = provider.notes.isNotEmpty;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final isEn = I18n.current == AppLocale.en;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(I18n.tr('note.title')),
        actions: [
          PopupMenuButton<_NoteSortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: isEn ? 'Sort notes' : '排序方式',
            initialValue: _sortOrder,
            onSelected: (next) {
              if (mounted && origin.isCurrent()) {
                setState(() => _sortOrder = next);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _NoteSortOrder.updatedDesc,
                child: AppSecondaryMenuText(
                  isEn ? 'Recently updated' : '最近更新',
                ),
              ),
              PopupMenuItem(
                value: _NoteSortOrder.createdDesc,
                child: AppSecondaryMenuText(
                  isEn ? 'Created date' : '创建时间',
                ),
              ),
              PopupMenuItem(
                value: _NoteSortOrder.titleAsc,
                child: AppSecondaryMenuText(
                  isEn ? 'Title A–Z' : '标题排序',
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: I18n.tr('note.archived'),
            onPressed: () {
              if (!mounted || !origin.isCurrent()) return;
              setState(() {
                _view = _view == _NoteLibraryView.active
                    ? _NoteLibraryView.archived
                    : _NoteLibraryView.active;
              });
            },
          ),
        ],
      ),
      body: !hasAnyNotes
          ? EmptyState(
              icon: Icons.edit_note,
              message: I18n.tr('note.empty.message'),
              actionLabel: I18n.tr('note.empty.action'),
              onAction: () => _openEditor(origin),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopTokens.secondaryMaxContentWidth,
                ),
                child: Column(
                  children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: AppSecondaryControlTheme(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchCtrl.text.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: I18n.tr('note.search.clear'),
                                onPressed: () {
                                  if (mounted && origin.isCurrent()) {
                                    _searchCtrl.clear();
                                  }
                                },
                              ),
                        hintText: I18n.tr('note.search.hint'),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final labels = [
                        '${I18n.tr('note.active')} ${provider.activeNotes.length}',
                        '${I18n.tr('note.archived')} ${provider.archivedNotes.length}',
                      ];
                      final theme = Theme.of(context);
                      final style = theme.segmentedButtonTheme.style;
                      const states = <WidgetState>{};
                      final labelStyle =
                          style?.textStyle?.resolve(states) ??
                          theme.textTheme.labelLarge;
                      final textDirection = Directionality.of(context);
                      var widestLabel = 0.0;
                      for (final label in labels) {
                        final painter = TextPainter(
                          text: TextSpan(text: label, style: labelStyle),
                          textDirection: textDirection,
                          textScaler: MediaQuery.textScalerOf(context),
                          maxLines: 1,
                        )..layout();
                        widestLabel = math.max(widestLabel, painter.width);
                        painter.dispose();
                      }
                      final padding =
                          (style?.padding?.resolve(states) ??
                                  const EdgeInsets.symmetric(horizontal: 16))
                              .resolve(textDirection);
                      final iconSize = style?.iconSize?.resolve(states) ?? 24;
                      // Leave room for the icon, its gap and button padding.
                      final segmentWidth =
                          widestLabel + iconSize + padding.horizontal + 12;
                      final direction =
                          segmentWidth * labels.length > constraints.maxWidth
                          ? Axis.vertical
                          : Axis.horizontal;
                      return SegmentedButton<_NoteLibraryView>(
                        direction: direction,
                        segments: [
                          ButtonSegment(
                            value: _NoteLibraryView.active,
                            icon: const Icon(Icons.notes_outlined),
                            label: Text(labels[0]),
                          ),
                          ButtonSegment(
                            value: _NoteLibraryView.archived,
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: Text(labels[1]),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (selected) {
                          if (mounted && origin.isCurrent()) {
                            setState(() => _view = selected.single);
                          }
                        },
                      );
                    },
                  ),
                ),
                if (allFolders.isNotEmpty || allTags.isNotEmpty)
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                      children: [
                        if (_selectedFolder != null || _selectedTag != null) ...[
                          ActionChip(
                            key: const ValueKey('note_filter_clear'),
                            avatar: const Icon(Icons.clear_all, size: 16),
                            label: Text(isEn ? 'All' : '全部'),
                            onPressed: () {
                              if (mounted && origin.isCurrent()) {
                                setState(() {
                                  _selectedFolder = null;
                                  _selectedTag = null;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        for (final folder in allFolders) ...[
                          FilterChip(
                            key: ValueKey('note_folder_filter_$folder'),
                            avatar: const Icon(Icons.folder_outlined, size: 15),
                            selected: _selectedFolder == folder,
                            label: Text(folder),
                            onSelected: (selected) {
                              if (mounted && origin.isCurrent()) {
                                setState(
                                  () => _selectedFolder =
                                      selected ? folder : null,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        for (final tag in allTags) ...[
                          FilterChip(
                            key: ValueKey('note_tag_filter_$tag'),
                            avatar: const Icon(Icons.label_outline, size: 15),
                            selected: _selectedTag == tag,
                            label: Text('#$tag'),
                            onSelected: (selected) {
                              if (mounted && origin.isCurrent()) {
                                setState(
                                  () => _selectedTag = selected ? tag : null,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                Expanded(
                  child: notes.isEmpty
                      ? _FilteredNotesEmptyState(
                          archived: _view == _NoteLibraryView.archived,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                          itemCount: notes.length,
                          itemBuilder: (context, index) {
                            final note = notes[index];
                            return Dismissible(
                              key: ValueKey('${_view.name}-${note.id}'),
                              direction: _pendingActions.containsKey(note.id)
                                  ? DismissDirection.none
                                  : DismissDirection.endToStart,
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: _view == _NoteLibraryView.active
                                      ? cs.tertiary
                                      : cs.primary,
                                  borderRadius: BorderRadius.circular(
                                    appSurfaceStyleOf(context)?.cardRadius ??
                                        DesignTokens.radiusCard,
                                  ),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: Icon(
                                  _view == _NoteLibraryView.active
                                      ? Icons.archive_outlined
                                      : Icons.unarchive_outlined,
                                  color: appReadableForeground(
                                    _view == _NoteLibraryView.active
                                        ? cs.tertiary
                                        : cs.primary,
                                    _view == _NoteLibraryView.active
                                        ? cs.onTertiary
                                        : cs.onPrimary,
                                  ),
                                ),
                              ),
                              confirmDismiss: (_) async {
                                if (!mounted ||
                                    _pendingActions.containsKey(note.id) ||
                                    !origin.isCurrent()) {
                                  return false;
                                }
                                await _runNoteAction(
                                  origin,
                                  note.id,
                                  _view == _NoteLibraryView.active
                                      ? _NoteCardAction.archive
                                      : _NoteCardAction.restore,
                                );
                                // The provider owns removal; never retain a
                                // dismissed widget when the source expires.
                                return false;
                              },
                              child: _NoteListCard(
                                note: note,
                                archived: _view == _NoteLibraryView.archived,
                                busy: _pendingActions.containsKey(note.id),
                                highlighted: widget.initialNoteId == note.id,
                                failure: _failureFor(note.id, origin),
                                onOpen: () => _openEditor(origin, note),
                                onRetry: () => _retryNoteAction(origin, note),
                                onAction: (action) =>
                                    _runNoteAction(origin, note.id, action),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'note_add_fab',
        onPressed: () => _openEditor(origin),
        child: const Icon(Icons.edit),
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  void _openEditor(NoteEditorOrigin origin, [NoteItem? note]) {
    if (!mounted ||
        !origin.isCurrent() ||
        (note != null && _pendingActions.containsKey(note.id))) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => NoteEditScreen(note: note)),
    );
  }

  List<NoteItem> _filterNotes(List<NoteItem> notes, String query) {
    final q = query.trim().toLowerCase();
    final filtered = notes
        .where((note) {
          if (_selectedFolder != null && note.folder != _selectedFolder) {
            return false;
          }
          if (_selectedTag != null && !note.tags.contains(_selectedTag)) {
            return false;
          }
          if (q.isEmpty) return true;
          return note.title.toLowerCase().contains(q) ||
              note.content.toLowerCase().contains(q) ||
              (note.folder?.toLowerCase().contains(q) ?? false) ||
              note.tags.any((tag) => tag.toLowerCase().contains(q)) ||
              note.attachments.any(
                (attachment) =>
                    attachment.name.toLowerCase().contains(q) ||
                    attachment.uri.toLowerCase().contains(q),
              );
        })
        .toList(growable: false);
    if (_sortOrder == _NoteSortOrder.updatedDesc) return filtered;
    final sorted = [...filtered];
    sorted.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return switch (_sortOrder) {
        _NoteSortOrder.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
        _NoteSortOrder.createdDesc => b.createdAt.compareTo(a.createdAt),
        _NoteSortOrder.titleAsc => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
      };
    });
    return sorted;
  }

  Future<void> _exportNoteAsMarkdown(
    NoteEditorOrigin origin,
    NoteItem note,
  ) async {
    final title = note.titleFor(I18n.current).trim();
    final base = title.isEmpty ? 'duoyi_note' : title;
    final rawName = base.toLowerCase().endsWith('.md') ? base : '$base.md';
    final fileName = WebFileDownload.sanitizeFileName(
      rawName,
      fallback: 'duoyi_note.md',
    );
    try {
      final result = await WebFileDownload.saveText(
        content: note.toMarkdownDocument(I18n.current),
        fileName: fileName,
        mimeType: 'text/markdown;charset=utf-8',
        shareSubject: note.titleFor(I18n.current),
        canProceed: () => mounted && origin.isCurrent(),
      );
      if (!mounted || !origin.isCurrent() || !result.saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.current == AppLocale.en
                ? 'Exported Markdown: $fileName'
                : '已导出 Markdown：$fileName',
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !origin.isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.current == AppLocale.en
                ? 'Failed to export Markdown file.'
                : '导出 Markdown 文件失败，请重试',
          ),
        ),
      );
    }
  }

  Future<void> _runNoteAction(
    NoteEditorOrigin origin,
    String id,
    _NoteCardAction action,
  ) async {
    if (!mounted || !origin.isCurrent()) return;
    if (action == _NoteCardAction.exportMarkdown) {
      final target = origin.provider.notes
          .where((note) => note.id == id)
          .firstOrNull;
      if (target != null) {
        await _exportNoteAsMarkdown(origin, target);
      }
      return;
    }
    if (_pendingActions.containsKey(id)) {
      return;
    }
    final operation = NoteEditorOperation(origin);
    if (!operation.isCurrent()) {
      operation.dispose();
      return;
    }
    setState(() {
      _pendingActions[id] = operation;
      _failedActions.remove(id);
    });
    try {
      final value = switch (action) {
        _NoteCardAction.pin || _NoteCardAction.archive => true,
        _NoteCardAction.unpin || _NoteCardAction.restore => false,
        _NoteCardAction.exportMarkdown || _NoteCardAction.delete => null,
      };
      await _persistNoteAction(operation, id, action, value);
    } finally {
      operation.dispose();
      if (mounted && identical(_pendingActions[id], operation)) {
        setState(() => _pendingActions.remove(id));
      }
    }
  }

  _NoteActionFailure? _failureFor(String id, NoteEditorOrigin origin) {
    final failure = _failedActions[id];
    if (failure == null ||
        !identical(failure.origin.provider, origin.provider) ||
        !failure.origin.isCurrent(checkRoute: false)) {
      return null;
    }
    return failure;
  }

  Future<void> _persistNoteAction(
    NoteEditorOperation operation,
    String id,
    _NoteCardAction action,
    bool? value,
  ) async {
    try {
      if (action == _NoteCardAction.delete) {
        await operation.origin.provider.deleteNotePersisted(
          id,
          canWrite: operation.isCurrent,
        );
      } else if (action == _NoteCardAction.pin ||
          action == _NoteCardAction.unpin) {
        await operation.origin.provider.setPinnedPersisted(
          id,
          value!,
          canWrite: operation.isCurrent,
        );
      } else {
        await operation.origin.provider.setArchivedPersisted(
          id,
          value!,
          canWrite: operation.isCurrent,
        );
      }
    } on AccountPreferenceWriteCanceled {
      // An expired page or account cannot report a result to this screen.
    } catch (_) {
      if (!mounted || !operation.isCurrent()) return;
      setState(() {
        _failedActions[id] = _NoteActionFailure(action, operation.origin);
      });
    }
  }

  void _retryNoteAction(NoteEditorOrigin origin, NoteItem note) {
    final failure = _failureFor(note.id, origin);
    if (failure == null) return;
    unawaited(_runNoteAction(origin, note.id, failure.action));
  }
}

class _FilteredNotesEmptyState extends StatelessWidget {
  final bool archived;

  const _FilteredNotesEmptyState({required this.archived});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              archived ? Icons.inventory_2_outlined : Icons.search_off_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              archived
                  ? I18n.tr('note.archived.empty')
                  : I18n.tr('note.search.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteActionFailure {
  const _NoteActionFailure(this.action, this.origin);

  final _NoteCardAction action;
  final NoteEditorOrigin origin;
}

class _NoteListCard extends StatelessWidget {
  final NoteItem note;
  final bool archived;
  final bool busy;
  final bool highlighted;
  final _NoteActionFailure? failure;
  final VoidCallback onOpen;
  final VoidCallback onRetry;
  final ValueChanged<_NoteCardAction> onAction;

  const _NoteListCard({
    required this.note,
    required this.archived,
    required this.busy,
    this.highlighted = false,
    required this.failure,
    required this.onOpen,
    required this.onRetry,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(
        surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
      ),
      border: highlighted
          ? Border.all(color: cs.primary, width: 0.6)
          : note.pinned
          ? Border.all(
              color: cs.primary.withValues(alpha: 0.28),
              width: 0.5,
            )
          : null,
      onTap: busy ? null : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.pinned) ...[
                Icon(Icons.push_pin, size: 18, color: cs.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  note.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (busy)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: NoteEditorUiCopy.saving,
                    ),
                  ),
                )
              else
                PopupMenuButton<_NoteCardAction>(
                  tooltip: I18n.tr('note.more'),
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    if (!archived)
                      PopupMenuItem(
                        value: note.pinned
                            ? _NoteCardAction.unpin
                            : _NoteCardAction.pin,
                        child: ListTile(
                          leading: Icon(
                            note.pinned
                                ? Icons.push_pin_outlined
                                : Icons.push_pin,
                          ),
                          title: AppSecondaryMenuText(
                            note.pinned
                                ? I18n.tr('note.unpin')
                                : I18n.tr('note.pin'),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    PopupMenuItem(
                      value: archived
                          ? _NoteCardAction.restore
                          : _NoteCardAction.archive,
                      child: ListTile(
                        leading: Icon(
                          archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        title: AppSecondaryMenuText(
                          archived
                              ? I18n.tr('note.restore')
                              : I18n.tr('note.archive'),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _NoteCardAction.exportMarkdown,
                      child: ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: AppSecondaryMenuText(
                          I18n.current == AppLocale.en
                              ? 'Export .md'
                              : '导出 .md 文件',
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _NoteCardAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: cs.error),
                        title: AppSecondaryMenuText(
                          I18n.tr('action.delete'),
                          color: cs.error,
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (note.preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note.preview,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (failure != null) ...[
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  I18n.tr('note.action.failed'),
                  style: TextStyle(color: cs.error, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(I18n.tr('action.retry')),
                  ),
                ),
              ],
            ),
          ],
          if (note.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final attachment in note.attachments.take(3))
                  _AttachmentChip(attachment: attachment, compact: true),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (note.folder != null)
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 14,
                      color: cs.primary,
                    ),
                    Text(
                      note.folder!,
                      style: TextStyle(fontSize: 11, color: cs.primary),
                    ),
                  ],
                ),
              for (final tag in note.tags.take(3))
                Text(
                  '#$tag',
                  style: TextStyle(fontSize: 11, color: cs.secondary),
                ),
              if (note.tags.length > 3)
                Text(
                  '+${note.tags.length - 3}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (archived)
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 14,
                      color: cs.primary,
                    ),
                    Text(
                      I18n.tr('note.archived'),
                      style: TextStyle(fontSize: 11, color: cs.primary),
                    ),
                  ],
                ),
              Text(
                AppDateFormat.fullDateTime(context, note.updatedAt),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NoteEditScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final NoteItem? note;
  const NoteEditScreen({super.key, this.note});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late _MarkdownEditingController _ctrl;
  late List<NoteAttachment> _attachments;
  late List<String> _tags;
  String? _folder;
  late final String _draftId;
  late final DateTime _draftCreatedAt;
  bool _hasCommitted = false;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _ctrl = _MarkdownEditingController(text: widget.note?.content ?? '');
    _attachments = [...?widget.note?.attachments];
    _tags = [...?widget.note?.tags];
    _folder = widget.note?.folder;
    _draftId = widget.note?.id ?? const Uuid().v4();
    _draftCreatedAt = widget.note?.createdAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _operation?.dispose();
    for (final notifier in _origin?.notifiers ?? <ChangeNotifier>[]) {
      notifier.removeListener(_sourceChanged);
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _sourceChanged,
    );
    for (final gate in _gates) {
      gate.routeRevision.removeListener(_sourceChanged);
    }
    _ctrl.dispose();
    super.dispose();
  }

  NoteEditorOrigin? _origin;
  NoteEditorOperation? _operation;
  final _gates = <AppAccessRouteGate>[];
  bool _saving = false;
  bool _choosingAttachment = false;
  bool _expired = false;
  bool _rebuildScheduled = false;
  int _revision = 0;
  _NoteEditorFeedback? _feedback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_origin != null) {
      _sourceChanged();
      return;
    }
    _origin = NoteEditorOrigin.capture(context);
    for (final notifier in _origin!.notifiers) {
      notifier.addListener(_sourceChanged);
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _sourceChanged,
    );
    for (final observer in Navigator.of(context).widget.observers) {
      if (observer is AppAccessRouteGate) {
        _gates.add(observer);
        observer.routeRevision.addListener(_sourceChanged);
      }
    }
  }

  void _sourceChanged() {
    _revision++;
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    void rebuild() {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    }

    scheduleMicrotask(() {
      if (!mounted) return;
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => rebuild());
      } else {
        rebuild();
      }
    });
  }

  bool _canAct(int revision) =>
      mounted &&
      !_expired &&
      revision == _revision &&
      _origin?.isCurrent() == true;

  NoteEditorOperation? _begin(
    int revision, {
    bool saving = false,
    bool choosingAttachment = false,
  }) {
    if (_operation != null || !_canAct(revision)) return null;
    final operation = NoteEditorOperation(_origin!);
    if (!operation.isCurrent()) {
      operation.dispose();
      return null;
    }
    setState(() {
      _operation = operation;
      _saving = saving;
      _choosingAttachment = choosingAttachment;
      _feedback = null;
    });
    return operation;
  }

  void _end(NoteEditorOperation operation) {
    operation.dispose();
    if (mounted && identical(_operation, operation)) {
      setState(() {
        _operation = null;
        _saving = false;
        _choosingAttachment = false;
      });
    }
  }

  Future<void> _saveAndPop(int revision) async {
    final operation = _begin(revision, saving: true);
    if (operation == null) return;
    try {
      final text = _ctrl.text.trim();
      if (text.isNotEmpty || _attachments.isNotEmpty) {
        final now = DateTime.now();
        await _origin!.provider.addOrUpdateNotePersisted(
          NoteItem(
            id: _draftId,
            content: text,
            format: 'markdown',
            blocks: NoteBlock.fromMarkdown(text),
            attachments: List.unmodifiable(_attachments),
            tags: List.unmodifiable(_tags),
            folder: _folder,
            pinned: widget.note?.pinned ?? false,
            archived: widget.note?.archived ?? false,
            createdAt: _draftCreatedAt,
            updatedAt: now,
          ),
          canWrite: operation.isCurrent,
        );
        _hasCommitted = true;
      } else if (widget.note != null || _hasCommitted) {
        await _origin!.provider.deleteNotePersisted(
          _draftId,
          canWrite: operation.isCurrent,
        );
      }
      if (mounted && operation.isCurrent()) Navigator.of(context).pop();
    } on AccountPreferenceWriteCanceled {
      // An expired account, route or access source cannot finish this form.
    } catch (_) {
      if (mounted && operation.isCurrent()) {
        setState(() => _feedback = _NoteEditorFeedback.saveFailed);
      }
    } finally {
      _end(operation);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) => _buildLocalized(context),
  );

  Widget _buildLocalized(BuildContext context) {
    context.watch<NoteProvider>();
    context.watch<AuthProvider?>();
    context.watch<AppLockProvider?>();
    context.watch<AppUpdateService?>();
    if (!_expired &&
        _origin?.isCurrent(checkRoute: false, checkAccess: false) != true) {
      _expired = true;
      _sourceChanged();
    }
    final revision = _revision;
    final enabled = _canAct(revision) && _operation == null;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(I18n.tr('note.edit.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        actions: [
          IconButton(
            key: const ValueKey('note-editor-export-md'),
            icon: const Icon(Icons.download_outlined),
            tooltip: I18n.current == AppLocale.en
                ? 'Export .md'
                : '导出 .md 文件',
            onPressed: enabled ? () => _exportCurrentMarkdown(revision) : null,
          ),
          IconButton(
            icon: Icon(
              _preview ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
            tooltip: _preview ? I18n.tr('note.edit') : I18n.tr('note.preview'),
            onPressed: enabled
                ? () {
                    if (_canAct(revision) && _operation == null) {
                      setState(() => _preview = !_preview);
                    }
                  }
                : null,
          ),
          IconButton(
            key: const ValueKey('note-editor-save'),
            tooltip: _saving ? NoteEditorUiCopy.saving : I18n.tr('action.save'),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: enabled ? () => _saveAndPop(revision) : null,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: SizedBox(
            height: math.max(400, constraints.maxHeight),
            child: Column(
              children: [
                if (_expired)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(NoteEditorUiCopy.expired),
                        TextButton(
                          onPressed: () {
                            if (!mounted ||
                                revision != _revision ||
                                _origin?.route?.isCurrent != true ||
                                !identical(
                                  ModalRoute.of(context),
                                  _origin?.route,
                                ) ||
                                context.read<AppLockProvider?>()?.isLocked ==
                                    true ||
                                context.read<AppUpdateService?>()?.mustUpdate ==
                                    true) {
                              return;
                            }
                            Navigator.of(context).maybePop();
                          },
                          child: Text(NoteEditorUiCopy.back),
                        ),
                      ],
                    ),
                  ),
                if (!_expired && _feedback != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(switch (_feedback!) {
                      _NoteEditorFeedback.saveFailed =>
                        NoteEditorUiCopy.saveFailed,
                      _NoteEditorFeedback.attachmentFailed =>
                        NoteEditorUiCopy.attachmentFailed,
                      _NoteEditorFeedback.openFailed =>
                        NoteEditorUiCopy.openFailed,
                    }, key: const ValueKey('note-editor-feedback')),
                  ),
                AbsorbPointer(
                  absorbing: !enabled,
                  child: _NoteFormatToolbar(
                    onHeading: () {
                      if (_canAct(revision) && _operation == null) {
                        _insertPrefix('# ');
                      }
                    },
                    onBold: () {
                      if (_canAct(revision) && _operation == null) {
                        _wrapSelection('**');
                      }
                    },
                    onItalic: () {
                      if (_canAct(revision) && _operation == null) {
                        _wrapSelection('*');
                      }
                    },
                    onQuote: () {
                      if (_canAct(revision) && _operation == null) {
                        _insertPrefix('> ');
                      }
                    },
                    onBullet: () {
                      if (_canAct(revision) && _operation == null) {
                        _insertPrefix('- ');
                      }
                    },
                    onChecklist: () {
                      if (_canAct(revision) && _operation == null) {
                        _insertPrefix('- [ ] ');
                      }
                    },
                    onCode: () {
                      if (_canAct(revision) && _operation == null) {
                        _wrapSelection('`');
                      }
                    },
                    onLink: () {
                      if (_canAct(revision) && _operation == null) {
                        _insertLink();
                      }
                    },
                    onAttachment: () => _addAttachment(revision),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: AbsorbPointer(
                    absorbing: !enabled,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ActionChip(
                            key: const ValueKey('note-editor-folder-chip'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            avatar: const Icon(Icons.folder_outlined, size: 15),
                            label: Text(
                              _folder ??
                                  (I18n.current == AppLocale.en
                                      ? 'Notebook'
                                      : '笔记本'),
                            ),
                            onPressed: () => _editFolderDialog(revision),
                          ),
                          for (final tag in _tags)
                            InputChip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              label: Text('#$tag'),
                              onDeleted: enabled
                                  ? () {
                                      if (_canAct(revision) &&
                                          _operation == null) {
                                        setState(() => _tags.remove(tag));
                                      }
                                    }
                                  : null,
                            ),
                          ActionChip(
                            key: const ValueKey('note-editor-add-tag-chip'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            avatar: const Icon(Icons.label_outline, size: 15),
                            label: Text(
                              I18n.current == AppLocale.en ? '+ Tag' : '+ 标签',
                            ),
                            onPressed: () => _addTagDialog(revision),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_operation != null && _choosingAttachment)
                  LinearProgressIndicator(
                    semanticsLabel: NoteEditorUiCopy.choosingAttachment,
                  ),
                if (_attachments.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 96),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final attachment in _attachments)
                              _AttachmentChip(
                                attachment: attachment,
                                canOpen: () =>
                                    _canAct(revision) && _operation == null,
                                onOpenFailed: () {
                                  if (_canAct(revision) && _operation == null) {
                                    setState(
                                      () => _feedback =
                                          _NoteEditorFeedback.openFailed,
                                    );
                                  }
                                },
                                onDeleted: enabled
                                    ? () {
                                        if (_canAct(revision) &&
                                            _operation == null) {
                                          setState(
                                            () =>
                                                _attachments.remove(attachment),
                                          );
                                        }
                                      }
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _preview
                        ? _MarkdownPreview(
                            content: _ctrl.text,
                            blocks: NoteBlock.fromMarkdown(_ctrl.text),
                            attachments: _attachments,
                            onToggleChecklist: enabled
                                ? (index) {
                                    _toggleChecklistOnController(_ctrl, index);
                                    if (mounted) setState(() {});
                                  }
                                : null,
                          )
                        : _NoteEditorPane(
                            controller: _ctrl,
                            attachments: _attachments,
                            readOnly: !enabled,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  void _insertPrefix(String prefix) {
    final text = _ctrl.text;
    final selection = _ctrl.selection;
    final start = selection.isValid ? selection.start : text.length;
    final lineStart = start <= 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final next = text.replaceRange(lineStart, lineStart, prefix);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
  }

  void _wrapSelection(String marker) {
    final text = _ctrl.text;
    final selection = _ctrl.selection;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.start : text.length;
      final next = text.replaceRange(offset, offset, '$marker$marker');
      _ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: offset + marker.length),
      );
      return;
    }
    final selected = selection.textInside(text);
    final next = text.replaceRange(
      selection.start,
      selection.end,
      '$marker$selected$marker',
    );
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: selection.end + marker.length * 2,
      ),
    );
  }

  void _insertLink() {
    final text = _ctrl.text;
    final selection = _ctrl.selection;
    final selected = selection.isValid && !selection.isCollapsed
        ? selection.textInside(text)
        : I18n.tr('note.link.placeholder');
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final replacement = '[$selected](https://)';
    final next = text.replaceRange(start, end, replacement);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + replacement.length - 1,
      ),
    );
  }

  Future<T?> _pushOwned<T>(
    NoteEditorOperation operation,
    ModalRoute<T> route,
  ) async {
    if (!mounted || !operation.isCurrent()) return null;
    operation.own(route);
    final result = Navigator.of(context).push(route);
    operation.listenForCover();
    try {
      final value = await result;
      await route.completed;
      return value;
    } finally {
      operation.release(route);
    }
  }

  bool _canCloseOwned(
    NoteEditorOperation operation,
    BuildContext modalContext,
  ) =>
      mounted &&
      modalContext.mounted &&
      operation.isCurrent() &&
      identical(operation.ownedRoute, ModalRoute.of(modalContext));

  Future<void> _addAttachment(int revision) async {
    final operation = _begin(revision, choosingAttachment: true);
    if (operation == null) return;
    try {
      final source = await _pushOwned<_AttachmentSource>(
        operation,
        createAppModalSheetRoute<_AttachmentSource>(
          context: context,
          builder: (ctx) => ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (ctx, _, _) => AppModalSheet(
              title: I18n.tr('note.attachment.dialog_title'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSettingsTile(
                    icon: Icons.folder_open_outlined,
                    color: Theme.of(ctx).colorScheme.primary,
                    title: I18n.tr('note.attachment.pick_file'),
                    subtitle: I18n.tr('note.attachment.pick_file.subtitle'),
                    onTap: () {
                      if (_canCloseOwned(operation, ctx)) {
                        Navigator.of(ctx).pop(_AttachmentSource.file);
                      }
                    },
                  ),
                  AppSettingsTile(
                    icon: Icons.link_outlined,
                    color: Theme.of(ctx).colorScheme.secondary,
                    title: I18n.tr('note.attachment.add_link'),
                    subtitle: I18n.tr('note.attachment.add_link.subtitle'),
                    onTap: () {
                      if (_canCloseOwned(operation, ctx)) {
                        Navigator.of(ctx).pop(_AttachmentSource.manual);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (source == null || !mounted || !operation.isCurrent()) return;
      if (source == _AttachmentSource.file) {
        final picked = await NoteAttachmentPicker.pickFile();
        if (!mounted || !operation.isCurrent()) return;
        if (picked != null) setState(() => _attachments.add(picked));
        // Canceling the system picker returns directly to the retained draft.
        return;
      }
      final attachment = await _pushOwned<NoteAttachment>(
        operation,
        createControllerDialogRoute<NoteAttachment>(
          context: context,
          useRootNavigator: false,
          builder: (ctx) => _ManualAttachmentForm(operation: operation),
        ),
      );
      if (!mounted || !operation.isCurrent() || attachment == null) return;
      setState(() => _attachments.add(attachment));
    } catch (_) {
      if (mounted && operation.isCurrent()) {
        setState(() => _feedback = _NoteEditorFeedback.attachmentFailed);
      }
    } finally {
      _end(operation);
    }
  }

  Future<void> _exportCurrentMarkdown(int revision) async {
    if (!_canAct(revision) || _operation != null) return;
    final text = _ctrl.text;
    final now = DateTime.now();
    final draft = NoteItem(
      id: _draftId,
      content: text,
      format: 'markdown',
      blocks: NoteBlock.fromMarkdown(text),
      attachments: List.unmodifiable(_attachments),
      tags: List.unmodifiable(_tags),
      folder: _folder,
      pinned: widget.note?.pinned ?? false,
      archived: widget.note?.archived ?? false,
      createdAt: _draftCreatedAt,
      updatedAt: now,
    );
    final title = draft.titleFor(I18n.current).trim();
    final base = title.isEmpty ? 'duoyi_note' : title;
    final rawName = base.toLowerCase().endsWith('.md') ? base : '$base.md';
    final fileName = WebFileDownload.sanitizeFileName(
      rawName,
      fallback: 'duoyi_note.md',
    );
    try {
      final result = await WebFileDownload.saveText(
        content: draft.toMarkdownDocument(I18n.current),
        fileName: fileName,
        mimeType: 'text/markdown;charset=utf-8',
        shareSubject: draft.titleFor(I18n.current),
        canProceed: () => mounted && _canAct(revision),
      );
      if (!mounted || !_canAct(revision) || !result.saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.current == AppLocale.en
                ? 'Exported Markdown: $fileName'
                : '已导出 Markdown：$fileName',
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !_canAct(revision)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.current == AppLocale.en
                ? 'Failed to export Markdown file.'
                : '导出 Markdown 文件失败，请重试',
          ),
        ),
      );
    }
  }

  Future<void> _editFolderDialog(int revision) async {
    final operation = _begin(revision);
    if (operation == null) return;
    try {
      final suggestions = <String>{
        for (final note in operation.origin.provider.notes)
          if (note.folder != null && note.folder!.trim().isNotEmpty)
            note.folder!.trim(),
      }.toList()..sort();
      final result = await _pushOwned<String>(
        operation,
        createControllerDialogRoute<String>(
          context: context,
          useRootNavigator: false,
          builder: (ctx) => _NoteTextInputDialog(
            operation: operation,
            title: I18n.current == AppLocale.en ? 'Notebook / Folder' : '所属笔记本',
            hintText: I18n.current == AppLocale.en
                ? 'Enter folder name (blank clears)'
                : '输入笔记本名称（留空则清除）',
            initialValue: _folder ?? '',
            suggestions: suggestions,
            allowEmptySubmit: true,
          ),
        ),
      );
      if (!mounted || !operation.isCurrent() || result == null) return;
      setState(() => _folder = NoteItem.normalizeFolder(result));
    } finally {
      _end(operation);
    }
  }

  Future<void> _addTagDialog(int revision) async {
    final operation = _begin(revision);
    if (operation == null) return;
    try {
      final suggestions = <String>{
        for (final note in operation.origin.provider.notes)
          for (final tag in note.tags)
            if (!_tags.contains(tag)) tag,
      }.toList()..sort();
      final result = await _pushOwned<String>(
        operation,
        createControllerDialogRoute<String>(
          context: context,
          useRootNavigator: false,
          builder: (ctx) => _NoteTextInputDialog(
            operation: operation,
            title: I18n.current == AppLocale.en ? 'Add tags' : '添加标签',
            hintText: I18n.current == AppLocale.en
                ? 'Enter tags (comma-separated)'
                : '输入标签（可用逗号分隔）',
            initialValue: '',
            suggestions: suggestions,
            allowEmptySubmit: false,
          ),
        ),
      );
      if (!mounted || !operation.isCurrent() || result == null) return;
      final parts = result
          .split(RegExp(r'[,，\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      setState(() => _tags = NoteItem.normalizeTags([..._tags, ...parts]).toList());
    } finally {
      _end(operation);
    }
  }
}

void _toggleChecklistOnController(
  TextEditingController controller,
  int lineIndex,
) {
  final current = controller.text;
  final next = NoteBlock.toggleChecklistLine(current, lineIndex);
  if (next == current) return;
  final cursor = controller.selection.isValid
      ? math.min(controller.selection.extentOffset, next.length)
      : next.length;
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: cursor),
  );
}

class _NoteTextInputDialog extends StatefulWidget {
  const _NoteTextInputDialog({
    required this.operation,
    required this.title,
    required this.hintText,
    required this.initialValue,
    required this.suggestions,
    required this.allowEmptySubmit,
  });

  final NoteEditorOperation operation;
  final String title;
  final String hintText;
  final String initialValue;
  final List<String> suggestions;
  final bool allowEmptySubmit;

  @override
  State<_NoteTextInputDialog> createState() => _NoteTextInputDialogState();
}

class _NoteTextInputDialogState extends State<_NoteTextInputDialog> {
  late final TextEditingController _ctrl;

  bool get _canAct =>
      mounted &&
      widget.operation.isCurrent() &&
      identical(widget.operation.ownedRoute, ModalRoute.of(context));

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = I18n.current == AppLocale.en;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(hintText: widget.hintText),
            ),
            if (widget.suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in widget.suggestions.take(12))
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(item),
                      onPressed: () {
                        if (!_canAct) return;
                        Navigator.of(context).pop(item);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_canAct) Navigator.of(context).pop();
          },
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (!_canAct) return;
            final val = _ctrl.text.trim();
            if (!widget.allowEmptySubmit && val.isEmpty) return;
            Navigator.of(context).pop(val);
          },
          child: Text(isEn ? 'Confirm' : '确定'),
        ),
      ],
    );
  }
}

enum _AttachmentSource { file, manual }

enum _NoteEditorFeedback { saveFailed, attachmentFailed, openFailed }

class _ManualAttachmentForm extends StatefulWidget {
  const _ManualAttachmentForm({required this.operation});
  final NoteEditorOperation operation;

  @override
  State<_ManualAttachmentForm> createState() => _ManualAttachmentFormState();
}

class _ManualAttachmentFormState extends State<_ManualAttachmentForm> {
  final _name = TextEditingController();
  final _uri = TextEditingController();
  final _mime = TextEditingController();
  bool _missingLocation = false;

  bool get _canAct =>
      mounted &&
      widget.operation.isCurrent() &&
      identical(widget.operation.ownedRoute, ModalRoute.of(context));

  @override
  void dispose() {
    _name.dispose();
    _uri.dispose();
    _mime.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canAct) return;
    final location = _uri.text.trim();
    if (location.isEmpty) {
      setState(() => _missingLocation = true);
      return;
    }
    Navigator.of(context).pop(
      NoteAttachment(
        name: _name.text.trim().isEmpty
            ? I18n.tr('note.attachment.default_name')
            : _name.text.trim(),
        uri: location,
        mimeType: _mime.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) => AppDialog(
      title: Text(I18n.tr('note.attachment.dialog_title')),
      content: SingleChildScrollView(
        child: AppSecondaryControlTheme(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('note-attachment-name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: I18n.tr('note.attachment.name'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('note-attachment-location'),
                controller: _uri,
                decoration: InputDecoration(
                  labelText: I18n.tr('note.attachment.uri'),
                  hintText: I18n.tr('note.attachment.uri_hint'),
                  errorText: _missingLocation
                      ? NoteEditorUiCopy.requiredLocation
                      : null,
                ),
                onChanged: (_) {
                  if (_canAct && _missingLocation) {
                    setState(() => _missingLocation = false);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('note-attachment-type'),
                controller: _mime,
                decoration: InputDecoration(
                  labelText: I18n.tr('note.attachment.type'),
                  hintText: I18n.tr('note.attachment.type_hint'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_canAct) Navigator.of(context).pop();
          },
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          key: const ValueKey('note-attachment-submit'),
          onPressed: _submit,
          child: Text(I18n.tr('action.add')),
        ),
      ],
    ),
  );
}

class _NoteEditorPane extends StatelessWidget {
  final TextEditingController controller;
  final List<NoteAttachment> attachments;
  final bool readOnly;

  const _NoteEditorPane({
    required this.controller,
    required this.attachments,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final editor = _NoteTextEditor(
          controller: controller,
          readOnly: readOnly,
        );
        if (constraints.maxWidth < 760) return editor;
        return Row(
          children: [
            Expanded(child: editor),
            const VerticalDivider(width: 28),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => _MarkdownPreview(
                  content: value.text,
                  blocks: NoteBlock.fromMarkdown(value.text),
                  attachments: attachments,
                  onToggleChecklist: readOnly
                      ? null
                      : (index) =>
                          _toggleChecklistOnController(controller, index),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NoteTextEditor extends StatelessWidget {
  final TextEditingController controller;

  final bool readOnly;

  const _NoteTextEditor({required this.controller, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: null,
      expands: true,
      autofocus: true,
      decoration: InputDecoration(
        hintText: I18n.tr('note.editor.hint'),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
      ),
      style: const TextStyle(fontSize: 16, height: 1.5),
    );
  }
}

class _MarkdownEditingController extends TextEditingController {
  _MarkdownEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle(fontSize: 16, height: 1.5);
    final cs = Theme.of(context).colorScheme;
    return TextSpan(
      style: base,
      children: _parseMarkdownDocument(text, base, cs),
    );
  }

  List<InlineSpan> _parseMarkdownDocument(
    String source,
    TextStyle base,
    ColorScheme cs,
  ) {
    if (source.isEmpty) return const [TextSpan(text: '')];
    final spans = <InlineSpan>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.addAll(_parseMarkdownLine(lines[i], base, cs));
    }
    return spans;
  }

  List<InlineSpan> _parseMarkdownLine(
    String line,
    TextStyle base,
    ColorScheme cs,
  ) {
    final markerStyle = base.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );
    final indentLength = line.length - line.trimLeft().length;
    final indent = indentLength == 0 ? '' : line.substring(0, indentLength);
    final trimmed = line.substring(indentLength);
    final spans = <InlineSpan>[];
    if (indent.isNotEmpty) spans.add(TextSpan(text: indent));

    if (trimmed.startsWith('# ')) {
      spans.add(TextSpan(text: '# ', style: markerStyle));
      spans.addAll(
        _parseInlineForEditor(
          trimmed.substring(2),
          base.copyWith(
            fontSize: ((base.fontSize ?? 14) + 4).clamp(16.0, 18.0),
            fontWeight: FontWeight.normal,
          ),
          cs,
        ),
      );
      return spans;
    }
    if (trimmed.startsWith('> ')) {
      spans.add(TextSpan(text: '> ', style: markerStyle));
      spans.addAll(
        _parseInlineForEditor(
          trimmed.substring(2),
          base.copyWith(
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
          cs,
        ),
      );
      return spans;
    }
    if (trimmed.startsWith('- [ ] ') || trimmed.startsWith('- [x] ')) {
      final checked = trimmed.startsWith('- [x] ');
      spans.add(TextSpan(text: trimmed.substring(0, 6), style: markerStyle));
      spans.addAll(
        _parseInlineForEditor(
          trimmed.substring(6),
          checked
              ? base.copyWith(
                  color: cs.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                )
              : base,
          cs,
        ),
      );
      return spans;
    }
    if (trimmed.startsWith('- ')) {
      spans.add(TextSpan(text: '- ', style: markerStyle));
      spans.addAll(_parseInlineForEditor(trimmed.substring(2), base, cs));
      return spans;
    }
    return spans..addAll(_parseInlineForEditor(trimmed, base, cs));
  }

  List<InlineSpan> _parseInlineForEditor(
    String source,
    TextStyle base,
    ColorScheme cs,
  ) {
    final markerStyle = base.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < source.length) {
      final bold = source.indexOf('**', i);
      final italic = source.indexOf('*', i);
      final code = source.indexOf('`', i);
      final link = source.indexOf('[', i);
      final candidates = <int>[
        bold,
        italic,
        code,
        link,
      ].where((pos) => pos >= 0).toList()..sort();
      final next = candidates.isEmpty ? -1 : candidates.first;
      if (next < 0) {
        spans.add(TextSpan(text: source.substring(i)));
        break;
      }
      if (next > i) {
        spans.add(TextSpan(text: source.substring(i, next)));
        i = next;
      }
      if (source.startsWith('**', i)) {
        final end = source.indexOf('**', i + 2);
        if (end > i + 2) {
          spans
            ..add(TextSpan(text: '**', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 2, end),
                style: base.copyWith(fontWeight: FontWeight.normal),
              ),
            )
            ..add(TextSpan(text: '**', style: markerStyle));
          i = end + 2;
          continue;
        }
      }
      if (source.startsWith('`', i)) {
        final end = source.indexOf('`', i + 1);
        if (end > i + 1) {
          spans
            ..add(TextSpan(text: '`', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 1, end),
                style: base.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: cs.surfaceContainerHighest.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            )
            ..add(TextSpan(text: '`', style: markerStyle));
          i = end + 1;
          continue;
        }
      }
      if (source.startsWith('[', i)) {
        final closeLabel = source.indexOf('](', i + 1);
        final closeUrl = closeLabel < 0 ? -1 : source.indexOf(')', closeLabel);
        if (closeLabel > i + 1 && closeUrl > closeLabel + 2) {
          spans
            ..add(TextSpan(text: '[', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 1, closeLabel),
                style: base.copyWith(
                  color: cs.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
            ..add(
              TextSpan(
                text: source.substring(closeLabel, closeUrl + 1),
                style: markerStyle,
              ),
            );
          i = closeUrl + 1;
          continue;
        }
      }
      if (source.startsWith('*', i)) {
        final end = source.indexOf('*', i + 1);
        if (end > i + 1) {
          spans
            ..add(TextSpan(text: '*', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 1, end),
                style: base.copyWith(fontStyle: FontStyle.italic),
              ),
            )
            ..add(TextSpan(text: '*', style: markerStyle));
          i = end + 1;
          continue;
        }
      }
      spans.add(TextSpan(text: source[i]));
      i++;
    }
    return spans;
  }
}

class _NoteFormatToolbar extends StatelessWidget {
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBullet;
  final VoidCallback onChecklist;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback onAttachment;

  const _NoteFormatToolbar({
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBullet,
    required this.onChecklist,
    required this.onCode,
    required this.onLink,
    required this.onAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.title,
              tooltip: I18n.tr('note.toolbar.heading'),
              onPressed: onHeading,
            ),
            _ToolButton(
              icon: Icons.format_bold,
              tooltip: I18n.tr('note.toolbar.bold'),
              onPressed: onBold,
            ),
            _ToolButton(
              icon: Icons.format_italic,
              tooltip: I18n.tr('note.toolbar.italic'),
              onPressed: onItalic,
            ),
            _ToolButton(
              icon: Icons.format_quote,
              tooltip: I18n.tr('note.toolbar.quote'),
              onPressed: onQuote,
            ),
            _ToolButton(
              icon: Icons.format_list_bulleted,
              tooltip: I18n.tr('note.toolbar.bullet'),
              onPressed: onBullet,
            ),
            _ToolButton(
              icon: Icons.checklist,
              tooltip: I18n.tr('note.toolbar.checklist'),
              onPressed: onChecklist,
            ),
            _ToolButton(
              icon: Icons.code,
              tooltip: I18n.tr('note.toolbar.code'),
              onPressed: onCode,
            ),
            _ToolButton(
              icon: Icons.link,
              tooltip: I18n.tr('note.toolbar.link'),
              onPressed: onLink,
            ),
            _ToolButton(
              icon: Icons.attach_file,
              tooltip: I18n.tr('note.toolbar.attachment'),
              onPressed: onAttachment,
            ),
            const SizedBox(width: 8),
            Text(
              'Markdown',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final NoteAttachment attachment;
  final VoidCallback? onDeleted;
  final bool compact;
  final bool Function()? canOpen;
  final VoidCallback? onOpenFailed;

  const _AttachmentChip({
    required this.attachment,
    this.onDeleted,
    this.compact = false,
    this.canOpen,
    this.onOpenFailed,
  });

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(attachment.uri);
    final target = uri == null
        ? null
        : (uri.scheme == 'http' ||
                  uri.scheme == 'https' ||
                  (kIsWeb && uri.scheme == 'blob'))
              ? uri
              : kIsWeb
              ? null
              : uri.scheme.isEmpty
              ? Uri.file(attachment.uri, windows: false)
              : const {'http', 'https', 'file', 'content'}.contains(uri.scheme)
              ? uri
              : null;
    return InputChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        _isWebUri(uri) ? Icons.link : Icons.insert_drive_file_outlined,
        size: compact ? 14 : 16,
      ),
      label: Text(
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      labelStyle: TextStyle(fontSize: compact ? 11 : 12),
      onDeleted: onDeleted,
      onPressed: target == null || canOpen?.call() == false
          ? null
          : () async {
              if (!context.mounted || canOpen?.call() == false) return;
              try {
                final opened = await launchUrl(
                  target,
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted && canOpen?.call() != false) {
                  onOpenFailed?.call();
                }
              } catch (_) {
                if (context.mounted && canOpen?.call() != false) {
                  onOpenFailed?.call();
                }
              }
            },
    );
  }

  bool _isWebUri(Uri? uri) => uri?.scheme == 'http' || uri?.scheme == 'https';
}

class _MarkdownPreview extends StatelessWidget {
  final String content;
  final List<NoteBlock>? blocks;
  final List<NoteAttachment> attachments;
  final ValueChanged<int>? onToggleChecklist;

  const _MarkdownPreview({
    required this.content,
    this.blocks,
    required this.attachments,
    this.onToggleChecklist,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final noteBlocks =
        blocks ??
        (content.trim().isEmpty
            ? [
                NoteBlock(
                  id: 'empty',
                  type: NoteBlockType.paragraph,
                  text: I18n.tr('note.preview.empty'),
                ),
              ]
            : NoteBlock.fromMarkdown(content));
    final images = attachments.where((attachment) => attachment.isImage);
    return ListView(
      children: [
        for (final image in images)
          _PreviewImageAttachment(attachment: image, colorScheme: cs),
        for (var i = 0; i < noteBlocks.length; i++)
          _PreviewBlock(
            block: noteBlocks[i],
            colorScheme: cs,
            onToggleChecklist:
                onToggleChecklist != null &&
                    noteBlocks[i].type == NoteBlockType.checklist
                ? () => onToggleChecklist!(i)
                : null,
          ),
      ],
    );
  }
}

class _PreviewImageAttachment extends StatelessWidget {
  final NoteAttachment attachment;
  final ColorScheme colorScheme;

  const _PreviewImageAttachment({
    required this.attachment,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(attachment.uri);
    final dataBytes = ImageDecodeCache.decodeBase64Image(attachment.uri);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final maxLogicalWidth = math.min(
      MediaQuery.sizeOf(context).width,
      DesktopTokens.secondaryMaxContentWidth,
    );
    final cacheWidth = ImageDecodeCache.boundedCachePixels(maxLogicalWidth, dpr);
    final cacheHeight = ImageDecodeCache.boundedCachePixels(
      maxLogicalWidth * 9 / 16,
      dpr,
    );
    Widget image;
    if (dataBytes != null) {
      image = Image.memory(
        dataBytes,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    } else if (uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            (kIsWeb && uri.scheme == 'blob'))) {
      image = Image.network(
        attachment.uri,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    } else if (!kIsWeb && uri != null && uri.scheme == 'file') {
      image = Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    } else if (!kIsWeb && attachment.uri.startsWith('/')) {
      image = Image.file(
        File(attachment.uri),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    } else {
      image = _imageFallback();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          appSurfaceStyleOf(context)?.smallTileRadius ??
              DesignTokens.radiusControl,
        ),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: image,
          ),
        ),
      ),
    );
  }

  Widget _imageFallback() {
    return Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  final NoteBlock block;
  final ColorScheme colorScheme;
  final VoidCallback? onToggleChecklist;

  const _PreviewBlock({
    required this.block,
    required this.colorScheme,
    this.onToggleChecklist,
  });

  @override
  Widget build(BuildContext context) {
    if (block.type == NoteBlockType.heading) {
      final style = block.level <= 1
          ? Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.normal)
          : Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.normal);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _InlineMarkdownText(text: block.text, style: style),
      );
    }
    if (block.type == NoteBlockType.quote) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
          color: colorScheme.primary.withValues(alpha: 0.06),
        ),
        child: _InlineMarkdownText(
          text: block.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (block.type == NoteBlockType.checklist) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final checkedColor = appReadableForeground(
        colorScheme.surface,
        isDark ? const Color(0xFF66BB6A) : DesignTokens.defaultSuccess,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          onTap: onToggleChecklist,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  block.checked
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 18,
                  color: block.checked
                      ? checkedColor
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InlineMarkdownText(
                    text: block.text,
                    style: block.checked
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: colorScheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (block.type == NoteBlockType.bullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.circle,
                size: 6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _InlineMarkdownText(text: block.text)),
          ],
        ),
      );
    }
    if (block.type == NoteBlockType.code) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
        child: Text(
          block.text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      );
    }
    if (block.type == NoteBlockType.divider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(color: colorScheme.outlineVariant),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _InlineMarkdownText(text: block.text),
    );
  }
}

class _InlineMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _InlineMarkdownText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = style ?? const TextStyle(fontSize: 16, height: 1.5);
    return Text.rich(
      TextSpan(
        style: base,
        children: _parseInline(text, base, colorScheme),
      ),
    );
  }

  List<InlineSpan> _parseInline(
    String source,
    TextStyle base,
    ColorScheme colorScheme,
  ) {
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < source.length) {
      final bold = source.indexOf('**', i);
      final italic = source.indexOf('*', i);
      final code = source.indexOf('`', i);
      final link = source.indexOf('[', i);
      final candidates = <int>[
        bold,
        italic,
        code,
        link,
      ].where((pos) => pos >= 0).toList()..sort();
      final next = candidates.isEmpty ? -1 : candidates.first;
      if (next < 0) {
        spans.add(TextSpan(text: source.substring(i)));
        break;
      }
      if (next > i) {
        spans.add(TextSpan(text: source.substring(i, next)));
        i = next;
      }
      if (source.startsWith('**', i)) {
        final end = source.indexOf('**', i + 2);
        if (end > i + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 2, end),
              style: base.copyWith(fontWeight: FontWeight.normal),
            ),
          );
          i = end + 2;
          continue;
        }
      }
      if (source.startsWith('`', i)) {
        final end = source.indexOf('`', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(
                fontFamily: 'monospace',
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.65,
                ),
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      if (source.startsWith('[', i)) {
        final closeLabel = source.indexOf('](', i + 1);
        final closeUrl = closeLabel < 0 ? -1 : source.indexOf(')', closeLabel);
        if (closeLabel > i + 1 && closeUrl > closeLabel + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, closeLabel),
              style: base.copyWith(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          );
          i = closeUrl + 1;
          continue;
        }
      }
      if (source.startsWith('*', i)) {
        final end = source.indexOf('*', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      spans.add(TextSpan(text: source[i]));
      i++;
    }
    return spans;
  }
}
