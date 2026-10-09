# 三类热图：最小交互与可访问性约定

日期：2026-10-09。范围：`/home/ubuntu/duoyi-worktrees/heatmaps-20261009` 的现有 HabitHeatmap/MoodHeatmap、三处直接调用、相关数据含义、heatmap tests 与 core locale/date formatter。只读审查，未运行 SDK、检查或测试，未修改源码，未扩展到 route localization 审计。

## 1. 现有实现的具体问题

- Habit 的 tooltip 使用 `$intensity 次`，但单 habit 数据是相对 target 的0–5进度，combined 是平均 progress；activity 是多个来源加权后 clamp 到0–5。**不能把 intensity 当真实记录/完成次数。**共享接口应传入当天的语义标签，默认用“强度/进度等级 3/5”。真实 counts 只能由了解原始数据的 caller 提供。
- Habit month、weekday、legend、count suffix 硬编码中文；Mood 的 weekdays、少/多、无记录及 `Mood.label` 也是中文。`Mood.label` 当前不随 locale 改变，heatmap 必须使用自己的 localized mood labels。
- Mood 五个颜色代表心情，当前“少→多”图例误导为数量轴。应显示命名的五档 mood（可带 emoji）与无记录，而不是把 mood 映射为 primary intensity。
- Mood 有 diary 但 mood=null 和没有 diary 都涂中性色；选中/tooltip/屏幕阅读器文案应分别为“未记录心情”和“无日记”。颜色可以相同，含义不能合并。
- 现有 cells 只有 Tooltip/Container，没有日期选择或键盘 action；Mood weekday 四个独立 padding 也没有严格对齐七行。52周宽度不能靠缩格适配到窄屏。

## 2. 推荐的最小交互

| 面向用户的行为 | 约定 |
| --- | --- |
| 初始展示 | 只在首次布局完成且 controller attached 时定位最近端；52周允许横向滚动。以后 build、locale、theme、data 更新不重新 jump 到末端。 |
| 日期选择 | State 保存 civil-day key，默认 today。点按有效 cell 更新选中 outline 和网格外较大的完整日期/值标签；无记录日期也可选，future 不可选。today 与 selected 使用可区分的 outline，不只依赖色深。 |
| 正常尺寸的替代操作 | 在选中标签旁提供可换行的“前一天/后一天/选择日期”控件；48px 左右的常规触控目标，范围限制为 visible start..today。这样用户无需精确命中小色块。 |
| 详情 | selection 与打开详情分开；caller 的可选详情 action 使用正常尺寸按钮。diary 可复用现有 showDiaryEditor，habit 可打开其日期记录；activity 没有详情能力时只显示标签，不能放一个无响应详情按钮。 |
| 回调 | 用户明确选择或打开详情才通知 caller；不能在 init/build、locale 更新、palette 更新或数据刷新时自动调用。箭头移动不应反复导航到 editor。callback 收到 civil date，不收到 locale 格式化字符串。 |
| 窄宽度 | 横向 viewport 承载固定最小间距的 grid，labels/legend/selection/actions 放在 viewport 外并允许 Wrap。不能把选择文案放在整个52周超宽 child 的末端，让近期查看仍需寻找说明。 |

紧凑色块的 hit target 可以与其 visual bounds 一致，但不能用彼此重叠的48px透明区域声称每个小格子都有独立48px目标；相邻日期会抢点击。上面的正常尺寸日期控件是最小可用替代路径。如果要求每个格子都满足常规触控目标，则必须实际增大 grid pitch，接受更宽/更高的横向内容。

## 3. 键盘与屏幕阅读器

