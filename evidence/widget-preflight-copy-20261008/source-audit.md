# Reminder issue locale 契约审计 — 2026-10-08

## 结论与本轮推荐

根 agent 提出的 **todo-preflight 五种原因独立 typed copy 切片** 已实施，本 agent 对四个实际生产文件重新进行了只读审查。当前范围内无有界 blocker：七处canonical原文逐字保留、preflight规则控制流与scheduledTime不变、locale在WidgetActionMessage内只解析一次并显式传给copy。它能把小组件实际收到的 app-owned preflight title/message 按交付语言显示，同时保留旧raw constructor、String callers、blocking、日期和账号/frame边界。完整源码结论与最终hash见末节；本报告未运行测试。

这只闭环 todo-preflight 原因的 typed widget + main 共享 String wrapper 路径。NotificationService、AlarmService/popup、scheduler String aggregate 仍是后续独立工作；其他页面直接读 raw title/message 也不会自动双语。不能把第一切片描述为全局或 native 原因管道完成。

本报告只读当前生产源码和实际 callers，未编辑 production、fixtures 或 docs，未执行测试、analysis、build、网络调用。私有报告是唯一写入。初读设计审查基线为 `0320cd6e4475ade690e4d4e5ba7f244105809819` 的widget-message工作树；实施后production review基线为已提交前批的 `6a978fa7d8a7b7c6294aa52840a360e2ed1f7ef0`。

## 真实数据路径

| 路径 | 当前字段 / 类型 | 在何处丢失结构 |
| --- | --- | --- |
| `_preflightWidgetTodoReminder` → `preflightTodoReminderPlan` | `TodoReminderPreflightIssue(title,message,blocking,scheduledTime)` | main 只把 blocking.title/message 放入 WidgetActionMessage 的 raw subject/detail |
| 同一 preflight → `NotificationService.ensureReadyForReminder` | `NotificationScheduleIssue(title,message,happenedAt,scheduledTime,relatedId,blocking)` | issue title/message 同样作为 raw subject/detail；无稳定 code |
| 创建 → `TodoProvider.addTodoWithResult` → `_syncTodoRemindersNow` | `TodoReminderSyncResult.issue` 为 nullable String，另有 generation/attemptedAt/succeededAt | scheduler List<String> failures → `join('；')`；未知异常 `toString()`；typed 来源不能恢复 |
| todo rule scheduler → push/alarm/popup | result-bearing push bool、AlarmScheduleIssue、popup exceptions | `_recordDispatchIssue` 用 error.toString；generic rule summary 只有String；alarm bridge额外执行现有blocking classifier |

生产 main 明确注入 `ForegroundReminderPopupSink(notificationFallback: notificationService)` 和 BackendReminderEmailSink，因此 popup 不是推测路径。email 的 HTTP错误仍属于外部/不透明原因，不应通过中文匹配变成 typed local code。

## 第一切片：精确的五个 preflight code

[preflightTodoReminderPlan](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/reminder_scheduler.dart:115) 有 **7 个 issue 构造点、5 个不同 app-owned 原因**。全部当前采用 blocking=true 默认。

| 实施 code | 实际位置 | 原 legacy title / message 必须逐字保留 |
| --- | --- | --- |
| `missingDate` | absolute、relativeToDue 两处无 anchor | 待办提醒注册失败 / 一次性提醒需要截止日期或提醒日期。请先设置未来的日期。 |
| `timeInPast` | absolute、relativeToDue 两处不能 coercion 的时间 | 待办提醒注册失败 / 提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。 |
| `invalidRepeatTime` | dailyTime hour/minute无效 | 重复提醒注册失败 / 重复提醒缺少有效时间，请重新选择提醒时间。 |
| `invalidWeeklyRule` | weeklyTime时间无效或weekdays为空 | 每周提醒注册失败 / 每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。 |
| `noDeliverableRule` | deliverableRules==0且issues为空的兜底 | 待办提醒注册失败 / 提醒计划没有可注册的规则，请重新设置提醒。 |

这里 code 只选择 app-owned title/message 文案，不能决定 blocking、registration success、规则选择或时间校正。`timeInPast` 两处现分别保存 base/when，不能丢失或重新读当前时间。70秒 same-minute grace、enabled规则筛选、firstScheduledTime、kinds、deliverableRules 和 mixed valid/invalid 的当前阻塞政策都保持原样。

### 第一切片的 exact files

