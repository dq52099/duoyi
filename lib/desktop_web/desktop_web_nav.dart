import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/global_search.dart';
import '../core/i18n.dart';

/// Top-level workspace destinations available in the Desktop Web shell.
enum DesktopWebDestination {
  today,
  todo,
  habit,
  calendar,
  focus,
  almanac,
  goals,
  notes,
  diary,
  stats,
  timeAudit,
  schedule,
  anniversary,
  countdown,
  themes,
  settings,
  moreApps,
}

/// Grouping sections in the Desktop Web navigation sidebar.
enum DesktopWebNavSection {
  workspace,
  tools,
  footer,
}

/// Quick-create entity types supported from the sidebar and command palette.
enum DesktopQuickCreateKind {
  todo,
  habit,
  goal,
  note,
  diary,
  calendarEvent,
  focus,
}

/// Initial mode when opening the Ctrl/Cmd+K command palette.
enum DesktopCommandMode {
  search,
  quickCreate,
}

extension DesktopWebDestinationX on DesktopWebDestination {
  DesktopWebNavSection get section => switch (this) {
    DesktopWebDestination.today ||
    DesktopWebDestination.todo ||
    DesktopWebDestination.habit ||
    DesktopWebDestination.calendar ||
    DesktopWebDestination.focus => DesktopWebNavSection.workspace,
    DesktopWebDestination.almanac ||
    DesktopWebDestination.goals ||
    DesktopWebDestination.notes ||
    DesktopWebDestination.diary ||
    DesktopWebDestination.stats ||
    DesktopWebDestination.timeAudit ||
    DesktopWebDestination.schedule ||
    DesktopWebDestination.anniversary ||
    DesktopWebDestination.countdown => DesktopWebNavSection.tools,
    DesktopWebDestination.themes ||
    DesktopWebDestination.settings ||
    DesktopWebDestination.moreApps => DesktopWebNavSection.footer,
  };

  bool get isPrimaryView => section == DesktopWebNavSection.workspace;

  String localizedLabel(AppLocale locale) {
    final isEn = locale == AppLocale.en;
    return switch (this) {
      DesktopWebDestination.today => isEn ? 'Today' : '今日',
      DesktopWebDestination.todo => isEn ? 'Tasks' : '待办',
      DesktopWebDestination.habit => isEn ? 'Habits' : '习惯',
      DesktopWebDestination.calendar => isEn ? 'Calendar' : '日历',
      DesktopWebDestination.focus => isEn ? 'Focus' : '番茄专注',
      DesktopWebDestination.almanac => isEn ? 'Almanac' : '万年历',
      DesktopWebDestination.goals => isEn ? 'Goals' : '目标管理',
      DesktopWebDestination.notes => isEn ? 'Notes' : '随手记',
      DesktopWebDestination.diary => isEn ? 'Diary' : '日记',
      DesktopWebDestination.stats => isEn ? 'Statistics' : '统计报表',
      DesktopWebDestination.timeAudit => isEn ? 'Time Log' : '时间足迹',
      DesktopWebDestination.schedule => isEn ? 'Schedule' : '课程日程',
      DesktopWebDestination.anniversary => isEn ? 'Milestones' : '日程与纪念日',
      DesktopWebDestination.countdown => isEn ? 'Countdowns' : '倒数日',
      DesktopWebDestination.themes => isEn ? 'Themes' : '外观主题',
      DesktopWebDestination.settings => isEn ? 'Account & Settings' : '账号与设置',
      DesktopWebDestination.moreApps => isEn ? 'More Tools' : '更多应用',
    };
  }

  String sectionLabel(AppLocale locale) {
    final isEn = locale == AppLocale.en;
    return switch (section) {
      DesktopWebNavSection.workspace => isEn ? 'Workspace' : '工作区',
      DesktopWebNavSection.tools => isEn ? 'Insights & Records' : '效率与记录',
      DesktopWebNavSection.footer => isEn ? 'Preferences' : '偏好与账号',
    };
  }

