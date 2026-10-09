# 热图实现：交互与布局审计

日期：2026-10-09。工作树：`/home/ubuntu/duoyi-worktrees/heatmaps-20261009`；root 提供 HEAD 为 `98d46d8`，本轮未运行 Git。

审阅冻结的 `calendar_heatmap.dart`、`habit_heatmap.dart`、`mood_heatmap.dart`、`activity_heatmap_card.dart`、`heatmap_ui_copy.dart`。仅补读直接使用的 calendar window 与 pickSolar 的范围/返回契约，并定向确认五个 mood 翻译 key；未扩展到 route/主题审计。未编辑源码、运行 SDK/检查/构建/测试或提交。

## 1. 阻塞修订

### P2：最高强度格子的选中/今天标记缺乏颜色对比

位置：[calendar_heatmap.dart:301](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/calendar_heatmap.dart:301) 与 [habit_heatmap.dart:29](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/habit_heatmap.dart:29)。

selected/today 的 border 均使用 `cs.primary`。level5 的 fill 是 background→primary 的0.98插值，仅剩约2%的背景贡献；在这种 cell 上，2px selected border 与1.2px today border 很难与填充区分。键盘 focus 的外框只表示整个 grid 获焦，不能补足“哪一天被选中”的标记。

建议使用**平面、对比明确的 outer ring**：填充外围保留一圈 surface 间隔，选中外圈取在 surrounding surface 上可见的 contrasting color（例如适当的 onSurface）；today 使用不同的 dot/角标或第二种 ring。selected 与 today 同时成立时，两项状态也应可辨。不要以 cell shadow 补救。

这是本轮唯一需要先修订的明确实现问题；root 已收到单独通知。

## 2. 已通过的源码检查

| 项目 | 判断 |
| --- | --- |
| 单个键盘 grid focus | 只有共享 FocusNode；cell 用 GestureDetector，不创建逐日 keyboard Focus。Tab 无需遍历364格，未知按键返回 ignored。 |
| 移动边界 | Left/Right ±7；Up/Down 的 weekday guard 避免跨行 wrap；所有候选还经过 current window.contains，因此 future/first-day 外不会选中。Home/End/Enter/Space 与 KeyRepeat 路径成立。 |
| Future 无交互 | `_cell` 在 contains=false 时直接返回 SizedBox，未创建 Tooltip、Semantics button、GestureDetector 或 callback。 |
| 过去空日期 | 仍构建合法 cell，tap/语义 tap/正常日期控件可选择，不误当 disabled。 |
| 初次近期定位 | post-frame 检查 mounted、controller clients、一次性 flag 后跳到 maxScrollExtent；locale/theme/data rebuild 不再次执行初始跳转。 |
| 选择后滚动 | 后帧检查 mounted/clients，按当前 selected/geometry 算列，只有选中格超出 viewport 时 jump，并 clamp 到实际 extent。快速选择的旧 callback 不会使用旧 day 覆盖最新 selection。 |
| Picker disposal | await 返回后先检查 mounted/null；销毁后的结果不会 setState 或使用已释放 controller。 |
| Picker 期间范围改变 | 返回值再次进入 `_select` 的 current window.contains；旧 picker 范围内、当前范围外的日期被忽略，不越界恢复旧 selection。取消也不改 selection。 |
| Locale 状态保留 | wrappers 和 CalendarHeatmap 都监听 I18n.localeListenable；CalendarHeatmap 不以 locale 为 key，controller 与 selected State 保留。didUpdateWidget 只在日期离开窗口时重设 today。 |
| 语义/Tooltip 主节点 | 每个有效 cell 有一个显式日期+描述+today label、selected 与 tap action；其 Tooltip/GestureDetector 子树置于 ExcludeSemantics 内，不会把相同 inline tooltip 作为第二个 cell label 合并。 |
| 数据含义 | habit/activity 描述是 level/5，不再称次数。mood 通过已有五个双语 key 显示命名语义；无 diary 与 diary mood=null 的文案和 neutral color 都分开。 |
| 详情回调 | onOpenDay 只在明确详情按钮时执行，不随 selection/locale/data build 自动导航。无 callback 时无详情按钮。读取的是当前 selected/current widget callback。 |

