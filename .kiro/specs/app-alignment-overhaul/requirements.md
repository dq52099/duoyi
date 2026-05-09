# Requirements Document: App Alignment Overhaul（指尖时光对齐打磨）

## Introduction

本需求文档由已确认的 `design.md` 反推而成，覆盖设计文档中 A–J 十个方向以及 20 条 Correctness Properties（P1–P20）。目标是把"指尖时光（duoyi）"从"毛坯房中的毛坯房"推进到"功能对齐、交互一致、空架子清零、时区与提醒正确、白噪音真实播放、可通过属性测试"的可上线状态。

需求采用 EARS（Easy Approach to Requirements Syntax）风格，中文书写。条目级编号 `X.Y` 将被 `tasks.md` 引用，`design.md` 的 Correctness Properties（P1–P20）被成对映射到对应条目。

## Glossary

- **系统 / System**：指尖时光客户端（Flutter/Dart）与其后端（`backend/main.py`）协同组成的整体应用。
- **Goal / 目标**：用户创建的长期目标，含类别、重复规则、调度模式、节假日跳过、专注联动、提醒、目标时长 / 每日次数等。
- **Todo / 任务**：用户创建的短期任务，含子任务、标签、优先级、提醒、专注联动、顺延历史。
- **Habit / 习惯**：周期性打卡项，沿用现有模型。
- **RecommendedGoal / 推荐目标**：内置目标库中的条目，可被一键实例化为用户自己的 Goal。
- **RecurrenceRule**：重复规则（daily / weekly / monthly / yearly / none，含 interval、byWeekdays、endDate）。
- **GoalScheduling**：目标的调度模式，含 `fixed`（固定星期/月日）与 `random`（指定上下限随机派发）。
- **ReminderConfig**：提醒配置，含 `kind ∈ {push, alarm}`、时间、是否震动、是否全屏等。
- **NotificationChannel / 通知通道**：`duoyi_general`，`Importance.high`，用于非强阻断的"消息"。
- **AlarmChannel / 闹钟通道**：`duoyi_alarm`，`Importance.max`，`fullScreenIntent=true`，用于"一定要处理"的提醒。
- **ReminderScheduler**：Provider 数据变化时做幂等同步的协调器。
- **FocusSoundService**：真实白噪音音频播放服务（基于 `audioplayers`）。
- **LocalTimezoneResolver**：统一的本地时区解析器，封装 `flutter_timezone` + `timezone`。
- **HolidayCalendar**：节假日与调休判定服务。
- **CompletionVisibilityPolicy**：完成态"当日保留、次日归档"的可见性策略。
- **DailyRollover**：每天 00:00（本地时区）执行的批处理：归档昨日完成项、顺延过期未完成项、按重复规则派发今日实例。
- **TodayDetailRouter**：今日页各 section "查看"按钮的统一路由入口。
- **EmptySurfaceAuditor**：空架子扫描器，产出 `docs/empty-surface-audit.md` backlog。
- **AsyncState**：统一的异步三态封装（`AsyncLoading / AsyncData / AsyncError`）。
- **DesignTokens**：统一的色板、圆角、间距、字阶 token 集合。
- **CloudSync v2 / cloud_sync_v2**：后端契约对齐的特性开关，用于分阶段开启 API 同步。

## Requirements

### Requirement 1：推荐目标库与 Goal 扩展字段

**User Story**：作为一名想持续成长的用户，我希望从类别化的推荐目标库中一键添加目标，并能在编辑页完整配置目标的重复、调度、节假日、专注、提醒、目标时长与每日次数，以便让一个目标真正"可运行"。

#### Acceptance Criteria