| 文件 | 最小修改职责 |
| --- | --- |
| 新 `lib/services/todo_reminder_preflight_copy.dart` | immutable TodoReminderPreflightCopy、五个显式notice、zh/en title/message renderer；无provider、异步、全局locale写入或raw-string匹配 |
| `lib/services/reminder_scheduler.dart` | TodoReminderPreflightIssue增加可空copy；旧raw constructor原接口保留；coded factory同时构造copy和原始title/message；只替换上述7处构造点 |
| `lib/services/widget_action_message.dart` | 新增optional preflightCopy；reminderIssue render在同一次effectiveLocale下显示coded title/message，copy为null仍使用raw subject/detail |
| `lib/main.dart` | blocking branch捕获 `blocking.copy`；继续保留subject=blocking.title、detail=blocking.message；不提前render、不改false/await/mutation/feedback scope |

实际renderer采用title/message两个方法，WidgetActionMessage先解析一次 `final effectiveLocale = locale ?? I18n.current`，再把同一个locale显式传给preflightCopy的两个方法。copy方法也支持省略locale时读取current；实际widget路径与coded factory均显式传入，因此不会再次隐式读取。renderer不修改legacy字段。

coded factory 的 canonical legacy字段是原中文字符串，不使用构造时 I18n.current，不把英文render结果反写到title/message。旧显式custom issueTitle（包括空串）、String preflight wrapper和unknown raw issue路径不变；blocking preflight分支原本显示blocking.title，没有套custom issueTitle，本轮不要改变这个兼容行为。

### 第一切片的兼容边界

- 原 `TodoReminderPreflightIssue(title:...,message:...)` 可继续创建任意原文；copy=null，任何包含“通知权限/提醒失败”等字样的用户或外部文本都不能被推断为code。
- WidgetActionMessage 没有copy时，当前中性raw reminderIssue wrapper及raw title/message保留行为不变。
- `_preflightQuickTodoReminder` 已是一份typed算法的String wrapper；它会立即render新copy，所以 main dialog/share 的preflight失败跟随当前locale，不复制权限检查。
- `todo_detail_screen.dart:1360`、`quick_capture_fab.dart:319`、`ai_schedule_screen.dart:148` 同样直接使用preflight，但还拼接raw字段。这些是可明确交给AGY的consumer接线，第一切片不能宣称已覆盖它们。
- coded factory和optional descriptor是本地presentation扩展，不能触及ReminderNotificationSink/AlarmSink的方法契约、调度队列、同步结果、通知历史或平台权限。

### 第一切片 acceptance cases

1. 五个code分别显式zh/en render；中文输出与旧title/message逐字一致，英文title/message不回退中文。
2. 两种one-shot anchor缺失、两种时间已过、invalid daily、weekly时间或星期缺失，均保持blocking=true、kinds/firstScheduledTime和返回false结果；past-time的scheduledTime字段保持原值。
3. same-minute grace允许的提醒仍无新的blocking issue；关闭plan/无enabled rules仍返回原无问题结果；mixed valid/invalid规则仍遵循原阻塞策略。
4. legacy raw issue constructor、未知中文原因、混合语言及看起来像code含义的文本保持literal；不通过contains/regex猜code。
5. 同一个message排帧后zh→en/en→zh，在实际guarded frame才render；账号切换仍抑制旧反馈。显式renderer locale不修改I18n.current。
6. String wrapper仍只执行一次preflight/权限流程并返回String；custom issueTitle:null/空串/空白/非空原文契约不退化。
7. scope/coordinator/provider绑定哈希不因copy接线变化；无需加入“已注册”或“已上传”成功推断。

这些是验证需求，本报告未新增或执行fixture。

## 后续切片一：NotificationService 的 typed issue metadata

[NotificationScheduleIssue](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/notification_service.dart:72) 当前只有raw字段。核心可添加optional `ReminderIssueCopy` metadata并在已知producer位置赋code，不重写raw字段。

widget实际经过的 `ensureReadyForReminder` / `_ensureChannelReadyOrRecord` / `_scheduleOnceOrRecord` / `_scheduleDailyOrRecord` 可以完整覆盖：

| app-owned 原因组 | 当前结果 / 严重性 |
| --- | --- |
| 提醒时间已过 | false、blocking=true |
| 系统通知权限未开启 | false、blocking=true |
| 提交后permission refresh未授权、未确认注册 | false、blocking=true；once/repeating原文有区别 |
| 普通渠道状态未知、blocked、silent、probe exception | true、blocking=false，继续注册/保留已注册但可能不显示或无声的含义 |
| 系统通知一次/重复调度异常 | false、blocking=true；拥有的外层说明可翻译，捕获异常作为literal detail |
| alarm降级push fallback | 保留当前producer行为和原blocking值；不能因为文案有“已降级”就自行改warning |

