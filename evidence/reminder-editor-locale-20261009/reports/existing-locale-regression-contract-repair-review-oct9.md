# Existing locale regression contract repair review — 2026-10-09

## Conclusion and scope

本轮有限只读 source/fixture contract 审阅未发现可操作问题。现有 5 个静态/模型测试文件的修复与国际化 facade、State 拆分、formatter 输出相符，保留对应功能和布局约束。Calendar locale firstcase 的最后中文断言与仍然选中的三日视图及项目筛选相符。

本审阅未运行测试、build、analyze、SDK、Git 或网络命令，未修改生产源码或 fixture。本文只报告源码审阅结果及观测到的 SHA，不宣称 repair3 或其它运行通过。

审阅 worktree：

- Calendar: `/home/ubuntu/duoyi-worktrees/calendar-content-locale-20261009`
- Reminder: `/home/ubuntu/duoyi-worktrees/reminder-editor-locale-20261009`

## Evidence and baseline

读取 `calendar-reminder-legacy-regression-oct9/verification.json` 的已有失败记录。其 Calendar 失败对应旧中文 literal 和旧格式化 clamp 表达式；Reminder 失败对应旧中文 literal 和 ISO 日期显示期望。这是历史运行记录，不是本审阅新执行的结果。

为 5 个旧测试选择 `todo-shared-locale-20261009` 中的未修改文件作为 before；逐文件 SHA 与该 verification 的 `sha256_before` 完全一致，随后用 `diff -u` 与当前目标 worktree 文件对比。实际 diff 未增加、删除或重命名测试 case：

| File | Before cases | Current cases | Case names preserved |
|---|---:|---:|---|
| Calendar `test/screens/calendar_inline_time_entry_static_test.dart` | 1 | 1 | Yes |
| Calendar `test/screens/calendar_project_detail_static_test.dart` | 3 | 3 | Yes |
| Calendar `test/screens/calendar_three_day_static_test.dart` | 8 | 8 | Yes |
| Reminder `test/widgets/recurrence_picker_static_test.dart` | 3 | 3 | Yes |
| Reminder `test/models/recurrence_interval_test.dart` | 6 | 6 | Yes |

总计 21 个 case，以上计数是文件内容核对，不是执行结果。

Calendar locale fixture 的 repair2 完整副本未保存，因此未声称获得该文件的完整 before diff。对它的审阅范围是根会话明确提供的有限最后 hunk，加上当前 firstcase 的完整控制流；前次审阅 SHA 只作为历史标识。

## Five fixture diffs

### 1. Calendar quick time entry

`calendar_inline_time_entry_static_test.dart:9` 起将菜单与表单的中文 literal 替换为真实的 `CalendarUiCopy` 使用位置。对应 facade 的中文值仍为记录一段时间、事项、分类、开始时间、时长（分钟）、备注，生产调用仍位于原有菜单/表单角色。

`startTime/category/noteCtrl` 更新为 State 中的 `_startTime/_category/_noteController`，同日比较更新为 `_isSameDay(widget.origin.selectedDay, now)`。生产代码仍用 origin 选定年月日和 `_startTime.hour/minute` 构造 start，依输入 minutes 计算 end，提交 `_category`、`TimeEntrySource.manual` 以及 trim 后备注（生产 `calendar_screen.dart:1554`、`:1616`）。原有禁止固定 other 类别和直接使用 `DateTime.now().hour/minute` 的断言保留。

### 2. Calendar project detail and dense layout

项目详情入口、弹层标题、打开待办以及全部空间改为相应 facade；`option.name/todos.length` 更新为当前组件的 `widget.option.displayName/widget.todos.length`。生产项目名仍由 option 展示，列表 itemCount 仍来自完整 todos（生产 `calendar_screen.dart:1951`、`:2019`）。独立项目操作、TodoScreen route、非外层滚动、独立 `ListView.separated`、`primary: false` 和禁止 `.take(8)` 等约束保留。

clamp 匹配更新为 `\.clamp\(\s*360\.0,\s*680\.0,?\s*\)`：仅允许 formatter 产生的空白和尾逗号，两个边界仍固定 360.0/680.0。生产内容高度仍为 viewport * 0.68 clamp 到这两个值（`:1958`）。原有 maxWidth 860、月格高度区间、0.46 viewportTarget、预览 8、导航尺寸、窄屏阈值、整页月滚动及详情独立滚动相关断言未变。

状态文案匹配仍要求同一个 `isCompleted ? MainUiCopy.calendarStatusCompleted : MainUiCopy.calendarStatusOverdue` 三元分支，而非仅独立包含两个文案标识。生产 `:2076` 分支及 facade 中文已完成/逾期相符；completed/overdue visual state、priority 图标和 lineThrough 断言保留。