1. THE 系统 SHALL 在 `GoalItem` 模型上提供 `category`（枚举 `GoalCategory ∈ {recommend, health, study, sport, emotion, custom}`）、`icon`、`recurrence`、`scheduling`、`skipHolidays`、`focusLink`、`reminder`、`timeTargetSeconds`、`dailyTargetCount` 字段。
2. WHEN 旧版本 `GoalItem` JSON 缺失上述新增字段，THE 系统 SHALL 使用向后兼容的默认值（`category = custom`、`skipHolidays = false`、`focusLink.enabled = false`、`reminder.enabled = false`）反序列化，并在下次保存时补齐字段。
3. THE 系统 SHALL 在 `lib/core/recommended_goals.dart` 中提供 `RecommendedGoalsLibrary`，内置 5 大类 `{health, study, sport, emotion, recommend}`，每类不少于 5 条、合计不少于 25 条推荐目标。
4. WHEN 用户在 `RecommendedGoalsPicker` 中点击一条推荐目标，THE 系统 SHALL 通过 `RecommendedGoalsLibrary.instantiate` 生成一个带新 UUID 的 `GoalItem` 并调用 `GoalProvider.add` 写入本地存储。
5. THE 系统 SHALL 提供 `GoalEditScreen`，把"基础信息 / 重复规则 / 调度模式 / 跳过节假日 / 专注联动 / 提醒 / 目标时长 / 每日次数"分模块折叠展示，且每个模块可独立保存。
6. WHERE 用户选择 `scheduling.mode = fixed` 且 `recurrence.frequency = weekly`，THE 系统 SHALL 允许设置 `fixedWeekdays ⊆ {0..6}`（周一=0）。
7. WHERE 用户选择 `scheduling.mode = fixed` 且 `recurrence.frequency = monthly`，THE 系统 SHALL 允许设置 `fixedMonthDays ⊆ {1..31}`。
8. WHERE 用户选择 `scheduling.mode = random`，THE 系统 SHALL 允许设置 `randomMinGapDays ≥ 1`、`randomMaxPerWeek` 与 `randomMaxPerMonth`（至少其一）。
9. THE 系统 SHALL 在 Goal 详情页同时展示"下一次派发日"（由 `RecurrenceEngine.nextOccurrence` 计算）。
10. IF 用户在编辑 Goal 过程中填写非法区间（如 `randomMinGapDays < 1`、`fixedMonthDays` 含 `32`），THEN THE 系统 SHALL 阻止保存并提示具体错误字段。

### Requirement 2：Todo 模型扩展与交互（子任务 / 标签 / 优先级 / 顺延 / 保存不返回）

**User Story**：作为需要精细管理一天事务的用户，我希望 Todo 支持子任务、多标签、优先级、目标时长、自动顺延、保存不返回等交互，让任务详情页变成"可以连续修改而不来回跳"的工作面板。

#### Acceptance Criteria

1. THE 系统 SHALL 在 `TodoItem` 模型上新增 `focusLink`、`reminder: ReminderConfig`（替代旧 `hasReminder + reminderAt`）、`timeTargetSeconds`、`postponeHistory: List<PostponeRecord>` 字段，并保留既有 `subtasks`、`tags`、`priority`、`dueDate`、`isCompleted`、`completedAt` 字段语义。
2. WHEN 旧版 Todo JSON 缺失 `focusLink / reminder / timeTargetSeconds / postponeHistory` 任一字段，THE 系统 SHALL 反序列化为安全默认值并下次写入时补齐。
3. WHEN 用户在 `TodoDetailScreen` 修改任一字段（标题、描述、子任务、标签、优先级、dueDate、提醒、专注联动、目标时长），THE 系统 SHALL 将本地状态标记为 `Editing`。
4. WHEN 用户在 `TodoDetailScreen` 处于 `Editing` 且点击 AppBar 的保存按钮，THE 系统 SHALL 持久化改动、保持当前路由不 pop、在页面内以 inline banner 展示"已保存"反馈，并把状态置回 `Clean`。
5. IF 用户在 `Editing` 状态下点击返回键或返回按钮，THEN THE 系统 SHALL 弹出"放弃修改"确认对话框，用户确认后才允许 pop。
6. WHERE `TodoItem.subtasks` 非空，THE 系统 SHALL 以 `done/total` 的比例计算并暴露 `subtaskProgress ∈ [0, 1]`。
7. WHEN 所有子任务全部完成，THE 系统 SHALL 将 `subtaskProgress` 置为 `1.0`。
8. WHERE `autoToggleByChildren = true` 且 `subtasks ≠ ∅`，WHEN `subtaskProgress` 变为 `1.0`，THE 系统 SHALL 自动把父任务 `isCompleted` 置为 `true` 并写入 `completedAt`。
9. WHERE `autoToggleByChildren = true` 且 `subtasks ≠ ∅`，WHEN 用户取消任一子任务，THEN THE 系统 SHALL 自动把父任务 `isCompleted` 置为 `false` 并清空 `completedAt`。
10. WHEN `DailyRollover` 遍历 todos 且遇到 `isCompleted = false ∧ dueDate < today 00:00 (local)`，THE 系统 SHALL 将 `dueDate` 顺延到今日同时刻（保持 `hour / minute` 不变），追加一条 `reason = "auto_daily_rollover"` 的 `PostponeRecord`，并在开启提醒时触发 `ReminderScheduler` 重同步。
11. THE 系统 SHALL 保证 `postponeOverdue` 算法对同一个 `todos` 二次调用产生相同的 `dueDate`（除 `postponeHistory` 被追加一条新记录外）。
12. THE 系统 SHALL 在 Todo 列表项同时展示：标签胶囊、优先级色标、目标时长剩余、下一次提醒时刻。

