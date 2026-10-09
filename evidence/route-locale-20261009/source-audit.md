# 主页面语言切换源码审阅 — 2026-10-09

## 结论

在本次限定的六个生产文件和两项 fixture 内，未发现有源码证据支持的 **must-fix** 问题。实现符合 [route locale/state 契约](/home/ubuntu/duoyi_deploy_backups/widget-refinement-20261006/route-locale-state-contract-oct9.md)：五个 public route 声明 marker，marker 优先于 bool；未标记页面保留原有 locale key 行为；目标页面以自身通知依赖刷新文案，保持 State、controller、provider owner 的挂载。

这是源码及 fixture 内容审阅，不是检查通过声明。主审后续仍需格式化及执行已授权的检查。真实计时推进、fallback/OAuth、部分子文案及实际入口路径尚未由这两项 fixture 完整证明。

## 范围与限制

只读取 `/home/ubuntu/duoyi-worktrees/route-locale-20261009` 的：

- `lib/widgets/brand_background.dart`
- `lib/screens/todo_screen.dart`
- `lib/screens/habit_screen.dart`
- `lib/screens/calendar_screen.dart`
- `lib/screens/pomodoro_screen.dart`
- `lib/screens/integrations_screen.dart`
- `test/widgets/brand_route_surface_locale_test.dart`
- `test/screens/main_route_locale_state_test.dart`

同时读取上述私有契约。未读取正在进行的 Mine 实现；未改生产源码或 fixture；未运行 Git、Flutter、Android、format、compiler、测试或网络命令。唯一写入为本私有报告。后续格式化可能移动本报告链接的行号；结论对应本次读取的源码形态。

## 1. marker、bool 与旧行为

[marker 定义](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/widgets/brand_background.dart:65) 紧邻共享 wrapper，没有导入页面、遍历 Element 或根据 StatefulWidget/StatelessWidget 类型猜测安全性。

[BrandRouteSurface 构造器及说明](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/widgets/brand_background.dart:75) 保持 const-compatible，`remountOnLocaleChange` 默认 true，明确说明它控制 **未标记** 路由的旧 remount 行为。计算为：

```dart
final shouldRemount =
    remountOnLocaleChange && child is! LocaleStatePreservingRoute;
```

[KeyedSubtree](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/widgets/brand_background.dart:113) 在两个策略下都处于 Material → BrandBackground → AppSecondaryControlTheme 的同一位置；marked 或 false 时 `key: null`，旧策略时 `ValueKey<AppLocale>(locale)`。

| child | bool | 语言变更后的策略 |
| --- | --- | --- |
| marked | 省略 / true / false | 同一无 key 子树，保留 element/State |
| unmarked | 省略 / true | 保留旧 locale key remount，用于 const 无依赖文案 |
| unmarked | false | 同一无 key 子树；child 必须自行刷新文案 |

五个 marker 都在 **public route** 上：[Todo](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/todo_screen.dart:40)、[Habit](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/habit_screen.dart:31)、[Calendar](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:42)、[Pomodoro](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:331)、[Integrations](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:28)。后两者是 stateless facade，marker 能保护其下面的 stateful body 和 provider fallback；仅判断 `child is StatefulWidget` 会漏掉它们，此实现没有采用这种判断。

无 key 策略本身只负责保留元素，不能让任意 const child 自动 rebuild。实际文案刷新由下述 page State listener 和 Integrations builder 负责。当前 wrapper 仍在每次通知时 rebuild，但其 child 对象不变不会阻止已经被自身 listener 标记为 dirty 的 State 重建。

保留旧行为意味着本批次尚未迁移的 unmarked stateful 页面仍可能随 locale key remount；契约没有声称本批次解决所有页面。marker 也不递归穿透任意 decorator。如果将来 `BrandRouteSurface(child: Padding(child: CalendarScreen()))` 或另一个会 remount 的外层包住目标页面，实际外边界还需 marker 或 false。六文件实现没有扩大 remount 范围。

