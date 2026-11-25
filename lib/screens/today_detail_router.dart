import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/today_ui_copy.dart';
import '../models/anniversary.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/todo_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/settings_action_origin.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import 'anniversary_screen.dart';
import 'course_schedule_screen.dart';
import 'diary_screen.dart';
import 'goal_edit_screen.dart';
import 'goal_screen.dart';
import 'habit_detail_screen.dart';
import 'habit_screen.dart';
import 'note_screen.dart';
import 'todo_detail_screen.dart';
import 'todo_screen.dart';

/// 今日页 / 其他聚合页调用的"详情跳转"所属 section 类型（Requirement 6.2）。
enum TodaySectionKind {
  todos,
  courses,
  anniversaries,
  goals,
  habits,
  notes,
  diary,
}

/// 今日页 / 聚合页"查看"按钮的统一路由入口（Requirement 6）。
///
/// - 按 section 类型跳转到对应详情页；
/// - 若具体 id 指向的条目已被删除 / id 为空，退化到列表页或 `EmptyState` 兜底，
///   而不是把用户直接扔进黑屏页面（R6.3）；
/// - 路由构建过程中抛出的任何异常被捕获 → `ErrorState` 页（R6.4）。
class TodayDetailRouter {
  TodayDetailRouter._();

  /// 统一入口。[id] 可选；未传时进入对应 section 的列表页。
  static Future<void> open(
    BuildContext context,
    TodaySectionKind kind, {
    String? id,
    int? accountGeneration,
  }) async {
    if (!context.mounted) return;
    final openingGeneration =
        accountGeneration ?? AccountLocalDataCleaner.accountDataGeneration;
    final origin = _DetailRouteOrigin(context, kind, openingGeneration);
    if (!origin.isCurrent(checkRoute: true)) return;
    try {
      final route = _routeFor(
        context,
        kind,
        id,
        origin: origin,
        accountGeneration: openingGeneration,
      );
      await Navigator.push(context, route);
    } catch (e, st) {
      // 路由构建阶段失败（例如 Provider 不在上下文），跳到 ErrorState 兜底。
      debugPrint('[TodayDetailRouter] route build failed: $e\n$st');
      if (!context.mounted || !origin.isCurrent(checkRoute: true)) return;
      await Navigator.push(
        context,
        _brandRoute(
          _DetailFallback(
            kind: kind,
            origin: origin,
            failedId: id,
            failed: true,
          ),
        ),
      );
    }
  }

  static Route<void> _routeFor(
    BuildContext context,
    TodaySectionKind kind,
    String? id, {
    required _DetailRouteOrigin origin,
    int? accountGeneration,
  }) {
    final openingGeneration =
        accountGeneration ?? AccountLocalDataCleaner.accountDataGeneration;
    switch (kind) {
      case TodaySectionKind.todos:
        if (id == null) {
          return _brandRoute(const TodoScreen());
        }
        final exists = context.read<TodoProvider>().todos.any(
          (t) => t.id == id,
        );
        if (!exists) return _emptyRoute(kind, origin);
        return _brandRoute(
          TodoDetailScreen(todoId: id, accountGeneration: openingGeneration),
        );

      case TodaySectionKind.courses:
        if (id != null) {
          final exists = context.read<CourseProvider>().courses.any(
            (course) => course.id == id,
          );
          if (!exists) return _emptyRoute(kind, origin);
          return _brandRoute(CourseScheduleScreen(initialCourseId: id));
        }
        return _brandRoute(const CourseScheduleScreen());

      case TodaySectionKind.anniversaries:
        AnniversaryType? anniversaryType;
        if (id != null) {
          final items = context.read<AnniversaryProvider>().items;
          final index = items.indexWhere((a) => a.id == id);
          if (index < 0) return _emptyRoute(kind, origin);
          anniversaryType = items[index].type;
        }
        return switch (anniversaryType) {
          AnniversaryType.birthday => _brandRoute(
            BirthdayScreen(initialAnniversaryId: id),
          ),
          AnniversaryType.memorial => _brandRoute(
            MemorialAnniversaryScreen(initialAnniversaryId: id),
          ),
          AnniversaryType.normal => _brandRoute(
            AnniversaryScreen(
              fixedType: AnniversaryType.normal,
              initialAnniversaryId: id,
            ),
          ),
          _ => _brandRoute(AnniversaryScreen(initialAnniversaryId: id)),
        };

      case TodaySectionKind.goals:
        if (id == null) {
          return _brandRoute(const GoalScreen());
        }
        final goals = context.read<GoalProvider>().goals;
        final idx = goals.indexWhere((g) => g.id == id);
        if (idx < 0) return _emptyRoute(kind, origin);
        final goal = goals[idx];
        return _brandRoute(GoalEditScreen(goal: goal));

      case TodaySectionKind.habits:
        if (id == null) {
          return _brandRoute(const HabitScreen());
        }
        final exists = context.read<HabitProvider>().habits.any(
          (h) => h.id == id,
        );
        if (!exists) return _emptyRoute(kind, origin);
        return _brandRoute(HabitDetailScreen(habitId: id));

      case TodaySectionKind.notes:
        if (id == null) {
          return _brandRoute(const NoteScreen());
        }
        final notes = context.read<NoteProvider>().notes;
        final idx = notes.indexWhere((note) => note.id == id);
        if (idx < 0) return _emptyRoute(kind, origin);
        return _brandRoute(NoteEditScreen(note: notes[idx]));

      case TodaySectionKind.diary:
        if (id != null) {
          final entries = context.read<DiaryProvider>().entries;
          final idx = entries.indexWhere((entry) => entry.id == id);
          if (idx < 0) return _emptyRoute(kind, origin);
          return _brandRoute(DiaryEditScreen(entry: entries[idx]));
        }
        return _brandRoute(const DiaryScreen());
    }
  }