- 一个 grid 焦点/roving focus 即可，Tab 不遍历全部364个日期。可通过正常日期控件进入/离开，不 trap focus。
- 按实际二维布局定义移动：Left/Right 为同 weekday 的前/后周（±7）；Up/Down 为本列相邻 weekday，行首/末不 wrap 到另一列。候选越界或 future 时不移动；Home 到第一有效日，End 到 today。
- Enter/Space 执行当前日期选择；打开详情属于明确的详情按钮/action。焦点/选中移动到 viewport 外时只滚动到该日期可见，不能每次滚到 today。
- 每个可选择日期有一个明确语义节点：完整 localized date + habit/activity level 或命名 mood/缺失状态，带 selected，必要时标 today；tap 语义与真实操作一致。
- 若保留每格节点，顺序是按日期从早到晚（每列 Mon..Sun），axis/legend 的重复装饰性文字与 tooltip 子节点不再重复播报相同日期。不要同时由 Semantics 与 Tooltip 报两份 label。
- future placeholders 没有 tap、focus、详情 callback 或 enabled/button 语义；可以直接从交互语义树排除。没有记录的过去日期仍是有效日期，不能误当 disabled。
- 屏幕阅读器用户也能使用正常尺寸日期控件选择任意有效日。选中大标签可作为单一更新提示；避免 label/live region 与焦点日期同时重复宣布。不要依赖颜色或 emoji 单独传达 mood。

## 4. 放大文字与 locale 状态

- `I18n.tr` 与 `I18nDateFormat` 都只是读取全局 current；独立 shared grid 应监听 `I18n.localeListenable`（直接或 ValueListenableBuilder），确保 raw locale event 也能更新已有 tooltip、月份、图例、选择标签与语义文案。
- Stateful grid 与 ScrollController 不以 locale 创建 key，不因 zh→en→zh 重建 State；选择 key 与 scroll offset 保留。格式化 label 每次由当前 locale 派生，不存进 State。
- 日期 grid、weekday axis 与 month axis 始终 Monday 对齐；可复用 picker weekday 词条，English 的 Mon/Wed/Fri/Sun 不塞进固定18/24px且未缩放的标签宽度。
- 不固定文本容器高度，也不 clamp TextScaler。选中标签、图例/controls 允许增高与换行；weekday label 所需宽高应参与轴/row pitch 的布局。活动卡片现有 title+summary Row 在窄宽/大文字下也应 Wrap 或上下排。
- month labels 按实际 month boundary 建立，使用跨多列的空间或冲突隐藏策略；不能每四周往单 cell 宽度里塞一个 Jan/9月并期待2x文字不溢出。完整年份可在选中日期/范围标签补充。
- locale 单独变化应保持像素 offset；resize/文字缩放使 grid geometry 变化时，可用最靠近可见端的 civil day 作 anchor 后 clamp 到新范围，避免无条件跳到末端。

## 5. Civil-day 与窗口更新

共享 helper 的 Monday/start/date progression 应使用年月日的 civil arithmetic，例如 `DateTime(year, month, day + delta)` 或统一的 UTC-field surrogate；不能用本地 midnight 的 `add/subtract(Duration(days: ...))` 当作跨 DST 的日期推进。

date key 始终为既有 YYYY-MM-DD，不能随 locale 改变；UTC surrogate 不能再 toLocal 后改变日期。给 diary/habit caller 的值应保持所选年月日含义。

周窗口/day 更新时，保留仍在范围内的 selection；若日期离开范围，明确 clamp/重新选择到有效日并更新标签。只有用户仍在 recent end 时才自动跟随新增的近期列，不能夺走已滚到历史段的位置。Future 是按当前 civil today 判断，不看是否存在一条未来数据。

## 6. 已有测试的边界

- `mood_heatmap_test.dart` 和 `mood_dark_theme_golden_test.dart` 检查亮暗 mood palette、中性空格以及特定中文 axis/少多文字。palette 的既定 semantic shades 应保留；中文少/多断言会随正确的 mood legend/localization 改变，需要后续由 root 更新。
- `main_route_locale_state_test.dart` 已要求 Habit tab/route/provider 在 raw locale events 下保留；它尚未证明热图 controller offset、selected civil date 或 keyboard/semantics 同样保留。
- statistics static test 固定搜索现有 HabitHeatmap 调用字符串和中文卡片文案；这不是阻止新 callback/shared grid/localization 的产品约束。
- 本轮看到的 heatmap tests 没有独立覆盖52周窄 viewport、放大文字、grid键盘操作、屏幕阅读器节点或 future no-action；本报告不宣称这些已验证，也没有新增/执行测试。

建议 root 后续验收只围绕这组交互：52周近期初始可见；窄宽/2x文字无 overflow；zh→en→zh 不丢选择/offset；键盘一次进出 grid；过去空日可选/future不可选；语义标签不把强度读成次数；diary mood-null 与无 diary 可区分。无需扩展到其他 route localization。

报告交付后停止本轮源读取。