## 2. listener 生命周期与状态保留

| 页面 | attach / refresh / remove 证据 | 保留项 |
| --- | --- | --- |
| Todo | [initState](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/todo_screen.dart:172)、[callback](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/todo_screen.dart:179)、[dispose](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/todo_screen.dart:259) | viewMode/filter/kanban config、batch 与 selected IDs、collapsed groups、list ScrollController、derived cache |
| Habit | [initState](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/habit_screen.dart:44)、[callback](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/habit_screen.dart:51)、[dispose](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/habit_screen.dart:56) | 两 tab 的 TabController、heatmap-built flag、稳定 scroll widget 位置/keys |
| Calendar | [initState](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:70)、[callback](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:86)、[dispose](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:96) | 五 tab controller、selected day/focused month、type/project/workspace filters、schedule/signature 状态 |
| Pomodoro body | [initState](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:443)、[callback](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:458)、[dispose](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:463) | 三 tab controller、provider owner 与 FocusRoom keep-alive State |

四个 callback 都只有 `if (mounted) setState(() {})`。每个 State 在 initState 添加一次，在 dispose 移除同一个实例方法 callback；没有在 build/didChangeDependencies 重复注册。语言事件不重读 initialDate、不重载 kanban、不清空筛选/选择、不替换 TabController，也不直接调用 timer mutation。

各页面 build 重新读取 brand strings：[Todo](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/todo_screen.dart:897)、[Habit](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/habit_screen.dart:721)、[Calendar](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:692)、[Pomodoro](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:487)。因此已使用当前 locale 文案的主页面内容会在既有 State 的 rebuild 中刷新。

Pomodoro public facade 到 [_PomodoroProviderFallback / body](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:338) 的结构不受语言 callback 改变。fallback provider 为 `late final`，load/lifecycle attach 在 [fallback initState](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:380)；保护外层 marker 后，语言变更不会销毁 timer owner。body 的初始化 DND/room 回调也只在 initState 注册，不会因语言 setState 重跑。

## 3. 新无 key 子实例能刷新文案，同时保留 State

这四个位置明确在 locale rebuild 内创建新 widget 对象，避免 identical const widget 导致子 build 被跳过：

- [HabitWeeklyCard 外部 SliverToBoxAdapter 和 card](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/habit_screen.dart:777) 均去除 const；同类型、同位置、同 key，更新 widget 而非 remount。
- [Pomodoro `_FocusRoomTab()`](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:1003) 更新现有 StatefulElement；其 [AutomaticKeepAliveClientMixin、refresh key、scroll PageStorageKey](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:2178) 保留。
- [Integrations `_LocationRemindersTab()` 和 `_LocaleTab()`](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:180) 在 builder 中是新无 key 实例；它们的 build 会重读当前 copy，即使其业务 provider 没有发通知。

创建新 Widget 不是销毁旧 State。Flutter 在 runtimeType/key/位置相同的情况下更新现有 element。这些位置没有加入 locale key、修改 tab 个数或替换 provider owner。子 widget 的 const 构造器可以保留；调用点不处于 const context 即可。

这里证明的是既有 locale-aware copy 可 refresh。文件仍有硬编码中文，例如 [Pomodoro 的“自习室”tab](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:512)、[Calendar 的“三日/年”tab](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:897)、[Todo 的部分操作文案](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/todo_screen.dart:989)。单纯 rebuild 不会翻译 literal；后续文案/编辑器迁移仍需完成。

## 4. Integrations：controller、fallback、OAuth

Integrations 复用既有 [ValueListenableBuilder](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:144)，没有给 facade/fallback 增加第二个手工 listener。该 builder 自身负责通知源的 attach/remove 生命周期。

[DefaultTabController](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:151) 无 key、固定 length 3，处于相同位置。语言 callback 返回新的 controller Widget 配置时，现有 StatefulElement 及 TabController 可以更新而保留，当前 Language tab 不回到默认 tab。

