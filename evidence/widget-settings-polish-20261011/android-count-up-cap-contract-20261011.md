# Android 正计时 24 小时封顶差异：源码证据与修复契约

日期：2026-10-11 UTC

核对提交：`391eb4f4580182525003403e5097fe4a56265249` (`391eb4f`)

## 核对结论

Flutter 正计时状态会把累计时长限制在 86,400 秒，iOS widget 也限制到 86,400 秒并在 cap 日期安排 timeline 刷新。Android 的静态秒数计算只限制到 `Int.MAX_VALUE`；实际活动显示则用完整的 `now - startedAt` 构造可运行的 `Chronometer`，没有 86,400 秒 cap。在 live 模式下，它还会隐藏承载静态格式化文本的 `TextView`。因此源码路径没有把 Android 的活动计时显示限制在 24 小时。

这是源码差异证据，不是真机观测结果。本次没有启动 Android emulator/device，也没有实际运行原生 `Chronometer`；超过 24 小时后的 Android 用户界面行为仍需真机验收。

## 源码证据

| 平台 | 证据位置 | 代码行为 |
| --- | --- | --- |
| Android | [`DuoyiFocusHabitWidgetProvider.kt:118-120`](../../android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt#L118) | 活动正计时计算完整 elapsed，只限制到 `Int.MAX_VALUE`，没有 86,400 秒 cap。 |
| Android | [`DuoyiFocusHabitWidgetProvider.kt:186-196`](../../android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt#L186) | 对可信的活动正计时启用 live widget；`setChronometerCountDown(..., false)`，base 使用完整的 `now - startedAt`。live 为真时隐藏静态 `widget_focus_streak_count`。 |
| Android | [`duoyi_focus_habit_widget.xml:160-174`](../../android/app/src/main/res/layout/duoyi_focus_habit_widget.xml#L160) | live 控件是原生 `Chronometer`，默认隐藏，由 provider 在活动计时时显示。 |
| Android | [`DuoyiFocusHabitWidgetProvider.kt:197-200, 330-349`](../../android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt#L197) | 接受的 render frame 才运行 alarm effect；当前 alarm 只传入 countdown 的 `endsAt`，count-up 会传 0 并取消该 alarm，没有 cap 边界刷新。 |
| Flutter | [`pomodoro_provider.dart:824-827, 1540-1541`](../../lib/providers/pomodoro_provider.dart#L824) | 每次同步将 count-up 状态限制在 `_maxCountUpSnapshotSeconds = 24 * 60 * 60`。 |
| Flutter | [`pomodoro_provider_test.dart:685-716`](../../test/providers/pomodoro_provider_test.dart#L685) | 25 小时前的运行快照恢复为 86,400 秒；完成结算时长同样为 86,400 秒。 |
| iOS | [`DuoyiWidgets.swift:73-123`](../../ios/DuoyiWidgets/DuoyiWidgets.swift#L73) | 正计时定义 `countUpCapSeconds = 86_400`，运行态 elapsed 被限制到 cap，并记录 `capDate` / `isAtCountUpCap`。 |
| iOS | [`DuoyiWidgets.swift:198-204`](../../ios/DuoyiWidgets/DuoyiWidgets.swift#L198) | timeline 会加入未到达的 cap 日期；达到 cap 后不再添加下一次 cap entry。 |

在 Android 源码中，`timerRemainingSeconds` 虽然会生成文本，但 live 控件显示时静态 `TextView` 被设为 `GONE`。因此只 clamp 静态文本或 `focus_timer_remaining_seconds` 不会限制当前活动的 `Chronometer`；修复必须作用于可见的 live 控件，并在 cap 到达时停止其增长。

## 状态、日期与 action 边界

- Android frame 在提交前会重新检查原始数据、widget options、时区、日期、UTC offset、locale 和时钟连续性；检查失败就拒绝本轮 render。相关实现见 [`DuoyiWidgetSnapshot.kt:38-86`](../../android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt#L38) 和 [`DuoyiWidgetFrameCore.kt:53-73`](../../android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetFrameCore.kt#L53)。countdown 有独立的到期拒绝规则，count-up cap 当前没有对应边界规则。
- 当前 widget quick-start 仅在 `frame.fresh && !storedRunning` 时发起启动 action；运行中的计时控件仍打开 Focus 页面，见 [`DuoyiFocusHabitWidgetProvider.kt:262-276`](../../android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt#L262)。cap 行为不能把这一入口改成暂停、完成或其它计时 mutation。
- Flutter 保留开始锚点，并从锚点重算 count-up 状态；已有 snapshot-boundary 测试覆盖阻塞后按锚点推进及开始锚点保持不变，见 [`pomodoro_snapshot_boundary_test.dart:259-270`](../../test/providers/pomodoro_snapshot_boundary_test.dart#L259)。cap 只影响显示与累计上限，不应清除或重写运行 session/account 数据。
- iOS 的 cap timeline 是 cap 时刷新路径现有行为的参照。Android 增加 cap 更新时，应沿用已接受 frame 的 effect 路径及 session/account 信任边界；旧计时器或旧 account 的延迟 alarm 不得影响新计时器或未绑定的 widget。

## AGY 有限修复契约

1. 活动正计时始终以 `elapsed = clamp(now - startedAt, 0, 86_400s)` 作为显示值。24 小时前仍使用现有 live count-up `Chronometer`，并保留 countdown 的当前显示和到期行为。
2. 到 cap 后，可见值为 `24:00:00` 并保持不变。必须停止或隐藏继续递增的 live `Chronometer`；只修改当前被隐藏的静态 `TextView` 不满足契约。保留现有 locale formatter 与 widget 样式。
3. 在已接受且 `sessionTrusted` 的活动 count-up frame 上，为 `startedAt + 24h` 安排一次 cap 边界刷新。刷新时重新读取当前 timer/account publication，并通过 `DuoyiWidgetSnapshot.renderWidget` 的 frame 验证后提交；若 session 已暂停、重置、替换或 account binding 失效，应取消/忽略旧 cap 请求。cap 请求应有与 countdown finish alarm 不冲突的身份，并在 cap 后停止重复调度。
4. cap 触发仅更新 widget 展示，不新增 pause/finish/start mutation，不产生完成 session、不改 account 数据，也不修改 Flutter 持久化的 start anchor。保留日界线、timezone/offset、locale 和 clock-change 防护。
5. 保留现有 quick-start 条件和行为：新鲜且无活动计时时才启动；活动计时时点击仍打开 Focus 页面。保留 24 小时前的 live timer、countdown、文案、样式和布局。
6. 实现后应补 Android 源码/单元覆盖：cap 前仍 live、恰好 cap 时停止并显示 `24:00:00`、cap 后仍冻结、延迟 cap alarm 对旧 session/account 无效，以及 countdown/action 行为不变。另需 Android emulator 或真机确认真实 `Chronometer` 的显示/冻结；本文件不代表这些检查已完成。

## 测试范围与限制

现有 Flutter provider 测试覆盖 25 小时快照恢复和最终结算 cap。针对 `android/app/src/test/java` 的关键词搜索未找到 Android count-up/86,400 秒 widget cap 测试；现有 `DuoyiWidgetFrameCoreTest` 覆盖的是 clock-change 和 countdown 到期等 frame 边界。现有 iOS resource test 检查共享计时字段，但没有发现专门验证 24 小时 cap 的测试。

本次仅读取源码、测试和文件状态，并写入本证据文件；没有运行测试、构建或设备命令。相关源码文件与 HEAD `391eb4f` 内容一致。`test/services/android_widget_resources_test.dart` 在共享工作区中有另一项 pin-receipt 静态断言改动，与本次 cap 证据无关。

## SHA-256

以下 hash 对应核对时工作区中的文件内容；列出的 cap 源码及 Flutter cap 测试相对 HEAD 未修改。

| 文件 | SHA-256 |
| --- | --- |
| `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt` | `a8e8fe9b9b558506c2a2cfbbfef8fded1fa9dd34da49741a04131aecfc24b40f` |
| `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt` | `98a73b8597906ca9c617cce5ef8963b285f724ae589e05ee159b68016c544351` |
| `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetFrameCore.kt` | `509c73770b631d31740a884774d498669badda55e3f25d4c6da24eabf832af7c` |
| `android/app/src/main/res/layout/duoyi_focus_habit_widget.xml` | `915519f64763f7ef671494e4f4e519f8c8ec74a095edf0f7dcb495ee38872f8f` |
| `lib/providers/pomodoro_provider.dart` | `64fd1ae1394a9021c9e1ed9cde2a17a665a8ea9d676a3df926c2bada5d887421` |
| `test/providers/pomodoro_provider_test.dart` | `1591f52fb0bd6b6206569e7247b7df539157d09d45c89409a3aeefa4c4df1460` |
| `test/providers/pomodoro_snapshot_boundary_test.dart` | `8d661f2331ae8fb3c1b61f04257ee26b10cd20f76271060d5d8f4004f6dcdb07` |
| `ios/DuoyiWidgets/DuoyiWidgets.swift` | `47beb6af03ddcaee65c5b5ad564de419677ae07662057b06442028210e0f4b38` |
| `android/app/src/test/java/com/duoyi/duoyi/DuoyiWidgetFrameCoreTest.kt` | `cc7ccd2c8fc9d59fbee2dc819b60d07bde505ea2c86e5d4413af346bfaf50175` |
| `test/services/ios_widget_resources_test.dart` | `6332a6dfa20fa95a8ecaba511ff0501f7be524470e8f31bebdbb5b9e087b2258` |
