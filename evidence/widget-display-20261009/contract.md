# Widget display contract — source audit, 2026-10-09

审阅基线：`/home/ubuntu/duoyi-worktrees/native-locale-20261009`。仅阅读源代码；未调用 Git，未运行 tests / analyze / build，也未改动仓库。已有 `widget-next-capability-inventory-oct9.md` 仅作为线索，以下结论重新追踪 Flutter producer 与 deep-link consumer 后形成。根代理已另建实施工作树 `widget-display-20261009`，本报告不写入该树。

结论：Android 纪念日应将 `anniversary_highlight_1/2` 与 `memorial_highlight_1/2/3` 合成有序、按目标身份去重的成对记录；`today_event_summary_id` 当前不存在，Calendar 事件摘要可使用同一 snapshot 的 `schedule_highlight_1_id`；iOS 月网格可以独立按 `entry.date` 绘制，现有 consumer 尚不能消费日期链接，增加 URL 参数本身不会选中日期。

## 1. Flutter 实际发布的纪念日数据

| 层次 | 源码证据 | 已确认含义 |
| --- | --- | --- |
| 所有类型列表 | [anniversary_provider.dart:19](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/providers/anniversary_provider.dart:19) | `items` 是完整 `_items` 副本，先 pinned，再按 daysRemaining 排序；不是“排除 memorial 的另一类”。 |
| memorial 子集 | [anniversary_provider.dart:39](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/providers/anniversary_provider.dart:39) | `memorials` 是 `_items` 中 type=memorial 的子集，保留原存储顺序，没有使用 items 的 pinned/days 排序。 |
| 两条综合记录 | [main.dart:2735](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2735) | 从 `a.items` 筛 daysRemaining≥0，再取 2；标题和 id 从同一个 `anniversaryItems` 列表逐项映射。 |
| 三条 memorial 记录 | [main.dart:2749](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2749) | 从 `a.memorials` 筛 daysRemaining≥0，再取 3；标题和 id 从同一个 `memorialItems` 列表逐项映射。 |
| 综合记录持久化 | [home_widget_service.dart:543](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:543) | 只写 `anniversary_highlight_1/2` 及各自 `_id`。真实文本加 `· ` 前缀；空集合第一条是已本地化 placeholder，第二条空白；没有 anniversary 3。 |
| memorial 持久化 | [home_widget_service.dart:591](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:591) | 写 `memorial_highlight_1/2/3` 及各自 `_id`，同样真实文本加 `· `，第一条空集合 placeholder，后续为空。 |
| 目标值 | [main.dart:2746](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2746)、[main.dart:2760](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2760) | 两组 `_id` 都是完整 `duoyi://anniversary/${Uri.encodeComponent(item.id)}` URI，不是两个不同路由，也不是数值 id。 |
| 清理默认值 | [home_widget_service.dart:72](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:72)、[:88](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:88) | 清理 A1/A2、M1/M2/M3 及其 id。A3 不在当前发布或清理契约内，不能当新排序的数据来源。 |

真实重复示例：综合列表首条是 memorial X，memorial 子集首条也为 X，则 A1 和 M1 文本/target 均可相同。即使同一对象分别落在 A2、M3，仍须只出现一次。不同对象恰好同标题时不能按文本去重。

标题已经在 Flutter 格式化为“原始标题 + 距下次还有 N 天”。[anniversary.dart:118](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/models/anniversary.dart:118) 中 normal 使用原日期，birthday/memorial 计算下一次年度日期；[:165](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/models/anniversary.dart:165) 计算 daysRemaining。当前 producer 过滤负数；原生展示整改不能改成过去日期计数或重算农历/循环/天数。

### Android 有界实施契约

在 provider 中一次构造记录：`{sourceKey, text, rawTarget, effectiveTarget, identity}`。顺序固定为 A1 → A2 → M1 → M2 → M3，保持各数组 producer 顺序；逐项选取后才取当前密度需要的前 1/2/3 条。不要重新按文本、天数或类别排序。