  static MaterialPageRoute<void> _brandRoute(Widget child) {
    return MaterialPageRoute(builder: (_) => BrandRouteSurface(child: child));
  }

  static Route<void> _emptyRoute(
    TodaySectionKind kind,
    _DetailRouteOrigin origin,
  ) {
    return _brandRoute(_DetailFallback(kind: kind, origin: origin));
  }

  static void _replaceFallback(
    BuildContext context,
    TodaySectionKind kind,
    _DetailRouteOrigin origin,
    String? id,
  ) {
    if (!context.mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        !origin.isCurrent()) {
      return;
    }
    Route<void> route;
    try {
      route = _routeFor(
        origin.context,
        kind,
        id,
        origin: origin,
        accountGeneration: origin.accountGeneration,
      );
    } catch (error, stack) {
      debugPrint('[TodayDetailRouter] retry failed: $error\n$stack');
      route = _brandRoute(
        _DetailFallback(kind: kind, origin: origin, failed: true, failedId: id),
      );
    }
    if (!origin.isCurrent()) return;
    unawaited(Navigator.of(context).pushReplacement<void, void>(route));
  }
}

/// Retains the account and provider behind recovery without rebinding to new data.
class _DetailRouteOrigin {
  _DetailRouteOrigin(this.context, this.kind, this.accountGeneration)
    : _settings = SettingsActionOrigin(context) {
    _provider = _providerIdentity();
  }

  final BuildContext context;
  final TodaySectionKind kind;
  final int accountGeneration;
  final SettingsActionOrigin _settings;
  late final Object _provider;
  static const _unavailable = Object();

  Listenable? get changes => switch (_provider) {
    (final Listenable provider, _) => provider,
    _ => null,
  };

  Object _providerIdentity() {
    try {
      final provider = switch (kind) {
        TodaySectionKind.todos => context.read<TodoProvider?>(),
        TodaySectionKind.courses => context.read<CourseProvider?>(),
        TodaySectionKind.anniversaries => context.read<AnniversaryProvider?>(),
        TodaySectionKind.goals => context.read<GoalProvider?>(),
        TodaySectionKind.habits => context.read<HabitProvider?>(),
        TodaySectionKind.notes => context.read<NoteProvider?>(),
        TodaySectionKind.diary => context.read<DiaryProvider?>(),
      };
      return switch (provider) {
        TodoProvider p => (p, p.storageGeneration),
        AnniversaryProvider p => (p, p.storageGeneration),
        GoalProvider p => (p, p.storageGeneration),
        NoteProvider p => (p, p.storageGeneration),
        _ => (provider, null),
      };
    } catch (_) {
      return _unavailable;
    }
  }

  bool isCurrent({bool checkRoute = false}) =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        accountGeneration,
      ) &&
      _settings.isCurrent(checkRoute: checkRoute) &&
      _providerIdentity() == _provider;
}

/// Localized, scrollable recovery that replaces only its own current route.
class _DetailFallback extends StatelessWidget
    implements LocaleStatePreservingRoute {
  final TodaySectionKind kind;
  final _DetailRouteOrigin origin;
  final bool failed;
  final String? failedId;

  const _DetailFallback({
    required this.kind,
    required this.origin,
    this.failed = false,
    this.failedId,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        I18n.localeListenable,
        AccountLocalDataCleaner.accountDataGenerationListenable,
        ?origin.changes,
      ]),
      builder: (context, _) {
        final current = origin.isCurrent();
        final title = TodayUiCopy.detailTitle(kind.name);
        final body = !current
            ? TodayUiCopy.detailSourceChanged
            : failed
            ? TodayUiCopy.detailOpenFailed
            : TodayUiCopy.detailMissing(kind.name);
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(title),
            titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DesignTokens.space3xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      failed ? Icons.error_outline : Icons.inbox_outlined,
                      size: 56,
                      color: failed
                          ? DesignTokens.resultError
                          : DesignTokens.resultEmpty,
                    ),
                    const SizedBox(height: DesignTokens.spaceMd),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeBase,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spaceLg),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (current)
                          FilledButton.icon(
                            onPressed: () => TodayDetailRouter._replaceFallback(
                              context,
                              kind,
                              origin,
                              failed ? failedId : null,
                            ),
                            icon: Icon(failed ? Icons.refresh : Icons.list_alt),
                            label: Text(
                              failed
                                  ? I18n.tr('action.retry')
                                  : TodayUiCopy.detailOpenList,
                            ),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            if (context.mounted &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              Navigator.of(context).pop();
                            }
                          },
                          icon: const Icon(Icons.arrow_back),
                          label: Text(I18n.tr('action.back')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