[provider fallback](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:82) 在 body builder 上方，provider 为 late final；[storage load](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:91) 只在 initState，`ChangeNotifierProvider.value` 继续暴露同一 owner。marker 保护 facade 边界，body 的语言 rebuild 不会重复 fallback 初始化。

[CalendarSubscriptions tab 的 OAuth handled guard](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:285) 仍在同一个 State；[didUpdateWidget](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/integrations_screen.dart:297) 只在 URI 变更时 reset，语言本身不会 reset。guard 在调用 dialog 前置 true。源码支持语言变更不重复处理同一 URI；fixture 尚未覆盖这条路径。

## 5. 不重复业务 mutation 的源码依据

locale callback 本身不执行业务操作。额外 build 会到达现有的 build-time schedule 方法，但它们保留去重状态：

- [Calendar schedule](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:116) 比较 `_lastCalendarInputSignature`，并用 `_calendarRebuildScheduled` 防止重复排队；[signature](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/calendar_screen.dart:175) 由日期边界、颜色和业务数据构成，没有 locale。业务输入未变且已 settle 时，纯语言 setState 不安排另一轮 rebuild mutation。午夜或业务更新本身改变 signature 时，正常数据刷新仍会发生。
- [FocusRoom refresh](/home/ubuntu/duoyi-worktrees/route-locale-20261009/lib/screens/pomodoro_screen.dart:2250) 保留 `_lastRefreshKey`、`_refreshScheduled`。key 由 joined IDs、Pomodoro persistedRevision、displayName 组成，没有 locale。在现有 State 保留且业务输入不变时，新 `_FocusRoomTab()` 的 widget 更新不会重复 watch/load/sync。第一次打开 tab 仍会进行正常初始化。
- Todo kanban loading、Pomodoro DND/room 初始化、Integrations fallback storage load 在 initState。marker 阻止语言 remount，也就阻止这些初始化被语言事件重新触发。

以上是源码推断，没有 mutation-spy fixture 或调用次数检查。任何非语言业务变化仍可以触发正常 mutation；不能把所有刷新调用都归咎于语言事件或要求永久不刷新。

## 6. fixture 真实证明了什么

### wrapper fixture

[brand_route_surface_locale_test.dart](/home/ubuntu/duoyi-worktrees/route-locale-20261009/test/widgets/brand_route_surface_locale_test.dart:171) 对契约的覆盖准确：

- unmarked const StatelessWidget 只读 `I18n.tr` 的旧行为仍覆盖；语言事件没有外层 repump。
- marked const StatefulWidget 保存 State/controller 对象、draft、counter，以及 init/dispose 次数。
- marked StatelessWidget facade 返回 stateful body，直接覆盖两种真实 facade 的类型形态。
- unmarked self-refreshing widget + false，以及 marked widget + 明确 true，都经相同生命周期断言。
- 测试通过真实 Navigator push/pop；locale 后只 pump；pop 后再通知，并检查 callback count 未增加。这个断言能检测 mounted-guarded listener 泄漏，比仅 `takeException == null` 更强。

host 使用 [const MaterialApp](/home/ubuntu/duoyi-worktrees/route-locale-20261009/test/widgets/brand_route_surface_locale_test.dart:162)，locale 本身固定，避免根 MaterialApp 更新遮盖 page notifier 缺失。`pumpWidget` 只在每个 case 开始。

### 主页面 fixture

[main_route_locale_state_test.dart](/home/ubuntu/duoyi-worktrees/route-locale-20261009/test/screens/main_route_locale_state_test.dart:315) 有一项 marker 声明测试和六项 widget case：

