# 热图最终细节复核

日期：2026-10-09。工作树：`/home/ubuntu/duoyi-worktrees/heatmaps-20261009`。

只读复核冻结源码中的 today dot、Today 日期控件与 Mood legend Flexible 修订。未修改源码或运行 SDK/检查/测试，未重读其他交互或测试路径。

## 源码判断：可接受

- [calendar_heatmap.dart:457](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/calendar_heatmap.dart:457) 改用约0.179的亮度分界与 opaque black/white。该分界接近黑白候选对比交点；既有 `#66BB6A` / `#4CAF50` 都会选择黑点，解决上一轮低反差白点问题。
- [calendar_heatmap.dart:349](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/calendar_heatmap.dart:349) 的 Today 是带 localized tooltip 的48×48 IconButton，仍只执行 `_select(widget.window.today)`；与前/后一天、Expanded 日期 picker 同行。日期文本可以换行增高，详情 callback 保留为独立按钮，没有把日期选择变成打开日记。
- [mood_heatmap.dart:86](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/mood_heatmap.dart:86) 的 legend sample 保留固定色块，文字改为 Flexible。sample 位于有限宽度 Wrap，Row 使用 mainAxisSize.min/loose Flexible；放大的长 label 可以在剩余宽度内换行，而不强迫色块+全部单行文字超出窄容器。

在这三处修订中没有发现新的实际源码问题，也没有剩余修订 blocker。

本报告只表示这些修订的源码可接受；focused analysis/tests 由 root 独立执行，本轮不代报其结果。所有源读取已经结束，保持冻结。