每条文本与其 **同一 sourceKey** 的 `_id` 绑定。不得先独立选 text，再从另一组/另一槽位取 id。当前 [DuoyiAnniversaryWidgetProvider.kt:75](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt:75) 按槽位读文本，[:132](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt:132) 另走 id fallback，应替换为同一选择结果直接用于 setText 与 click intent。

候选与去重规则：

- 空/纯空白 text 跳过；有非空 id 的文本保留原样，不能因为文本等于某个 fallback 字符串而删除用户记录。
- **只有无 id** 的候选，才按已知中英文空文案识别 placeholder。识别时可 trim 并去掉一个展示 `· ` 前缀；只用于识别，不改写真实原文。当前 Flutter 空集合默认分支写无 bullet 的 placeholder，真实记录分支写 bullet；旧/其他 snapshot 中的 bullet placeholder 也应兼容。
- 合法当前 URI 只接受 `duoyi://anniversary/<单个非空、正确编码的 id segment>`。legacy raw id 可以沿用当前 provider 的 `Uri.encode(rawId)` 包装为 anniversary URI。解析时先分 path segment 再解码，保留 item id 的大小写和字符。
- 有效目标按同一个 decoded anniversary item identity 去重，首次记录优先；不能以 fallback `duoyi://anniversary` 为所有无 id 行的共同 identity。
- 无有效 id 的 legacy 真实文本仍展示，点击使用 anniversary 列表入口。此类记录缺少对象身份，不能可靠按对象去重；保留每个来源记录，避免按文本误删不同条目。重复检查不得把所有 legacy 行合并成一条。
- 非空但不支持的 URI 不应打开其他 host/action 或外部地址；保留真实文本，点击安全退回 `duoyi://anniversary`。缺 id 同样回退。
- 没有真实候选时只保留一条本地化空态；其他槽位隐藏。过期 snapshot 只保留原有“日期数据待刷新”提示与列表入口，不保留旧对象目标。

**必须同步空行判定：** [DuoyiWidgetSnapshot.kt:136](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt:136) 的 finishRender 仍将第 2/3 槽分别对应 A2/A3；[:141](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt:141) 只在 null 时读同号 memorial。若 provider 选到 M1，但 A2 已存空字符串，这段会隐藏真正的第二行。新选择结果应拥有自己的 blank/density visibility，或 finishRender 接收已选行；移除该布局的旧 A2/A3 判空。保持其他布局的 finishRender 行为和尺寸上限不变。

最小生产范围是 Anniversary provider + Snapshot 中该布局的空行契约（如需要可抽小 helper），不必修改 Flutter producer、model、排序或全局 displayMode。

### iOS 相同数据的现有边界

[DuoyiWidgets.swift:1444](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:1444) 配置 primary=A1，rows=A2/M1/M2/M3。[:827](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:827) 仅排除 primary 的 sourceKey，未按目标身份去重，因此也可重复显示同一对象。

[:583](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:583) 的 `isAnniversaryFallback` 只 trim，不去掉 `· `；[:771](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:771) 还只根据 title 判断是否替换 primary。若同步完善 iOS 纪念日，应采用上述无 id + 已知 placeholder 规则与目标 identity，而不能根据 text alone 替换真实用户数据。

## 2. Calendar 摘要与目标的真实语义

唯一生产 `HomeWidgetService.push` 的调用点是 [main.dart:2820](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2820)。因此主 producer 的数组配对有确定来源。