### Requirement 3：完成态保留与 DailyRollover

**User Story**：作为一名希望"看见自己完成过什么"的用户，我希望任务完成后仍然保留在今日列表里，只通过颜色与徽章做视觉区分，次日零点才淡出，从而避免"打勾即消失"带来的失落感。

#### Acceptance Criteria

1. WHEN 用户在今日列表 `toggleTodo(id)` 把任务从未完成切为完成，THE 系统 SHALL 保持该任务仍在 `provider.todos` 中、仍在今日列表展示、`visualState(t) = completed`、`completedAt = now`。
2. THE 系统 SHALL 对 `TodoVisualState` 按 `{normal, dueSoon, overdue, completed, archived}` 五档渲染，每档绑定 `DesignTokens` 中对应颜色（normal=onSurface，dueSoon=orange.shade400，overdue=red.shade400，completed=green.shade400+删除线+灰度 70%，archived=grey.shade400）。
3. THE 系统 SHALL 在每日本地 00:00 或 `AppLifecycleState.resumed` 且日期跨天时触发一次 `CompletionVisibilityPolicy.runDailyRollover(now)`。
4. WHEN `runDailyRollover(now)` 执行完成，THE 系统 SHALL 使得 `{t | t.isArchivedAfterRollover = true}` 与 `{t | t.isCompleted ∧ dateOnly(t.completedAt) < today}` 完全相等。
5. IF 任意 `t.isArchivedAfterRollover = true`，THEN THE 系统 SHALL 保证 `t.isCompleted = true`。
6. IF 任意 `t.isCompleted = true`，THEN THE 系统 SHALL 保证 `t.completedAt ≠ null`。
7. THE 系统 SHALL **禁止**在"用户完成一条任务"路径上触发物理删除，物理删除只能由显式的"长按/滑动 + 二次确认"操作触发。
8. THE 系统 SHALL 在"统计 / 历史"面板中允许查询到 `archived` 与 `completed` 的任务。

### Requirement 4：通知与闹钟的严格分层

**User Story**：作为一名只想在"非重要事件"被轻推、而在"必须到点处理"时被强提醒的用户，我希望系统把所有提醒路径按 push / alarm 两类严格分层，绝不用 Toast 假装提醒。

#### Acceptance Criteria

1. THE 系统 SHALL 提供 `NotificationService`（仅 push）、`AlarmService`（仅 alarm）、`ReminderScheduler`（协调器）三个类，职责互不重叠。
2. THE 系统 SHALL 在 Android 上声明通知渠道 `duoyi_general`（`Importance.high`）与 `duoyi_alarm`（`Importance.max`、`fullScreenIntent=true`、`vibrationPattern=[0,500,500,500]`）。
3. THE 系统 SHALL 在 Android `AndroidManifest.xml` 中声明 `SCHEDULE_EXACT_ALARM`、`USE_FULL_SCREEN_INTENT`、`FOREGROUND_SERVICE` 权限。
4. WHEN `ReminderConfig.kind = push`，THE `ReminderScheduler._dispatch` SHALL 最终调用 `LocalNotifications.scheduleOnce / scheduleDaily`。
5. WHEN `ReminderConfig.kind = alarm`，THE `ReminderScheduler._dispatch` SHALL 最终调用 `AlarmService.scheduleFullScreen`，并使用 `duoyi_alarm` 渠道。
6. WHERE `ReminderConfig.enabled = true`，THE 系统 SHALL **禁止**以 `ScaffoldMessenger.showSnackBar` 或 Toast 作为唯一落地形式；系统内提示只允许作为前台时的**镜像**。
7. WHEN 时区发生变化、权限状态变化、应用冷启动，THE `ReminderScheduler.resyncAll` SHALL 依次取消自己管过的 id、再按最新 Provider 数据重新下发调度。
8. THE `ReminderScheduler` SHALL 在同一数据源多次调用 `syncTodos / syncGoals / syncHabits / syncAnniversaries` 时保持幂等（先取消再下发）。
9. IF `AlarmService.scheduleFullScreen` 在 Android 12+ 因缺少精准闹钟权限失败，THEN THE 系统 SHALL 返回可重试错误并提示用户引导至系统设置。

