# Widget action 文案实现审计 — 2026-10-08

## 最终结论

初读发现并即时通报的三项有界问题，均已由根 agent 修正并经过本 agent 重新读取生产源码确认。当前审查范围内无进一步有界 blocker，可进入根 agent 的新回归批次。此结论是源级审查，不等同于测试或平台运行通过。

只读范围：`lib/main.dart`、新增 `lib/services/widget_action_message.dart`、generic `lib/services/widget_quick_todo_action.dart`、未改动的 `WidgetActionScope`，以及用于核对事实契约的 NotificationService、TodoProvider、ReminderScheduler、CloudSyncProvider 公共实现。未编辑 production source 或 fixtures，未运行测试、分析、构建、网络调用或干预进程。此报告不以其他 agent 尚未完成的 fixtures 为实现证据。

## 已确认保留的契约

- `WidgetActionScope` 内容未变，仍在排帧回调执行前检查原 account-data generation 与 caller predicate，再调用反馈闭包。
- `_createQuickTodoFromAction` 在任何 preflight/permission await 前绑定原 `AuthProvider` 与 `TodoProvider`，create 闭包使用原 `todos`，没有 await 后重读 provider 进行 mutation。generic coordinator 的 await 顺序、preflight 前后 guard、create 后 feedback guard、catch guard 均与原实现相同。
- 两个 widget feedback helper 都在 `scope.afterFrame` 的实际回调内，取最新 shell/fallback context，检查 mounted，随后才执行 `message.render()`。`render` 在调用时读取 `I18n.current`；descriptor 构造、排帧和 coordinator 都不提前 render。
- renderer 的可选显式 locale 只选择本次中英分支，不更改全局 locale。任务标题、习惯名称、原始 native title/message/issue 与 sync reason 都作为 final 字段保存，不解析中文、不调用 `NotificationUiCopy.formatIssueText`、不重新查询名称。
- typed widget preflight 使用 `_preflightWidgetTodoReminder`。原 String `_preflightQuickTodoReminder` 只委托这一份算法并在回调中 render，dialog/share 仍收到 String；没有复制权限算法。原 `_quickTodoCreatedMessage` 也保留 String wrapper，widget 直接使用 typed `_quickTodoCreatedNotice`。dialog catch 中的 shell fallback 已改为 descriptor，所有 main typed feedback 调用均完成迁移。
- `_quickTodoCreatedNotice` 只捕获同步事实和原因，后续 render 不重新读取 provider。保存成功仅描述本机保存、同步未上传/未确认/稍后后台上传；未宣称上传完成。提醒 hint 仅引导检查设置/详情。`TodoReminderSyncResult.issue == null` 的 timeout 路径也没有变成“已确认注册”。

## 已通报并闭环的问题

### 1. reminderIssue 与保存后提醒 issue 的外层措辞过强 — 已修正

初读 `reminderIssue` 在任何原始 title/message 前追加“提醒未注册 / Reminder not registered”。main 的 NotificationService issue 分支没有携带 `NotificationScheduleIssue.blocking`，因此不能根据这个 descriptor 区分 blocking failure 与 nonblocking warning。channel unknown/blocked/silent/probe-exception 会记录 `blocking:false`，原始原因明确写有“继续注册 / 已注册但可能无声或不显示”。正常这些 probe 返回 ready=true 并提前退出 preflight，不会日常进入 false 分支；本报告不声称正常 channel warning 必然走到错误包装。但 catch 的 false 分支可读取保留的 lastScheduleIssue，统一“未注册”包装本身仍没有事实依据。

保存后分支的 `TodoReminderSyncResult.issue` 只有 String，没有 registration severity。`ReminderScheduler._syncRuleObjects` 在同一轮保留成功 rules 到 `kept`，同时收集失败 rules，最后才抛出汇总异常。widget `addTodoWithResult` 未开启 `reportReminderScheduleFailure`，默认执行全量 `syncTodos`，所以 issue 还可能来自其他任务。非空 issue 不足以断言新任务的所有提醒未注册。

最终实现：`WidgetActionNotice.reminderIssue` 使用“提醒状态需检查 / Reminder status needs attention”外层，`savedReminderIssue` 使用“本机已保存，检查提醒状态”外层，原始 title/message/issue 完整附加。main 创建分支也已使用新 enum 名。两者都不再推断所有提醒未注册；原生字段本身可能包含注册/无声/渠道等措辞，按无损契约保留。

证据：[中性 renderer](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_action_message.dart:215)、[widget 创建结果](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4188)、[native issue 字段传递](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4495)。

### 2. pure sync adapter 的空 retry reason 优先级 — 已修正