| key / 值 | Producer 证据 | 消费含义 |
| --- | --- | --- |
| `today_event_summary` | [main.dart:2785](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2785)、[:2807](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2807)；[home_widget_service.dart:627](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:627) | 首条今日聚合事件的 label 加 `今日：` / `Today: `；无事件时本地化 `No events today`。不是纯日历本地 event，也不是事件数量。 |
| `schedule_highlight_1/2/3` | [main.dart:2799](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2799)；[home_widget_service.dart:628](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:628) | 同一个今日事件数组取前三条 label，写入时加 bullet。 |
| `schedule_highlight_1/2/3_id` | [main.dart:2803](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2803)、[:2933](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2933)；[home_widget_service.dart:631](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:631) | 每条对应的完整 read-only 目标 URI；summary 对应首条 `schedule_highlight_1_id`。 |
| `today_event_summary_id` | push 参数、payload、account defaults 及全局 source 检索均未找到生产 | 不能承诺用该不存在的 key 打开详情，也不能推测旧残留值属于当前 summary。 |
| `calendar_month_summary` | [home_widget_service.dart:646](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:646) | 固定本地化“本月日期 · 今日已标记”展示文案；不是日期数组、event count 或月份事实数据。 |

[main.dart:2895](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2895) 由 CalendarProvider 聚合 todos/habits/pomodoros/anniversaries/courses/diaries/countdowns/goals/timeEntries，排除已完成 todo 与无 sourceId 的事件，再按 event.date、title 排序。没有过滤“当前时刻之后的事件”，不能称为下一件待发生事件，也没有可据此安排 event-time 刷新的结构化时间。

[main.dart:2933](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:2933) 的目标映射是：todo / habit / anniversary / course / diary / goal / countdown / time-entry 加 encoded id；普通 event → `duoyi://calendar`；pomodoro → `duoyi://focus`。因此“今天摘要”的点击有时正确地进入待办、习惯或专注，不应强制把有效目标转换为 calendar event id。

### Consumer 与安全回退

[main.dart:3810](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:3810) 的 `_handleWidgetUri` 只接收 duoyi scheme；[:3837](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:3837) 阻止账号转换/清理期间访问；[:4219](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:4219) 在详情路由前等待数据 hydration 并核对 account generation。

- `duoyi://calendar` 在 [main.dart:3913](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:3913) 只切到 tab 3；`duoyi://tab/calendar` 在 [:3859](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:3859) 也映射到 3。都是当前支持的通用日历入口。
- `duoyi://anniversary/<id>` 在 [:3933](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:3933) 调用 TodayDetailRouter；[today_detail_router.dart:100](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/screens/today_detail_router.dart:100) 根据实际类型进入 normal/birthday/memorial 页，已删除 id 进入明确 EmptyState。不能因为 title 像 memorial 就另造不支持的 `duoyi://memorial` host。
- 其他详情 host 按 [:3880](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:3880) 起的现有分支消费；不要附加 `confirm=1` 或 `action` target，使摘要点击成为完成/打卡/开始计时操作。

Calendar 事件行的有界契约：从相同 display snapshot 读取 summary 与 `schedule_highlight_1_id`；只接受上面 producer 生成的 read-only URI 形状。没有目标、目标非法/不支持、空数据或过期时，使用现有 Calendar 通用入口。若未来增加 `today_event_summary_id` alias，须同时修改 push 参数/payload/default clear/signature 与一致性校验；本次不需要增加该 schema。

展示规则建议明确为：fresh + 真摘要 → 展示原 summary；fresh + `No events today` → 本地化空态、通用 Calendar 点击；缺失/纯空白 → 隐藏可选事件行；stale → 展示本地化待刷新提示、通用 Calendar 点击。compact 可隐藏事件行，standard/detailed 的密度限制保留。不要为缺失数据生成假的 event id，也不要用 `calendar_month_summary` 冒充事件行。

Android 当前 [DuoyiCalendarWidgetProvider.kt:97](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt:97) 只读取月份文案；[:130](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt:130) 的 root/title/month/today/grid/summary 都通用路由。可仅新增事件 TextView、provider 填值与这一行的匹配 target；保留其余按钮行为。