### Requirement 5：专注模式白噪音真实播放

**User Story**：作为希望通过白噪音进入专注状态的用户，我希望番茄钟启动后白噪音真的在扬声器循环播放、前后台切换不掉线、暂停/完成能及时停止。

#### Acceptance Criteria

1. THE 系统 SHALL 在 `assets/sounds/white_noise/` 提供至少 4 条循环音轨：`rain.mp3`、`forest.mp3`、`cafe.mp3`、`waves.mp3`，并在 `pubspec.yaml` 的 `flutter.assets` 中声明。
2. THE 系统 SHALL 在 `pubspec.yaml` 中引入 `audioplayers: ^6.x` 依赖。
3. THE 系统 SHALL 提供 `FocusSoundService`（单例），暴露 `play(String sound)` / `stop()` / `setVolume(double v)` / `fadeIn(Duration)` / `fadeOut(Duration)` / `bindLifecycle(WidgetsBinding)` / `currentSound` / `isPlaying` / `volume` 等接口。
4. THE `FocusSoundService.play` SHALL 使用 `ReleaseMode.loop` + `PlayerMode.lowLatency` 实现无缝循环。
5. WHEN `PomodoroState` 从 `isRunning = false` 转为 `isRunning = true` 且 `whiteNoiseSound ≠ 'none'`，THE 系统 SHALL 保证调用完成后 `FocusSoundService.isPlaying = true ∧ FocusSoundService.currentSound = whiteNoiseSound`。
6. WHEN 番茄钟触发 pause / reset / complete，THE 系统 SHALL 在 500ms 内把 `FocusSoundService.isPlaying` 置为 `false`（允许 `fadeOut(300ms)` 过渡）。
7. WHERE 白噪音正在播放，THE 系统 SHALL 在 Android 上以 `ForegroundService(type = mediaPlayback)` 方式维持播放不被锁屏杀死。
8. WHEN 用户在系统设置里静音应用音量，THE `FocusSoundService` SHALL 维持 `isPlaying = true` 状态一致，但不发声（由系统音量控制）。
9. WHEN `PomodoroProvider` 切换 `whiteNoiseSound` 为 `'none'`，THE `FocusSoundService` SHALL 等价于 `stop()`。

### Requirement 6：Today 详情路由修复

**User Story**：作为每日进入"今日"页查看事项的用户，我希望每个 section 的"查看"按钮都不再黑屏、空数据也能优雅回退。

#### Acceptance Criteria

1. THE 系统 SHALL 提供 `TodayDetailRouter.open(ctx, TodaySectionKind kind, {String? id})` 作为"今日"各 section "查看"按钮的统一入口。
2. THE `TodayDetailRouter` SHALL 覆盖 `TodaySectionKind ∈ {todos, courses, anniversaries, goals, habits, diary}` 全部取值。
3. WHEN 目标数据不存在（id 无效 / 已删除 / section 本身为空），THE `TodayDetailRouter` SHALL 跳转至 `EmptyState` 回退页，而不是黑屏。
4. IF 路由构建阶段抛出异常，THEN THE 系统 SHALL 跳转至 `ErrorState` 页并提供"重试"按钮。
5. THE 今日页 SHALL **禁止**在 section 的 `onMore` 回调中直接调用 `Navigator.push` 到可能为 null 的页面；所有跳转必须经由 `TodayDetailRouter`。

### Requirement 7：日历视图按日期过滤

**User Story**：作为喜欢按月视图浏览事务的用户，我希望点击日历里的某一天后，下方列表就能聚合当天所有事项。

#### Acceptance Criteria

1. THE `CalendarMonthGrid` SHALL 暴露 `OnDayTap? onDayTap` 回调与 `DateTime? selectedDay` 入参。
2. WHEN 用户点击月视图中的某一天，THE 系统 SHALL 通过 `onDayTap(day)` 通知父级并高亮选中日。
3. THE `CalendarScreen` SHALL 订阅 `selectedDay`，并在下方列表区聚合展示当日的 `TodoItem`、`Anniversary`、`Course`、`GoalOccurrence`、`HabitOccurrence`。
4. WHEN 用户点击另一天，THE 列表区 SHALL 立即刷新为新日期的聚合结果。
5. WHERE 选中日无任何事项，THE 列表区 SHALL 展示 `EmptyState`（含"新建"快捷入口）。