workspaceId 模型、aggregator 传递、provider 筛选、effectiveWorkspaceId 和 option 类检查保持。

### 3. Calendar three-day entry and navigation

菜单改为 `() => MainUiCopy.calendarViewThreeDay`，tab 改为 `CalendarUiCopy.tabThreeDay`，导航 tooltip 改为 index 3 对应的 `MainUiCopy.calendarPrevThreeDays/calendarNextThreeDays`。当前 production 菜单、Tab 和 header 分支均在对应位置，中文 facade 仍输出三日视图、三日、前三天、后三天。

TabController length 5、`three_day` value、previous/next 方法、threeDayLabel 和 view key 保留。其余七个 case 的聚合筛选、复用 day agenda、宽屏 900 阈值、窄屏横向滚动、390/380 宽度、异步聚合、月视图滚动、弹层尺寸和共享小号控件约束没有改动。

### 4. Recurrence picker controls

只将 weekly label、两种 subtitle、重复次数 label/helper/clear tooltip 的旧中文文本改为 `ReminderEditorUiCopy` 属性名。核对当前生产使用位置：subtitle 仍由 `widget.supportMaxOccurrences` 选择 withMax/withoutMax（`recurrence_picker.dart:231`）；weeklyDaysLabel 仍在 weekly 输入区域；max label/helper 仍属于输入 decoration，clear tooltip 仍属于清除按钮（`:457`、`:481`）。facade 中文保持原意。

supportMaxOccurrences 的声明和默认值、initial.maxOccurrences、控制器、共享 secondary theme/style、`!widget.supportMaxOccurrences` 以及 controller.clear 检查保留；Todo detail 完整 rule.label 与 Goal edit 禁用 max occurrences 两个 case 未改。

这些静态用例继续检查 source 中对应表达式的存在；本轮接受依据同时包括上述实际 call site 的只读核对，不将静态存在检查等同于运行行为验证。

### 5. Recurrence interval semantics

唯一变动是完整 label 中 `2026-05-20` 改为 `2026年5月20日`。`RecurrenceRule.label` 仍传递 frequency/interval/weekdays/endDate/maxOccurrences 给 facade（`recurrence.dart:120`）；中文显示通过 `I18nDateFormat.date` 得到年/月/日格式。完整期望仍精确包含每 2 周、一/三、结束日和共 10 次，未删除结束日期或次数信息。

其余 interval、当前 active week 后续 weekday、date-only endDate 包含整日、结束日上界、none compact label 的断言均不变。模型 JSON 的 endDate 仍使用 ISO serializer；本次修改的是显示期望。

## Calendar firstcase final Chinese hunk

当前控制流先从 Year 切到 English `3-Day`，验证 Feb 1/2/3 和 3/1/0 items，然后在该视图选择 alpha project，检查 2 items、排除 1 item、保留 alpha 业务内容并排除 other 内容。之后只切 locale 回 zh，没有切回 Day（fixture `calendar_content_locale_state_test.dart:387` 起）。

因此末段 header 应为 `2月1日 - 2月3日`，与 production 的 index 3 -> threeDayLabel 及 monthDay range 相符。两个 alpha todos 均在 Feb 1，Feb 2 的唯一 todo 属于 other project，因此按当前 active alpha 筛选，每条 lane 的计数应为 2/0/0。

局部 `laneCount` helper 先按中文日期 heading 找其 `_ThreeDayLane` ancestor，再找对应 count descendant（fixture `:426`）。三条 assert 将 `2月1日 周一/2 项`、`2月2日 周二/0 项`、`2月3日 周三/0 项` 各自绑定，重复的 0 项不会互相误匹配。生产 `_ThreeDayLane` 使用相同 project/workspace/type 参数查询当日事件并以 events.length 显示计数（production `:2468`、`:2501`）。

末段仍检查日历、三日、literal project 2、Literal task alpha one，以及 `takeException() == null`。当前 firstcase 的前序中英日期、业务内容、project/workspace filter、selected chip、year counts 和 English 三日计数断言均存在。根会话说明这次有限 hunk 没有改变此前 English 三日选择及筛选断言；因没有完整 before 文件，本报告不扩大这一历史 diff 结论。

## SHA-256 — exact old baselines and current fixtures