  IconData get icon => switch (this) {
    DesktopWebDestination.today => Icons.wb_sunny_outlined,
    DesktopWebDestination.todo => Icons.check_circle_outline,
    DesktopWebDestination.habit => Icons.repeat_rounded,
    DesktopWebDestination.calendar => Icons.calendar_month_outlined,
    DesktopWebDestination.focus => Icons.timer_outlined,
    DesktopWebDestination.almanac => Icons.wb_twilight_outlined,
    DesktopWebDestination.goals => Icons.flag_outlined,
    DesktopWebDestination.notes => Icons.edit_note_rounded,
    DesktopWebDestination.diary => Icons.menu_book_outlined,
    DesktopWebDestination.stats => Icons.insights_outlined,
    DesktopWebDestination.timeAudit => Icons.timelapse_outlined,
    DesktopWebDestination.schedule => Icons.view_week_outlined,
    DesktopWebDestination.anniversary => Icons.celebration_outlined,
    DesktopWebDestination.countdown => Icons.hourglass_bottom_outlined,
    DesktopWebDestination.themes => Icons.palette_outlined,
    DesktopWebDestination.settings => Icons.tune_outlined,
    DesktopWebDestination.moreApps => Icons.grid_view_outlined,
  };

  IconData get selectedIcon => switch (this) {
    DesktopWebDestination.today => Icons.wb_sunny_rounded,
    DesktopWebDestination.todo => Icons.check_circle_rounded,
    DesktopWebDestination.habit => Icons.repeat_on_rounded,
    DesktopWebDestination.calendar => Icons.calendar_month_rounded,
    DesktopWebDestination.focus => Icons.timer_rounded,
    DesktopWebDestination.almanac => Icons.wb_twilight_rounded,
    DesktopWebDestination.goals => Icons.flag_rounded,
    DesktopWebDestination.notes => Icons.edit_note_rounded,
    DesktopWebDestination.diary => Icons.menu_book_rounded,
    DesktopWebDestination.stats => Icons.insights_rounded,
    DesktopWebDestination.timeAudit => Icons.timelapse_rounded,
    DesktopWebDestination.schedule => Icons.view_week_rounded,
    DesktopWebDestination.anniversary => Icons.celebration_rounded,
    DesktopWebDestination.countdown => Icons.hourglass_bottom_rounded,
    DesktopWebDestination.themes => Icons.palette_rounded,
    DesktopWebDestination.settings => Icons.tune_rounded,
    DesktopWebDestination.moreApps => Icons.grid_view_rounded,
  };

  int? get legacyTabIndex => switch (this) {
    DesktopWebDestination.today => 0,
    DesktopWebDestination.todo => 1,
    DesktopWebDestination.habit => 2,
    DesktopWebDestination.calendar => 3,
    DesktopWebDestination.focus => 4,
    DesktopWebDestination.settings => 6,
    _ => null,
  };

  static DesktopWebDestination fromLegacyTabIndex(int tab) => switch (tab) {
    0 => DesktopWebDestination.today,
    1 => DesktopWebDestination.todo,
    2 => DesktopWebDestination.habit,
    3 => DesktopWebDestination.calendar,
    4 => DesktopWebDestination.focus,
    6 => DesktopWebDestination.settings,
    _ => DesktopWebDestination.today,
  };
}

/// Metadata and right-side action slot rendered by the unified 56px topbar.
@immutable
class DesktopTopBarSpec {
  final String title;
  final String? breadcrumb;
  final String? subtitle;
  final List<Widget> actions;
  final bool showQuickSearch;
  final bool showQuickCreate;

  const DesktopTopBarSpec({
    required this.title,
    this.breadcrumb,
    this.subtitle,
    this.actions = const <Widget>[],
    this.showQuickSearch = true,
    this.showQuickCreate = true,
  });
}