### Requirement 8：时区本地化

**User Story**：作为可能跨时区出差或切换系统时区的用户，我希望所有调度的"壁钟时间"始终按我设备当前的本地时区理解。

#### Acceptance Criteria

1. THE 系统 SHALL 在 `main.dart` 首帧之前调用 `LocalTimezoneResolver.init()`。
2. THE `LocalTimezoneResolver.init` SHALL 依次尝试：`flutter_timezone.FlutterTimezone.getLocalTimezone()` → 失败回退到 `DateTime.now().timeZoneName` 对应 IANA → 再失败固定回退 `Asia/Shanghai`，并在非理想路径上写入日志。
3. THE `LocalTimezoneResolver.init` SHALL 调用 `tz.setLocalLocation(tz.getLocation(name))` 使 `tz.local` 指向解析结果。
4. WHERE 系统代码需要生成"某时刻的调度时间"，THE 系统 SHALL 统一使用 `tz.TZDateTime.from(dateTime, tz.local)`。
5. THE 系统 SHALL **禁止**在调度路径上直接构造 `DateTime.utc(...)` 并传入 `flutter_local_notifications.zonedSchedule`。
6. WHEN 应用进入 `AppLifecycleState.resumed` 且探测到设备 IANA 时区变化，THE 系统 SHALL 重新调用 `tz.setLocalLocation` 并触发 `ReminderScheduler.resyncAll`。
7. THE 系统 SHALL 保证：对于 `ReminderConfig(kind=alarm, hour=H, minute=M)` 在本地触发日 `D` 的调度，最终的 `tz.TZDateTime T` 满足 `T.timeZoneName == tz.local.name ∧ T.hour == H ∧ T.minute == M ∧ dateOnly(T) == D`。
8. THE 系统 SHALL 保证：设备时区由 `tz1` 切至 `tz2` 后，`resyncAll` 重新调度的闹钟在新时区下的 `(hour, minute)` 仍等于用户原设定（壁钟时间不变、绝对 UTC 时间变）。

### Requirement 9：空架子扫描与补齐

**User Story**：作为需要对 MVP 质量负责的开发者，我希望通过一个工具列出所有"空架子 / 占位 UI / 假数据"并推进到 tickets，从而逐步清零。

#### Acceptance Criteria

1. THE 系统 SHALL 在 `lib/core/empty_surface_auditor.dart` 提供 `EmptySurfaceAuditor`，含静态 `known: List<EmptySurfaceEntry>` 与 `runtimeAudit(BuildContext)`。
2. THE `EmptySurfaceAuditor.known` SHALL 至少覆盖以下已知占位：`lib/services/audio_service.dart`（_isPlaying 假播放）、`lib/screens/today_screen.dart`（部分 section 查看黑屏），并允许随实现进度追加。
3. THE 系统 SHALL 提供扫描脚本（或文档化方法）对仓库执行以下匹配：`TODO`、`FIXME`、`Placeholder`、`假数据`、`mock`、`hardcoded`、仅 `return Container();` / `return const SizedBox();` 的 build 方法、立即 resolve 的 `Future.value()` / 空 `async {}`。
4. THE 系统 SHALL 把扫描结果写入 `docs/empty-surface-audit.md` 作为 backlog，并与 `tasks.md` 中的"补齐任务"互相引用。
5. WHEN 实现阶段关闭一条 entry，THE 系统 SHALL 要求在 `EmptySurfaceEntry.fixTicketId` 字段填入对应任务 id。

### Requirement 10：视觉、空态、错误态与 AsyncState 打磨

**User Story**：作为使用应用的人，我希望界面在加载中、空数据、失败时都有一致、美观、可操作的反馈，而不是白屏或卡顿。

#### Acceptance Criteria