`ensureReadyForReminder` 的String issueTitle是兼容API。给app-owned默认标题单独显式title code/copy；自定义title值原样保存（含空串），不比较它是否等于某段中文来推断ownership。main已知默认标题的render可在交付时切换语言，service记录仍保存原捕获raw title，保持现有signature身份。

[record signature](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/notification_service.dart:497) 是 title + message + scheduledTime + normalizedRelatedId + blocking，窗口30秒。duplicate分支仍更新happenedAt/RecordedAt和lastIssue对象，但不notify。两处构造新NotificationScheduleIssue都必须复制typed metadata，否则重复问题会丢语言能力。metadata不加入signature，render不触发record、notify或save。

`_lastScheduleIssueIsPermissionOnly` 当前依赖canonical raw字符串，requestPermission/refreshPermission据此清理。此语言批次保留原raw和该流程；不能因换英文存储导致permission-only问题无法清除，也不能把全部warning都清除。

NotificationScheduleIssue不是通知history记录：它没有toJson，也未写`duoyi_notif_history`。history另有NotificationItem/title/body/isRead及scheduled-record去重；issue metadata迁移应保持这些schema、数量、未读与调度记录身份不变。要翻译系统通知内容与旧历史是另一个明确设计工作，不能以本次issue双语宣称完成。

### Sink 接口兼容

实际`ReminderScheduleIssueSink`由NotificationService及既有fake sinks实现。直接给abstract方法新增optional named copy参数也会要求所有implementers更新，属于接口改动。

最小兼容方案：在`lib/services/reminder_sinks.dart`增加独立optional typed capability（例如 `ReminderScheduleIssueCopySink`），保持原 `ReminderScheduleIssueSink`签名；producer/helper遇typed sink就提交canonical raw + metadata，否则调用旧raw sink。NotificationService实现新capability，两种入口最终共用同一_recordScheduleIssue逻辑；fallback不能执行两次record。这样旧fake/external sink仍可消费raw契约，typed能力逐步接入。

## 后续切片二：scheduler aggregate → TodoProvider → widget

仅给NotificationScheduleIssue加code仍不够：widget保存后消息消费的是String `TodoReminderSyncResult.issue`。完整typed汇总至少要把下列实际丢失点一起接通：

- `ReminderScheduleSyncException.failures` List<String>及toString；
- `_unresolvedTodoReminderFailureSummary`、`_ruleScheduleFailureSummary`；
- `_todoScheduleFailures` Map<String,String>、`syncTodosAndGetTodoFailure`；
- `_recordDispatchIssue`捕获error.toString、`_recordTodoRuleDispatchFailure`app-owned兜底；
- TodoProvider同步正常/异常/timeout后late completion三个分支；
- `TodoReminderSyncResult` optional typed aggregate；
- WidgetActionMessage的savedReminderIssue descriptor。

建议增加immutable typed aggregate，由每个entry同时携带canonical legacy string和optional copy。unknown entries保持raw，不拆joined字符串推断code。保留`ReminderScheduleSyncException(List<String>)`原构造、failures和toString，新增named typed factory/field或平行typed result API。原 `syncTodosAndGetTodoFailure: Future<String?>` 作为兼容wrapper，新增typed result API使用同一个serialized实现；不能再运行一轮scheduler。

TodoReminderSyncResult保留nullableString issue/hasIssue、generation、attemptedAt、succeededAt，新增optional typed aggregate。`reminder_scheduler_missing`这一本地固定原因可以明确赋code，但legacy issue仍是原literal。空failures fallback也是明确code；任意异常toString只成为rawentry，不做字符串识别。

不能改widget的默认`reportReminderScheduleFailure=false`来借此简化类型：默认汇总本来可能含其他任务失败，需保留来源和neutral wording。mixed成功/失败 rules 的已注册部分保持原有队列；typed“失败”不能变成“所有提醒未注册”。timeout仍issue=null/succeededAt=null，不能因typed field空就宣称注册已确认。late completion继续经过原generation/account guard，再同时更新legacy和typed事实。

### Alarm 与 popup 的必要边界

`AlarmScheduleIssue`没有blocking；[scheduler alarm bridge](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/reminder_scheduler.dart:2176)计算 `effectiveBlocking = suppliedBlocking || _isAlarmScheduleIssueBlocking(rawTitle,rawMessage)`。原phrase列表包含“已降级注册”“精准权限未开启”“内置闹钟已注册但兜底失败”等，并影响dispatch返回值。人类语义上像warning的原文，不代表当前调度契约允许它为nonblocking。