| case | 实际断言 |
| --- | --- |
| Todo | 从 matrix 改为 list、完成状态 filter、非零 offset；raw zh/en 事件后 State、provider、ScrollController 身份及夹限后的 offset 保留，title 更新 |
| Habit | 先打开 heatmap，raw 事件后 State、provider、TabController/index 保留，heatmap copy 更新 |
| Pomodoro | 先选 History，raw 事件后 TabController/index、外部 provider、session List/item 身份保留，title 更新 |
| Calendar wrapped | initialDate 后改成另一日/Day tab；raw 事件后 State/controller/index 和日期标签保留、copy 更新 |
| Calendar direct | 没有 BrandRouteSurface，也保持 changed date/tab/State 并刷新 copy |
| Integrations | 通过 Language tab UI 选择语言，controller 身份和 index 2 保留，title、语言 labels、radio 更新 |

这些 case 不会在语言事件之间重新 pumpWidget。其 MaterialApp 不 watch LocaleProvider 更新 flutterLocale，因此 raw event 必须由页面自己的 notifier 路径处理。Calendar 的非 const host 也只在 case 开头实例化一次，不会在事件时重新构造父树。

## 7. 验收限制

以下不是本次发现的 introduced must-fix；它们限制“已经验证完成”的说法：

1. **专注真实计时与 mutation**：[_MemoryPomodoroProvider](/home/ubuntu/duoyi-worktrees/route-locale-20261009/test/screens/main_route_locale_state_test.dart:66) 覆盖 getter，返回固定 `_fixtureState`；测试不启动真实 timer、不推进 clock。它证明 provider/tab/controller/session 身份保留，却不能证明真实 remainingSeconds 单调推进、timer lifecycle 无重挂或 mutation 没有重复。固定 getter 也可能掩盖 inherited mutation 对 provider 私有 state 的变化；未来真实计时或 mutation-spy 验收需要独立路径。
2. **真实 provider fallback/OAuth**：Integrations fixture 主动提供所有 optional providers；Pomodoro fixture 也提供全部依赖。没有 fallback-owned provider 的身份/load 次数断言，没有重复 OAuth dialog 防护断言。
3. **四处 const 子边界**：fixture 未直接验证 HabitWeeklyCard weekdays/status、FocusRoom tab copy/scroll、Integrations Location tab copy 在 raw event 后更新；它们符合源码更新机制，但仍是 source-backed。
4. **业务状态覆盖**：Todo fixture 使用 read-only ShareProvider，不覆盖 batch selected IDs、collapsed groups、kanban config；Habit 未保存非零 scroll offset；Calendar 未覆盖 type/project/workspace filter/focused-month 状态。字段未被 locale callback 修改，但实际 UI 验收尚不完整。
5. **mutation 次数与真实入口**：没有 Calendar rebuild/FocusRoom load-sync 的调用计数，也没有实际 Today/Search/main widget URI/Mine/Calendar event sheet 路径或 settings 覆盖后返回的 offstage case。契约原先的 call-site 审阅支持无需新增 flag；本次限定审阅没有重新读取这些 call-site 文件。
6. **真实页面 listener cleanup**：wrapper probe 明确检查 pop 后 callback count；六个页面 case 主要挂在 MaterialApp home，未分别 pop 五个真实页面后检查 callbacks。四个生产 listener 的平衡由源码成立。
7. **完整英文化/编辑器**：上述 literal、独立 modal builder 捕获的标题/草稿、picker caller key 迁移均不能由本批次 route listener 自动解决。
8. **实际执行结果**：本审阅没有运行 fixture，未读取主审稍后的格式化/检查结果，因此不声明测试通过、无 analyzer/compiler 问题或构建可交付。

## 建议

本批次可以继续进入主审的格式化与已授权检查，没有来自本次源码审阅的额外 AGY production must-fix。检查通过后可以按限定的“主页面语言切换保留状态”范围合入；报告/最终说明应保留真实计时、fallback/OAuth、实际入口和完整文案迁移的验收限制。后续针对这些缺口增加验收时，不要通过 locale key remount 或重建 controller 来修复 copy，也不要把固定 provider 状态等同于真实专注计时验证。