1. THE 系统 SHALL 在 `lib/core/design_tokens.dart` 提供统一的 `DesignTokens`（颜色、圆角、间距、阴影、字阶），并在后续所有新写 UI 中使用。
2. THE 系统 SHALL 在 `lib/widgets/result_states.dart` 提供 `EmptyState`（扩展 `action` 回调）、`LoadingState`（shimmer）、`ErrorState`（接收 `Object error, VoidCallback onRetry`）三件套。
3. THE 系统 SHALL 在 Provider 层以 `sealed class AsyncState<T> = AsyncLoading<T> | AsyncData<T> | AsyncError<T>` 表达异步三态。
4. WHEN UI 构建读取到 `AsyncLoading`，THE 系统 SHALL 渲染 `LoadingState`。
5. WHEN UI 构建读取到 `AsyncError(e)`，THE 系统 SHALL 渲染 `ErrorState(error: e, onRetry: …)`。
6. WHEN UI 构建读取到 `AsyncData(data)` 且 `data.isEmpty = true`，THE 系统 SHALL 渲染 `EmptyState`。
7. WHERE 页面需要二次确认（放弃编辑、物理删除、取消提醒），THE 系统 SHALL 使用同一套对话框样式 token。

### Requirement 11：重复、随机、跳节假日与稳定种子

**User Story**：作为一名想让目标按"周三/周五固定派发"或"每周随机两天派发"同时跳过法定节假日的用户，我希望引擎在派发上既灵活又稳定，不会每次刷新都漂移。

#### Acceptance Criteria

1. THE 系统 SHALL 提供 `RecurrenceEngine.nextOccurrence(rule, scheduling, skipHolidays, anchor, {now})` 与 `enumerateOccurrences(rule, scheduling, skipHolidays, start, end)`。
2. THE 系统 SHALL 提供 `HolidayCalendar` 服务，暴露 `isHoliday(day) / isWorkMakeupDay(day)`，数据允许以内置 JSON 或远端可更新形式承载。
3. WHERE `rule.frequency = weekly ∧ interval = k`，THE `nextOccurrence` 返回值 `next` SHALL 满足 `1 day ≤ next − anchor ≤ 7 × k days`。
4. WHERE `rule.endDate = E ≠ null`，THE `nextOccurrence` SHALL 要么返回 `null`，要么返回 `result ≤ E`。
5. WHERE `scheduling.mode = random`，THE `nextOccurrence` SHALL 在 `[anchor + max(1, randomMinGapDays), upperBound]` 区间内以 `stableSeed(goalId, yearWeek(lowerBound))` 为种子采样。
6. WHEN 同一 `goalId` 在同一"年-周"内被多次计算 `nextOccurrence`，THE 系统 SHALL 返回相同日期（稳定种子保证）。
7. WHERE `skipHolidays = true`，THE `nextOccurrence` 返回值 `next` SHALL 满足 `HolidayCalendar.isHoliday(next) = false`，除非整个随机窗口全为节假日，此时回落到窗口内最后一个非节假日或返回 `null`（实现必须二选一并在测试中一致断言）。
8. THE 系统 SHALL 在 `DailyRollover` 中调用 `materializeTodayFromRecurring(today)`，对所有 `status = active` 的 Goal，若 `nextOccurrence = today` 则生成当日 occurrence 并触发 `ReminderScheduler.scheduleFor`。

### Requirement 12：离线优先与后端契约对齐

**User Story**：作为在地铁/弱网环境下也要用应用的用户，我希望本地写入立即生效、网络恢复后自动同步到后端；同时后端接口契约跟客户端一致。

#### Acceptance Criteria

1. THE 系统 SHALL 采用 Offline-First：本地写入 → Provider 持久化到 `SharedPreferences` → `CloudSync` 排队 → `ApiClient` 推送。
2. THE 系统 SHALL 为所有可同步实体（Goal、Todo、Habit、Anniversary）使用 UUID v4 作为主键。
3. WHERE 请求体中含日期时间字段，THE 系统 SHALL 使用 `DateTime.toLocal().toIso8601String()` 并额外携带 `tz: "<IANA 名>"` 字段。
4. THE 后端（`backend/main.py`）SHALL 仅持久化 UTC 时间 + tz 名，由客户端在渲染时转换回本地。
5. THE `POST /api/v1/goals` 请求体 SHALL 对齐以下字段：`id, title, category, icon, colorValue, recurrence{frequency, interval, byWeekdays}, scheduling{mode, randomWindow{minGapDays}}, skipHolidays, focus{enabled, preset, sound}, reminder{kind, time, daysBefore}, timeTargetSeconds, dailyTargetCount`。
6. THE 系统 SHALL 以特性开关 `cloud_sync_v2` 分阶段开启后端同步；`cloud_sync_v2 = false` 时客户端功能完全可用（仅本地）。
7. IF 网络请求失败，THEN THE `CloudSync` 队列 SHALL 以指数退避方式重试，最多 5 次，并在 UI 侧通过小角标表示"有未同步改动"。