本轮语言metadata应继续传递这个**现有计算结果**，保持canonical raw供旧classifier读取，不让renderer/code重新判定severity。若随后要移除substring classifier，必须另做完整行为等价验证；不能在语言迁移中静默修正它。typed Alarm metadata可覆盖 `_tryNativeRingtone`、`_finishScheduleIssue`、once/repeating的权限/精准回退/partial native成功/queue确认分支，未知native/plugin error作为literal detail。

`ForegroundReminderPopupSink` 是实际生产sink。它在fallback更新失败记录blocking=true，在“前台已展示但下一次fallback重建失败”记录blocking=false。其app-owned StateError（past-time、once/repeating fallback false）需有明确typed exception/copy才能穿过scheduler；不要只翻外层然后把已知内部中文继续当作unknown。必须保留fallback与timer的generation、操作串行、3秒popup去重和cancel-after-dialog行为。

`NotificationScheduleUnavailableException` 当前丢失typed来源，后续应增加optional copy/metadata，但title/message/toString保持兼容。`AlarmPermissionDeniedException`、`AlarmQueueHandoffException`及popup fallback异常同理。typed exception识别通过类型/字段，未知Object仍原样保存。

具体后续core/service文件为：`reminder_issue_copy.dart`（扩code）、`notification_service.dart`、`reminder_sinks.dart`、`notification_permission_exception.dart`、`alarm_service.dart`、`foreground_reminder_popup_sink.dart`、`reminder_scheduler.dart`、`todo_provider.dart`、`widget_action_message.dart`、`main.dart`。实际`local_notifications_io.dart:886`的app-owned past-time StateError可在生产位置附typed来源；未知PlatformException保持raw。server HTTP/email消息不属于可从客户端字符串推断的本地code，当前无需backend/main.py改动。

## AGY consumer 接线交付边界

完成producer metadata后，可把明确consumer名单交给AGY按shared renderer接线：

- preflight：todo_detail_screen、quick_capture_fab、ai_schedule_screen；
- NotificationScheduleIssue：上述页面，加habit_screen/habit_detail_screen、countdown_screen、anniversary_screen、notification_history_screen的测试反馈/每日slot保存错误。

这些页面当前或直接拼`issue.title/message`，或只取issue.message。[NotificationUiCopy.formatIssueText](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/core/notification_ui_copy.dart:569)采用contains并替换整句，能丢失异常后缀与降级/未确认含义；新typed路径不能依赖它。可以新增typed-aware formatter（explicit locale；copy有值走code；copy无值返回raw）；旧raw formatter兼容由其既有callers决定，不能把未知原因自动翻成通用权限失败。

本报告未扩展前端样式、notification body、系统channel名称、旧history翻译或Swift/Kotlin原生UI任务，也不以该名单宣称整个app full-flow已验收。

## 后续完整管道 acceptance 要点

- 同code双locale显示，canonical raw fields不变；未知raw含中文、引号、服务诊断后缀仍literal；explicit custom label和空串不被当缺省。
- channel未知/blocked/silent/probe-error仍true + blocking=false；permission/past-time失败仍false + blocking=true；成功后relatedId范围清理和channel-warning保留不变。
- 同一问题30秒内重复仍无额外notify，时间更新和typed metadata保留；locale render不改变signature、history数量/未读、pendingCount或触发重新调度。
- alarm所有现有partial/degraded/native-success/plugin-failure分支的effectiveBlocking和dispatch result与迁移前相同；原始unknown detail不参与新增type推断。
- popup fallback失败、前台展示后重建warning、重复注册、visible dedup、取消/账号换代都保留原control flow。
- typed aggregate保留失败顺序、raw entries和legacy join结果；full-list与target-only来源不混淆；mixed结果和timeout不夸大注册成功或全部失败。
- 旧sink/fake、旧exception/String result API仍工作，新增typed接口单次调度/record；late result在账号或request generation失效后仍抑制。

## 本次审读指纹（第一切片实施前）