/// Shared navigation and workspace appearance controller for Desktop Web views.
class DesktopWebNavController extends ChangeNotifier {
  DesktopWebNavController({
    DesktopWebDestination initialDestination = DesktopWebDestination.today,
    String? initialSelectedEntityId,
    SearchKind? initialSelectedEntityKind,
    bool? darkModeOverride,
    bool? frostedOverride,
  }) : _destination = initialDestination,
       _selectedEntityId = initialSelectedEntityId,
       _selectedEntityKind = initialSelectedEntityKind,
       _darkModeOverride = darkModeOverride,
       _frostedOverride = frostedOverride {
    if (initialSelectedEntityKind == SearchKind.todo &&
        initialSelectedEntityId != null) {
      _selectedTodoId = initialSelectedEntityId;
    }
  }

  DesktopWebDestination _destination;
  String? _selectedTodoId;
  String? _selectedEntityId;
  SearchKind? _selectedEntityKind;
  DateTime? _focusedCalendarDate;
  int _almanacTabIndex = 0;
  bool? _darkModeOverride;
  bool? _frostedOverride;
  final Map<DesktopWebDestination, DesktopTopBarSpec> _topBarSpecs =
      <DesktopWebDestination, DesktopTopBarSpec>{};
  final ValueNotifier<int> _topBarRevision = ValueNotifier<int>(0);
  bool _topBarPostFramePending = false;
  bool _disposed = false;

  DesktopWebDestination get destination => _destination;
  String? get selectedTodoId => _selectedTodoId;
  String? get selectedEntityId => _selectedEntityId;
  SearchKind? get selectedEntityKind => _selectedEntityKind;
  String? selectedIdFor(SearchKind kind) =>
      _selectedEntityKind == kind ? _selectedEntityId : null;
  DateTime? get focusedCalendarDate => _focusedCalendarDate;
  int get almanacTabIndex => _almanacTabIndex;
  bool? get darkModeOverride => _darkModeOverride;
  bool? get frostedOverride => _frostedOverride;
  ValueNotifier<int> get topBarListenable => _topBarRevision;

  void Function({
    DesktopCommandMode initialMode,
    String? initialQuery,
  })? onOpenCommandPalette;

  void Function(DesktopQuickCreateKind kind)? onQuickCreate;

  VoidCallback? onResetNestedRoutes;

  void navigateTo(
    DesktopWebDestination destination, {
    String? selectedTodoId,
    String? selectedEntityId,
    SearchKind? selectedEntityKind,
    bool clearSelectedEntity = false,
    DateTime? focusedDate,
    int? almanacTab,
  }) {
    if (_disposed) return;
    var changed = _destination != destination;
    _destination = destination;
    if (clearSelectedEntity &&
        (_selectedEntityId != null || _selectedEntityKind != null)) {
      _selectedEntityId = null;
      _selectedEntityKind = null;
      changed = true;
    }
    final resolvedEntityId = selectedEntityId ?? selectedTodoId;
    final resolvedEntityKind =
        selectedEntityKind ?? (selectedTodoId != null ? SearchKind.todo : null);
    if (resolvedEntityId != null || resolvedEntityKind != null) {
      if (_selectedEntityId != resolvedEntityId ||
          _selectedEntityKind != resolvedEntityKind) {
        _selectedEntityId = resolvedEntityId;
        _selectedEntityKind = resolvedEntityKind;
        changed = true;
      }
    }
    final resolvedTodoId =
        selectedTodoId ??
        (resolvedEntityKind == SearchKind.todo ? resolvedEntityId : null);
    if (resolvedTodoId != null && resolvedTodoId != _selectedTodoId) {
      _selectedTodoId = resolvedTodoId;
      changed = true;
    }
    if (focusedDate != null && focusedDate != _focusedCalendarDate) {
      _focusedCalendarDate = focusedDate;
      changed = true;
    }
    if (almanacTab != null) {
      final normalizedTab = almanacTab.clamp(0, 3);
      if (normalizedTab != _almanacTabIndex) {
        _almanacTabIndex = normalizedTab;
        changed = true;
      }
    }
    onResetNestedRoutes?.call();
    if (changed) {
      notifyListeners();
    }
  }

