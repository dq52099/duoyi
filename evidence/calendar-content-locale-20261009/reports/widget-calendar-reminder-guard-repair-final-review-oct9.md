# Calendar / Reminder guard final source review

2026-10-09。有限只读复审最终两处 feedback helper、time-entry origin失效监听/owned-route关闭、新旧分类guard及共享surface一致性。用户此前授权的日历补修范围由根会话确认。本轮没有修改源码/fixture、读取测试内容、执行测试/analyze/SDK/Git/网络或新增agent；未重审其余i18n。Luna正在执行的既有测试结果由根会话另行归档。

**前次唯一遗漏已修复；本次新增生产路径未发现可定位问题。** 此结论限于源代码，不是导航/跨账号/键盘运行验收。

- Todo feedback helper `calendar_screen.dart:1395–1402` 与 time-entry helper `1539–1546` 现在都先检查 `context.mounted`，再取得并确认非空且 mounted 的ScaffoldMessenger，然后才showSnackBar。前次time-entry的遗漏已消除。
- time-entry `initState:1565–1569` 同时监听accountDataGeneration和retained callerAvailability；`dispose:1588–1595` 移除两者及locale listener。新监听没有初始化draft/controllers或执行provider mutation。
- caller notifier在Calendar.dispose入口设置不可用并通知（101–102、1241–1247）；opening scope同时携带该listenable与caller predicate（1166–1173）。caller predicate包含notifier的disposed状态，因此通知期间Calendar State仍mounted也会正确失效；晚注册监听亦立即收到失效通知（1251–1254）。
- `_onOriginChanged:1572–1580` 仅在mounted且origin无效时安排一个post-frame回调，调度后再次检查mounted/origin，并使用同一个owned-route helper；不会在dispose/build通知中同步导航。重复通知被scheduled标记合并。
- helper `1528–1536` 检查缓存route的activity；只有该route为current时pop，否则removeRoute该精确引用。与新监听组合后，不会因分类menu或无关route位于top而pop它们；已移除route不再关闭。
- 分类入口/返回谓词 `1679–1685` 与始终非空的onChanged `1694–1701` 保留mounted、origin、submitting、saved检查。共享field在entry、void onTap后、keyboard await后及menu await后/pre-didChange处重检（surface `2354–2370`），仍覆盖stale-origin opening与本地FormField变更边界。Reminder Type call site未变化，其此前通过的guard保留。
- 最终两树surface文件cmp退出码0，实际字节一致；本轮未将无关空行差异当作行为修复。

新监听只使失效的time-entry surface主动关闭；没有增加业务回调、改变locale资源、改变draft enum/ID或清理用户数据。已合法启动的provider操作仍按原provider fencing处理，UI关闭不是回滚承诺。

## 最终实际源指纹

| 文件 | SHA-256 |
| --- | --- |
| calendar `lib/screens/calendar_screen.dart` | `bc35b8ad9f03889144332ef811f3c345f2f8d74a3fac697e8a82b5d3a6c1a244` |
| calendar `lib/widgets/surface_components.dart` | `9ea733e62913e0f818f8c7c9d7e54bb5d99de3b053ec2973bd800ac4aec2c591` |
| reminder `lib/widgets/reminder_plan_editor.dart` | `ef2be0025c93771d6c63b53722cebd33db3ab15eadfdb584c449d322de3f759a` |
| reminder `lib/widgets/surface_components.dart` | `9ea733e62913e0f818f8c7c9d7e54bb5d99de3b053ec2973bd800ac4aec2c591` |

calendar根路径：`/home/ubuntu/duoyi-worktrees/calendar-content-locale-20261009`。reminder根路径：`/home/ubuntu/duoyi-worktrees/reminder-editor-locale-20261009`。

本报告取代 `widget-calendar-reminder-guard-repair-review-oct9.md` 对time-entry feedback未修复的最终结论；前份记录保留作修复历史。源码读取在本报告完成后停止。