| 文件 | SHA-256 |
| --- | --- |
| lib/main.dart | ddb0a6d8c0f966d95a4da433602573d7a83fb541eb0e1e67cc6df638ff523b20 |
| lib/services/widget_action_message.dart | 231146b7fd2799d75da5ab747b214bddd204ae49c59b9f299fbeea5c33f10af5 |
| lib/services/reminder_scheduler.dart | ac4de46ab83e2e822883bcb73b49b5b0213dc4380710cab8dbbd3d878ac45c74 |
| lib/providers/notification_service.dart | 69b8411b0eb0bff0289f8bbbbdac44b01f1c451f5545f480dcab79d9bfc3c27c |
| lib/services/reminder_sinks.dart | 18dbf9ef3e09b9e975a3a82d6d6a32aeddb15b938f8b15de7a96fb950c34f868 |
| lib/services/notification_permission_exception.dart | a21a4d6ce7e4bbe8158c82cc68883addf25c3b14ea814eb9a2acfd60e307d0d4 |
| lib/services/alarm_service.dart | 232e971f69d2606fb1e4a1cbc695661bda638449461bb6be07ae95f0a2b7661d |
| lib/services/foreground_reminder_popup_sink.dart | 84f0ca729e119423ad26301b8097fd59f35dc9b5bfc3c3ebba0fa9bbbd63c37a |
| lib/providers/todo_provider.dart | 933e150ff316a45a498726f1d2f3596ad9ea99253636c0455757a88e887ef1b1 |
| lib/core/notification_ui_copy.dart | 6054d3d76df54cfa0ea4cdcbdb24450641cf7a7fe66d1132c1bdbdde2df4b2b2 |

## 实施后 production audit — Base 6a978fa

实际四文件切片为：`lib/main.dart`、`lib/services/reminder_scheduler.dart`、`lib/services/widget_action_message.dart`、新增`lib/services/todo_reminder_preflight_copy.dart`。未读取fixture agent的新增测试作为审查证据，未运行任何Dart/Flutter命令。以下为源级审查结果：

- coded factory以显式`AppLocale.zh`生成canonical title/message，保留原constructor默认blocking=true和nullable scheduledTime。copy immutable且不携带permission/blocking决策。
- 七处构造点按顺序映射missingDate、timeInPast、missingDate、timeInPast、invalidRepeatTime、invalidWeeklyRule、noDeliverableRule。只读源码比对确认各处生成的title/message UTF-8字节与base原literal一致。
- 用等价占位替换新旧issue构造块后，整个preflight function源码一致；两条scheduledTime参数仍分别为base/when。不是运行证明，但直接限定了本轮control-flow差异。
- scheduler从`_effectiveTodoPlanForPreflight`开始到文件尾与base逐字一致：grace、规则解析、所有alarm/popup/queue行为、blocking classifier、去重和summary未受本切片修改。
- main相对base只有`preflightCopy: blocking.copy`这一行生产改动，raw subject/detail与return false保留，provider捕获、String wrapper、frame guards均未改变。
- WidgetActionMessage在render入口用一次`locale ?? I18n.current`决定effectiveLocale，并显式传给title/message；preflightCopy为null仍回退原subject/detail。其他notice/issueTitle/raw native/savedReminderIssue/sync render行为未变。
- 新copy类的两个方法按显式code分支提供中英文本，无substring/regex识别、无provider查询、无全局locale mutation。英语timeInPast明确保留“未注册”的阻塞原因；本轮不覆盖降级/非阻塞native文案。

**当前结论：无进一步有界source blocker，可进行根agent的独立fixtures和回归。** 该结论不代表全局native原因管道双语完成，也不代表运行测试、端到端iOS小组件或其他页面迁移通过。

### 最终审读生产 SHA-256

| 文件 | SHA-256 |
| --- | --- |
| lib/main.dart | 67294f6fc38c93c60361466d07e4d986de3c7f43e1c81bc19bb21185593257d6 |
| lib/services/reminder_scheduler.dart | f98c9912de30ef6f46f759260fbd24c0e5bcf545af85a97f0125c44e64e3b5b7 |
| lib/services/widget_action_message.dart | 29e0b9d8c72c58217c3f0f5f16117e3d6169a7b1824ee4302f90f8ce733b5924 |
| lib/services/todo_reminder_preflight_copy.dart | 2932139dc20aeed180dfc517a1a988b23c6941e3a6d7729802ecefb66f956456 |
| lib/services/widget_action_scope.dart（未变） | caaf1b0f6d4d2c3e0a369b38cddced1c29bf2fa78d53f657a6abbb2d4d446ead |
| lib/services/widget_quick_todo_action.dart（未变） | b5d99d781800c8cb0d596b23a50ce752c69d0d7c8bd8bd89e19ca157a8e0c2fa |
| lib/providers/notification_service.dart（未变） | 69b8411b0eb0bff0289f8bbbbdac44b01f1c451f5545f480dcab79d9bfc3c27c |
| lib/providers/todo_provider.dart（未变） | 933e150ff316a45a498726f1d2f3596ad9ea99253636c0455757a88e887ef1b1 |