iOS 当前 [DuoyiWidgets.swift:1376](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:1376) 将 summary 当 row；通用 readRows `:835` 读取 `\(key)_id`，因此此行目前必然回退 `duoyi://calendar`。新 Calendar-specific view/entry row 可有界地用 schedule1 的 target；不要因不存在的 summary id 改动全局 row getter 或承诺所有 widget 的详情链接。

## 3. 空数据、旧快照与账号边界

Flutter 在 [home_widget_service.dart:497](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:497) 先将 publication day 清空，完成 payload、offset 与 generation/locale 校验后，在 [:683](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/home_widget_service.dart:683) 发布 day。清理默认值将 day/nonce/id 置空。保留这个发布顺序，不能只更新 text 而不更新 matching id。

Android [DuoyiWidgetSnapshot.kt:16](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt:16) 按本地 day 和当前 UTC offset 判 fresh，`:23` 的 display wrapper 用待刷新文案替代过期值，并把 `_id` 清空。新增行应继续从 `forDisplay` 的 getString 读取；不能直接读取 backing 或用 getAll 绕过 stale overlay。注意 Android fresh 判定与 iOS 并不完全相同：Android 的 `isFresh` 没有强制 nonce，而 iOS 有。

iOS [DuoyiWidgets.swift:265](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:265) 的 published-session 要求合法 day/offset/非空 nonce；[:315](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:315) 以 entry date 本地 day/offset 检查，`:692` 对 stale entry 清除 rows，primary 为打开刷新且目标为 widget 通用入口。不要重新读取 UserDefaults 来“补”旧 entry 的对象 target/account nonce。

日期网格本身可以显示当前 timeline entry 的月历，即使事件 payload stale；这不代表事件已更新。数据新鲜度由原 snapshot 契约控制，月份/今日 marker 由 entry date 控制。

## 4. iOS 月网格与日期点击能力

现有 Swift source 没有月网格或 firstWeekday 设置。`DuoyiWidgetView.content` [DuoyiWidgets.swift:903](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:903) 只有 Todo/Focus 专用分支，Calendar 走通用 linked text。

可直接实现的视觉契约：

- 使用 Gregorian Calendar、`.current` timeZone，以 **entry.date** 取年/月/日；月标题、月份长度、前置空格、当前日 marker 使用同一 Calendar/date。不要在 Calendar view 内另外用 `Date()`，否则未来 midnight timeline entry 仍可能显示上一天。
- [DuoyiWidgets.swift:659](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:659) 同一 publication 生成 future entries；[:194](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:194) 已加入 day-end / DST transition。Calendar 视图保留这些 timeline 行为，不新增刷新计时或把日期网格当事件实时更新。
- 周一起：Android [DuoyiCalendarWidgetProvider.kt:150](/home/ubuntu/duoyi-worktrees/native-locale-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt:150) 把 Sunday-based weekday 转成 Monday offset；Flutter [calendar_month_grid.dart:31](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/widgets/calendar_month_grid.dart:31) 也明确周一起。iOS 设置 `firstWeekday = 2` 或等价 Monday offset，中英文都保持顺序，不采用 en-US 的默认 Sunday-first。
- locale 使用 entry.locale：[DuoyiWidgets.swift:215](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/DuoyiWidgets/DuoyiWidgets.swift:215) 优先 saved widget_locale，缺失/非法时系统首选英文→en，其他→zh。格式器显式使用 en / zh 对应 locale；weekday header 为本地化 Monday→Sunday，不借设备 locale 改顺序。
- 用 Calendar 日期算术处理月底、leap year 与 DST，不以固定 86,400 秒递增日期。空白格无日期/无链接，不制造上一月/下一月事件。family/displayMode 决定能显示的周数与事件行；保留 accessory 的原通用入口及 header/footer/theme 行为。