初读 factory 只用 `retryPending` bool 决定 retry state；provider `localSaveSyncMessage` 则仅在 `syncRetryStatus?.trim()` 有内容时优先使用 retry，否则继续看 pendingChanges + lastError，再到后台上传。现有 main 传 public getter，它在 internal reason 为 null 时生成非空默认文案，当前 setter 调用也都有非空 stage prefix，故不是已证明的正常生产误分支。最终 pure adapter 已使用 `retryPending && (retryReason?.trim().isNotEmpty ?? false)` 才进入 retry；reason 赋值仍保留未 trim 的原文，空 retry 可继续进入 error/background 分支。

最终优先级吻合：feature disabled → account transition → unauthenticated → server backup disabled → autoSync off → nonblank retry → pendingChanges + nonblank lastError → background upload。lastError 同样只用于非空检测，字段保留原文。

证据：[pure facts adapter](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_action_message.dart:52)、[provider 原优先级](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/cloud_sync_provider.dart:212)、[main public getter 绑定](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4567)。

### 3. 显式空 issueTitle 的兼容性 — 已修正

旧 String API 接受任何 literal issueTitle，包括 `''`。初读 main 把 omitted 与 `''` 都存为 subject 空串，renderer 再以 `subject.isEmpty` 选择默认标题，导致明确传入 `issueTitle:''` 被替换为默认值。非空自定义标签和空白字符串保持原样。最终 descriptor 单独保留 `final String? issueTitle`，renderer 用 `issueTitle ?? bilingualDefault`；main 配置异常、无具体 issue、alarm denied 分支传入 nullable 原文，不再借 subject 识别缺省。因此 null 在 render 时选当前 locale 默认标题，而明确的空串、空白和任何自定义标签均保持 literal 值。service 的 issueTitle 调用仍原样保留自定义值；原始 native issue.title/message 的展示路径也未改写。

证据：[nullable label 与 renderer](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_action_message.dart:93)、[String preflight wrapper](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4417)、[typed preflight 字段](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4439)。

## 边界与验证限制

本批迁移覆盖 widget-owned 文案及三个共享 helper 的兼容接口。dialog/share 仍保留自己的直接中文 UI、自己的 reminder issue String 包装和异步账号流程；本报告不把这次迁移描述为全页面 i18n 或这些入口的账号边界修复。上游 service/native 原因可能仍是中文，这是保留原始事实字段的结果。

本报告是 source review，未执行 runtime fixtures、测试、analysis、build 或端到端平台验证。generic String 推断与 typed 接口保留是源级检查结论，运行结果由根 agent 的独立验证批次记录。

## 最终审读生产指纹

Base HEAD：`0320cd6e4475ade690e4d4e5ba7f244105809819`。下面 SHA-256 对应三项修正后、根 agent 开始新回归前的 production 内容；source/core review 未读取 fixtures。

| 文件 | SHA-256 |
| --- | --- |
| lib/main.dart | ddb0a6d8c0f966d95a4da433602573d7a83fb541eb0e1e67cc6df638ff523b20 |
| lib/services/widget_action_message.dart | 231146b7fd2799d75da5ab747b214bddd204ae49c59b9f299fbeea5c33f10af5 |
| lib/services/widget_quick_todo_action.dart | b5d99d781800c8cb0d596b23a50ce752c69d0d7c8bd8bd89e19ca157a8e0c2fa |
| lib/services/widget_action_scope.dart | caaf1b0f6d4d2c3e0a369b38cddced1c29bf2fa78d53f657a6abbb2d4d446ead |
| lib/providers/cloud_sync_provider.dart | a7b29554dafd02a50ea4c725914fda1ac91f6cc9986f49a282ea4e6f0c7444c9 |
| lib/providers/notification_service.dart | 69b8411b0eb0bff0289f8bbbbdac44b01f1c451f5545f480dcab79d9bfc3c27c |
| lib/providers/todo_provider.dart | 933e150ff316a45a498726f1d2f3596ad9ea99253636c0455757a88e887ef1b1 |
| lib/services/reminder_scheduler.dart | ac4de46ab83e2e822883bcb73b49b5b0213dc4380710cab8dbbd3d878ac45c74 |

## 关键交付位置

| 契约 | 生产代码位置 |
| --- | --- |
| scope 在实际 frame 前检查原账号与 caller | [WidgetActionScope.afterFrame](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_action_scope.dart:19) |
| locale 在 scope + mounted 后读取 | [context feedback](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4118)、[shell feedback](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4137) |
| 原 provider 在 await 前绑定、typed create | [widget quick create](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4157) |
| generic coordinator 保留原 guard 顺序 | [runWidgetQuickTodoAction](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_quick_todo_action.dart:9) |
| String created wrapper 与 typed status 快照 | [created notice](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4548) |
| raw 名称只作为参数保存 | [完成名称](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4367)、[打卡名称](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4337) |
| nonblocking native warning 正常继续注册 | [channel readiness](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/notification_service.dart:571) |
| issue=null timeout 不确认注册 | [TodoProvider reminder result](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/todo_provider.dart:583) |
| mixed rule success 与 raw failure 汇总 | [ReminderScheduler rule outcomes](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/reminder_scheduler.dart:4380) |