  void setAlmanacTab(int index) {
    final normalized = index.clamp(0, 3);
    if (_disposed || _almanacTabIndex == normalized) return;
    _almanacTabIndex = normalized;
    notifyListeners();
  }

  void selectTodo(String? todoId) {
    if (_disposed) return;
    final changed =
        _selectedTodoId != todoId ||
        _selectedEntityId != todoId ||
        _selectedEntityKind != (todoId == null ? null : SearchKind.todo);
    if (!changed) return;
    _selectedTodoId = todoId;
    _selectedEntityId = todoId;
    _selectedEntityKind = todoId == null ? null : SearchKind.todo;
    notifyListeners();
  }

  void selectEntity(SearchKind? kind, String? id) {
    if (_disposed) return;
    final nextId = id;
    final nextKind = id == null ? null : kind;
    var changed =
        _selectedEntityId != nextId || _selectedEntityKind != nextKind;
    _selectedEntityId = nextId;
    _selectedEntityKind = nextKind;
    if (nextKind == SearchKind.todo && _selectedTodoId != nextId) {
      _selectedTodoId = nextId;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void clearSelectedEntity() {
    if (_disposed ||
        (_selectedEntityId == null && _selectedEntityKind == null)) {
      return;
    }
    _selectedEntityId = null;
    _selectedEntityKind = null;
    notifyListeners();
  }

  void focusCalendarDate(DateTime? date) {
    if (_disposed || _focusedCalendarDate == date) return;
    _focusedCalendarDate = date;
    notifyListeners();
  }

  void openCommandPalette({
    DesktopCommandMode initialMode = DesktopCommandMode.search,
    String? initialQuery,
  }) {
    onOpenCommandPalette?.call(
      initialMode: initialMode,
      initialQuery: initialQuery,
    );
  }

  void triggerQuickCreate(DesktopQuickCreateKind kind) {
    onQuickCreate?.call(kind);
  }

  DesktopTopBarSpec? topBarSpecFor(DesktopWebDestination destination) =>
      _topBarSpecs[destination];

  void setTopBarSpec(
    DesktopWebDestination destination,
    DesktopTopBarSpec? spec,
  ) {
    if (_disposed) return;
    final previous = _topBarSpecs[destination];
    if (identical(previous, spec)) return;
    if (spec == null) {
      if (!_topBarSpecs.containsKey(destination)) return;
      _topBarSpecs.remove(destination);
    } else {
      _topBarSpecs[destination] = spec;
    }
    _bumpTopBarRevisionSafely();
  }

  void _bumpTopBarRevisionSafely() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_topBarPostFramePending) return;
      _topBarPostFramePending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _topBarPostFramePending = false;
        if (!_disposed) {
          _topBarRevision.value = _topBarRevision.value + 1;
        }
      });
      return;
    }
    _topBarRevision.value = _topBarRevision.value + 1;
  }

  void setDarkModeOverride(bool? dark) {
    if (_disposed || _darkModeOverride == dark) return;
    _darkModeOverride = dark;
    notifyListeners();
  }

  void toggleDarkMode(Brightness currentBrightness) {
    setDarkModeOverride(currentBrightness != Brightness.dark);
  }

  void setFrostedOverride(bool? frosted) {
    if (_disposed || _frostedOverride == frosted) return;
    _frostedOverride = frosted;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    onOpenCommandPalette = null;
    onQuickCreate = null;
    onResetNestedRoutes = null;
    _topBarRevision.dispose();
    super.dispose();
  }
}

/// Inherited scope exposing [DesktopWebNavController] to nested views.
class DesktopWebScope extends InheritedNotifier<DesktopWebNavController> {
  const DesktopWebScope({
    super.key,
    required DesktopWebNavController controller,
    required super.child,
  }) : super(notifier: controller);

  static DesktopWebNavController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DesktopWebScope>()
        ?.notifier;
  }

  static DesktopWebNavController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'DesktopWebScope not found in widget tree');
    return controller!;
  }
}