HeatmapUiCopy 的 mood/range 仍调用全局 I18n/I18nDateFormat，但当前所有 UI 创建 copy 的路径取同一个 I18n notifier 的 locale，setLocale 更新 current 后再通知；本轮未发现实际热切换混合语言路径。未来不要把独立 locale 的 copy 当作不依赖全局的 formatter。

## 3. 320px、2x文字、1/52周的布局推导

这是源码约束推导，不是已运行的 widget/设备验收。

- 2x 时 grid pitch 至少 `13×2+3=29px`，axisWidth 至少48px，headerHeight 至少32px；weekday 文字不再塞进旧18/24px标签轴，七行使用同一 pitch。
- 52周的内容宽度显式为 `52×pitch+72px`，置于水平 SingleChildScrollView；不会为了320px viewport把52列压到不可见尺寸。1周内容也有明确有限宽度，默认 finite viewport 内可以正常布局。
- 月标签按实际 month boundary 放置，追加的尾部空间容纳最后标签；首个残月与下月标签过近时去掉残月标签。2x时完整月份间的通常间距足够，未发现明确月标签重叠条件。
- Activity title/subtitle 用独立 Text，summary 用 Wrap；Habit legend 与 Mood 每个命名样本用 Wrap；selected label、hint 与按钮不设置固定文本高度，可随放大增高。
- 日期按钮行只固定两侧 IconButton，中间 Expanded TextButton 的日期文字可换行；320px下没有把长日期与固定宽 summary 放入不可压缩 Row 的结构。
- shared grid 的 Row/Expanded 仍要求 host 提供有限水平宽度，当前三类标准竖向内容场景满足；360px fallback 本身不能让 Expanded 在无限水平约束下工作。不是本轮320px场景的 blocker。
- 2x后整体组件明显更高，需作为 host 的可竖向滚动内容使用；共享 Column 不负责把全部 legend/日期 controls 压进一个固定小高度。不能仅凭本报告宣称所有 viewport 高度都无 overflow。

## 4. 非阻塞的交互细节

1. **选择反馈的重复 payload**：[calendar_heatmap.dart:242](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/calendar_heatmap.dart:242) 的 liveRegion 完整包含 date+description；语义 day button 的 label 也包含相同内容。screen reader 聚焦后激活 day 时，可能再次播报同一整段选择值。inline Tooltip 已排除，这里是另一种重复来源。可让 day 的语义 tap 依赖 selected 状态反馈，而正常日期 controls/单键盘 grid 的移动使用 live selection 提示，或缩短独立 live 提示。未运行实际 TalkBack/VoiceOver，因此不声称具体重复次数。
2. **Window/geometry 更新的 scroll anchor**：locale 单独更新不改 geometry，可保持 offset；但 weeks/文字缩放变化、窗口整体移动时，目前没有以旧可见 civil day 重建 offset。didUpdateWidget 重设 today 后也不会自动 ensureVisible。这不破坏 current bounds/数据正确性；若需要在1→52周参数变化或窗口轮换后保持历史日期锚点，应另行补这个行为。
3. **正常尺寸目标继承主题**：现有 IconButton/TextButton 使用 framework/theme 的默认最小尺寸与 tap density，没有主动缩小目标；若48px是所有品牌主题下的硬约定，可显式设置最小尺寸。当前源码不能代替对 inherited compact theme 的实际验收。

这些细节不扩大为 route localization 或主题批量审计。

## 5. 交付与冻结

明确 blocker：修复 selected/today 的高强度 cell 对比。其余键盘、异步 picker、安全范围、future 交互、locale State、文字换行与窄宽结构，本轮未发现需要阻塞的源码缺陷。

测试作者在独立路径工作；本轮未读取或修改其草稿，未运行测试。屏幕阅读器实际宣布顺序、真实字体/主题与最终320px/2x渲染仍属于 root 后续验收证据。

所有源读取已结束；本报告交付后保持读取冻结，由 root 统一修订。
