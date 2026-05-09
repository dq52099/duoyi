# 手动回归清单（Task 25）

对齐 `.kiro/specs/app-alignment-overhaul/requirements.md`。在可用真机上按顺序走完以下 14 条，出现偏差在"状态"栏打叉 + 补截图到 Issue。

## 1. 启动 & 时区
- [ ] 冷启动后在"我的 → 关于"看到当前 IANA 时区信息（可选；至少日志里 `LocalTimezoneResolver.diagnostics` 为空或只有非致命回退）。
- [ ] 断网启动 → 所有 Tab 可用；App 底部不显示"同步失败"红色状态。

## 2. 推荐目标
- [ ] "目标"页右上 ✨ 按钮 → 打开推荐目标面板。
- [ ] 切换"健康 / 学习 / 运动 / 情感 / 推荐" 5 个分段，每个都有 ≥ 5 条条目。
- [ ] 点击任一推荐条目 → SnackBar "已添加到目标列表"；返回"目标"页能看到新条目。
- [ ] 新条目打开编辑页 → 8 个折叠模块（基础/重复/调度/跳节假日/专注/提醒/时长/次数）都可展开。

## 3. 任务交互
- [ ] 新建一个任务 → 详情页编辑标题 → 点 AppBar ✓ → SnackBar"已保存" + 详情页**不返回**。
- [ ] 继续改标题 → 按系统返回键 → 弹"放弃未保存的修改？" → 点"取消" → 仍在详情页。
- [ ] 再按返回 → 点"放弃" → 回列表，改动未落盘。
- [ ] 任务卡片显示：优先级色点、标签胶囊、下次提醒 HH:MM、目标时长 badge。
- [ ] 勾选完成 → 卡片**保留在今日列表**，显示"已完成"绿色徽章 + 删除线。
- [ ] 取消勾选 → 回到普通态，徽章消失。

## 4. 子任务 / 顺延
- [ ] 新建任务带 3 个子任务，`autoToggleByChildren = true`（默认）。
- [ ] 依次勾选 3 个子任务 → 父任务自动标为完成。
- [ ] 取消其中一个 → 父任务自动回到未完成。
- [ ] 新建任务设置昨日 dueDate → 下次启动或 resume 时 → `dueDate` 自动顺延到今日同一时刻，`postponeHistory` 增加一条。

## 5. 通知 vs 闹钟
- [ ] 任务详情页：提醒开关 = ON，kind = **推送**，时间 = 1 分钟后 → 到点系统通知中心出现，不全屏。
- [ ] 切换 kind = **闹钟**，时间 = 1 分钟后 → 到点**全屏 intent 弹出 + 震动**。
- [ ] Android 12+：第一次选闹钟弹"请开启精准闹钟权限"引导（`AlarmPermissionDeniedException` 被捕获时）。

## 6. 专注模式白噪音
- [ ] 番茄钟选"雨声" → 启动 → 扬声器真实播放循环雨声。
- [ ] 暂停 → 500ms 内静音（fadeOut 300ms + tail）。
- [ ] 锁屏并等 30s → 解锁后仍在播放（Android `foregroundServiceType=mediaPlayback`）。
- [ ] 切换到"无白噪音" → 立即停播。

## 7. Today 页
- [ ] 有待办时，"查看"按钮 → 进入 TodoScreen。
- [ ] 无待办 + 点某个已删除条目（模拟）→ 跳到 EmptyState 兜底页而非黑屏。
- [ ] 四个指标卡（待办 / 习惯 / 专注 / 日记）点击都能跳到对应 Tab。

## 8. 日历
- [ ] 月视图点击任一天 → 日期高亮 + 下方列表刷新为当日事项。
- [ ] 切换月份，选中的日期视觉跟随。
- [ ] 当日无任何事项 → 日代理区域显示"空态"。

## 9. 时区切换
- [ ] 设置几个闹钟提醒（H=20, M=30）。
- [ ] 把系统时区从 Asia/Shanghai 切到 America/New_York → 回到 App → 日志显示 `ReminderScheduler.resyncAll` 被触发；下次 20:30（新时区本地）仍触发。
- [ ] 壁钟时间不变，UTC 绝对时刻变。

## 10. 视觉态
- [ ] 加载中：LoadingState shimmer 条带正常动画。
- [ ] 错误态：ErrorState 显示错误文案 + "重试"按钮。
- [ ] 空态：EmptyState 含图标 + "新建"主按钮。

## 11. CloudSync v2
- [ ] `FeatureFlags.cloudSyncV2 = false`（默认）→ "我的 → 立即同步"不发出任何网络请求。
- [ ] 手动覆盖 `cloudSyncV2 = true` + 登录 → "立即同步"成功 → "有未同步改动"角标消失。
- [ ] 再修改一条任务 → "有未同步改动"角标重现。

## 12. Empty Surface Audit
- [ ] 运行 `pwsh scripts/empty_surface_scan.ps1` → `docs/empty-surface-audit-raw.md` 生成，命中条目数不高于上次基线。
- [ ] `docs/empty-surface-audit.md` 中 ⏳ 的条目是否已关闭（准备发版前）。

## 13. 测试套件
- [ ] `flutter test test/` 全绿。
- [ ] `flutter test test/services/no_toast_reminder_static_test.dart` 强约束全绿（P15）。
- [ ] `flutter test integration_test/app_alignment_smoke_test.dart` 在真机或 emulator 上全绿。

## 14. 黑屏 / 崩溃
- [ ] 逐页打开：Today / Todo / Habit / Calendar / Pomodoro / Mine → 没有 FlutterError 红屏。
- [ ] 冷启动、切后台 30s、杀进程再启动，三轮不崩。

---

**发版闸**：以上任何 ❌ 都不允许发稳定版。ℹ️ 项可以进待跟踪 Issue。