| Worktree / file | Before SHA-256 | Current SHA-256 |
|---|---|---|
| calendar `test/screens/calendar_inline_time_entry_static_test.dart` | `6e82091af9a5a38500b2b5d887412abbb69a3e0b945ba65366bd492e4705181e` | `965dcbca8fd57549ee740018c62dee8c6c957baa05cca60a1970e1ab93ed2e88` |
| calendar `test/screens/calendar_project_detail_static_test.dart` | `f93385dca88fb39b2503a08e0b4790df06a37ba55e0751057f8e45209d0ffc3b` | `7b6b07fb136a0e50169030613bb04a3004c208899a1367686c6a24fe435070e8` |
| calendar `test/screens/calendar_three_day_static_test.dart` | `8f88d6163410d4eb2ec7e97b1541e09adb17c4203d8b9ee8e33313be850f80b7` | `64fc4f6f74908b70608673a1640a6e1e067f3f6ae3ed5f7333ec127d5706e700` |
| reminder `test/widgets/recurrence_picker_static_test.dart` | `13ee3489a70a45ae5ae83044e6a47762d88435f9836d228ef6e70037066903f7` | `295e0d4b623e64d56caf1c8d809cd765ce932a51e00d1093395f0685f552ecec` |
| reminder `test/models/recurrence_interval_test.dart` | `7f2e8aae5225a17255d14467e3da3c647ba5ecf4c7e2ec3cca78168c62c78844` | `e15fb6991b7202dbaa73051d604f1f5616fe4c8fa80a1cce495f185d4cf382d6` |

Calendar locale fixture 前次审阅标识：`4a5e219c6ffa0a031c574ac1d242e8b0451988ac76aa6b3bd830a105f9492ea1`（未获得对应完整文件，非本轮 before diff 来源）。

| Worktree / additional fixture | Current SHA-256 |
|---|---|
| calendar `test/screens/calendar_content_locale_state_test.dart` | `bbcf2b759fd073689519b978d0c721e6b6a26da6707490b91de7fa4bfa8aeb1e` |
| reminder `test/widgets/reminder_editor_locale_state_test.dart` | `fe6ca3eeb6a1897738b9b1620442a3b8f844b47c4cb6e513f5b22c6df153b964` |

## SHA-256 — observed production references

| Worktree / file | Current SHA-256 |
|---|---|
| calendar `lib/core/calendar_ui_copy.dart` | `82276c4c43f1afd470919cccfd3e11baf64225d4efd25b3332b75982def31029` |
| calendar `lib/core/main_ui_copy.dart` | `8450f33acaefda41a41534283c1bf84dc9d7991dbc69cb60226f9b7221afe815` |
| calendar `lib/core/i18n.dart` | `0f92b6dc9222a836508aefa15e47dc17edaf3193498fc3e256f395fcf4fffd3f` |
| calendar `lib/core/i18n_date_format.dart` | `b92bbe21b07751d8bb21bab9a3abbe24407efa4ec35b00b8dc654b33d5bfd9b3` |
| calendar `lib/screens/calendar_screen.dart` | `bc35b8ad9f03889144332ef811f3c345f2f8d74a3fac697e8a82b5d3a6c1a244` |
| calendar `lib/widgets/surface_components.dart` | `9ea733e62913e0f818f8c7c9d7e54bb5d99de3b053ec2973bd800ac4aec2c591` |
| calendar `lib/providers/calendar_provider.dart` | `da97957191f8d5e10fc8fb44d49372e50f759e7f3542e28361766e410295d23c` |
| reminder `lib/core/reminder_editor_ui_copy.dart` | `a2168543f919e739e6f729f08f095072ab319ff4de1690e4513da106ab5cf42f` |
| reminder `lib/core/i18n.dart` | `df7a2f149409a063077f53f7f60d661b53d7623fd0e0d7970e33a1c084c301a9` |
| reminder `lib/core/i18n_date_format.dart` | `b92bbe21b07751d8bb21bab9a3abbe24407efa4ec35b00b8dc654b33d5bfd9b3` |
| reminder `lib/models/recurrence.dart` | `f952bb3a8e9f2219000ee7ca9f690c63f6aa26ce7ea7e1a5def9b7dac48456f7` |
| reminder `lib/widgets/recurrence_picker.dart` | `036b8dba3709816c101f860d1f3aabc9cc4833b1c503db8ce5b536d1fcec5418` |
| reminder `lib/widgets/reminder_plan_editor.dart` | `37d90d6fca3de70289bb8715dbef6cf549ced5c9c678747d17346e184a21ee3b` |
| reminder `lib/widgets/surface_components.dart` | `9ea733e62913e0f818f8c7c9d7e54bb5d99de3b053ec2973bd800ac4aec2c591` |

以上列在 legacy verification 内的生产文件 SHA 与其中记录相符；其余 main_ui_copy、Calendar date formatter/provider 仅记录本次观测值。两 worktree 的 surface_components 当前 SHA 相同。运行判断交由根会话/Luna 的独立 verification 记录。