**当前日期深链结论：未支持。** `_handleWidgetUri` 的 calendar 分支忽略 path/query，只切 tab；[calendar_screen.dart:44](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/screens/calendar_screen.dart:44) 虽有 initialDate，但仅在 [:72](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/screens/calendar_screen.dart:72) 的 initState 初始化；主 shell [main.dart:5866](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/main.dart:5866) 不传初始日期，也没有公开选择日期接口。

本次仅做原生展示时，月格应维持通用 Calendar 点击；不发一个 consumer 会忽略的 date URL并声称“点哪天就选哪天”。如实施日期导航，另需有界的 Dart 契约：`duoyi://calendar?date=YYYY-MM-DD`，严格格式/日期 round-trip 校验、本地 Gregorian 日期语义、不接受 DateTime 自动归一化无效日期；consumer 先按原 hydration/account 规则打开 Calendar，再在已挂载 Calendar State 调用明确的日期选择入口（更新 selectedDay/focusedMonth，保留现有筛选与 controller），或使用明确创建的 `CalendarScreen(initialDate: day)` 路由。缺失/非法 date 回到现有通用入口；不得改变全部旧 calendar 链接的选日行为。

iOS 原生 bridge [AppDelegate.swift:48](/home/ubuntu/duoyi-worktrees/native-locale-20261009/ios/Runner/AppDelegate.swift:48) 接收 duoyi URL并透传完整字符串，Dart [deep_link_service.dart:17](/home/ubuntu/duoyi-worktrees/native-locale-20261009/lib/services/deep_link_service.dart:17) 同样透传 parsed URI，因此无需另造系统 scheme；缺的是 Flutter calendar consumer 的选日行为。若采用 per-cell Link，实际不同 widget family 的点击区域还需设备验收，本审阅不声称已验证。

## 5. 必要验收 case（只提出，未执行）

| 范围 | 必须包含的 case |
| --- | --- |
| 纪念日 identity/配对 | A1=M1、A2=M3、综合全为 memorial、综合只有普通/生日、两组混合；每条只出现一次且点击其正确 target。不同 id 的相同 text 都保留。 |
| 纪念日空态/legacy | null / empty / whitespace、无 id 的中英 placeholder（含 bullet）、有 id 而 text 恰等于 placeholder、无 id legacy 真实文本、raw id、encoded `/`/中文/空格 id、不支持 URI；确认 safe list fallback。 |
| 纪念日密度 | compact 1、standard 2、detailed 3；A2 空而选到 M1/M2 时不得被 finishRender 旧槽位隐藏；完全无数据时仅一条空态。 |
| Calendar 配对 | 首 schedule 为 todo/habit/anniversary/course/diary/goal/countdown/time-entry/event/pomodoro，summary 和 target 对应；缺 schedule1 target、非法 target、空/no-events summary 与 nonexistent summary_id 残留值均安全回退。 |
| Freshness/清理 | 前一日、offset 改变/DST、day 暂时空（写入中）、账号 clear、nonce 缺失；无旧事件/旧周年对象 target，保留各平台既有 freshness 策略。 |
| iOS 网格 | 28/29/30/31 天，Monday/Sunday 开月，4/5/6 周，跨年、未来 midnight entry、DST transition；用 entry.date 定义 month/day marker，zh/en/system fallback 与周一起一致。 |
| 当前路由 | cold/warm launch、hydration 未完成、账号转换中、对象已删除；已有泛日历链接保持原行为。若加日期契约，追加合法 leap-day、非法 02-30、缺/畸形 query、重复点击及原 State 已存在时的选日验收。 |

保持不变：producer 排序与选取上限、Anniversary 日期/循环/农历语义、用户文本、已编码 item id、账号隔离/hydration、mutation action 验证、snapshot 发布与清理协议、displayMode/theme/底部导航、现有通用 Calendar 入口、timeline timer/day-boundary 行为。不要把本次展示整改扩成新的事件时间调度或全局路由重写。

审阅完成；STOP。
