# 热图交互修订复核

日期：2026-10-09。工作树：`/home/ubuntu/duoyi-worktrees/heatmaps-20261009`。

本轮只读取格式化后冻结的 `calendar_heatmap.dart` 中新增选中外圈/今天圆点、weekday TextPainter 测量与日期按钮尺寸部分；没有重新审阅其余架构或测试。未修改生产源码、运行 SDK、检查或测试。

## 1. 已修复

- **选中标记与高强度填充脱离**：[calendar_heatmap.dart:416](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/calendar_heatmap.dart:416) 的外容器使用 onSurface 选中边框、surface 背景及1px间隔；内部填充保持原颜色。最高强度接近 primary 时，选中边框不再同色融入填充。外圈是平面结构，没有重加 cell shadow。
- **today 与 selected 分离**：today 使用内部右下圆点，selected 使用外圈，两者可同时存在；语义上的 today 与 selected 状态仍保留。
- **weekday 布局由实际文字决定**：[calendar_heatmap.dart:155](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/calendar_heatmap.dart:155) 用继承后的实际 TextStyle、方向与 TextScaler 测量四个可见 weekday；axis width/pitch 分别取测量值加余量。TextPainter 在读取结果后 dispose，不保留临时资源。
- **日期控件尺寸明确**：前/后一天使用48×48约束；日期 picker、Today 和可选详情按钮显式指定48×48 minimumSize，长文字仍可增高/换行，没有添加固定文本高度。

## 2. 尚需修订：today dot 的亮度阈值

位置：[calendar_heatmap.dart:446](/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/widgets/calendar_heatmap.dart:446)。

目前 fill luminance >0.4 才使用 black87，其他情况使用 white。该阈值对现有 mood palette 会选择较弱的候选：

| 现有填充 | 近似相对亮度 | 当前圆点 | 近似对比 |
| --- | --- | --- | --- |
| light Mood.good `#66BB6A` | 0.395 | white | 2.36:1 |
| dark Mood.awesome `#4CAF50` | 0.328 | white | 2.78:1 |

这是从现有颜色常量和亮度公式推导的结果，未运行 widget/设备测试。3px today 标记在这些格子上仍偏弱；黑点比白点更合适。

建议选择黑/白候选中实际对比更高的一项；如果保留 black87，比较时计入其与填充的 alpha blending。较简单的实现是 opaque black/white 的对比选择，避免使用0.4这个偏高的切换阈值。也可降低阈值到约0.2，但直接比较候选更清楚。

选中外圈已通过复核；本轮唯一残留的实际修订项是这项 today dot 颜色选择。

## 3. 范围与交付

没有发现此次 weekday 测量或控件尺寸修订引入新的明确源码问题。root 的 focused run 独立进行，本报告不代报其结果。

所有源读取已结束，保持冻结；root 可按这一个 dot 修订项统一处理。
