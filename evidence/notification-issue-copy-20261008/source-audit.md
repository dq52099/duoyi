# Notification issue typed copy 契约审计 — 2026-10-08

## 当前结论

本轮 quick decision：`ensureReadyForReminder` 改为 `String? issueTitle`、缺省为 null，然后在方法内解析为原始 `'提醒注册失败'`，适合当前仓库且不需要新增平行 typed wrapper。所有已读取的实际调用均直接使用 named String 参数；没有方法 tearoff、override 或 static guard 要求原非空默认签名。此结论只来自源码，不是运行/编译验证。

生产源码审查与 owned warning/unconfirmed display title 修正后的最终复审均已完成，未发现本轮范围内未解决的源码 blocker。初读和第一轮结论保留为审计过程记录；最终八个生产 hashes 见报告末尾。本报告不把源码审查称为编译、runtime 或 frozen verification 通过。

基线 HEAD：`b7c37c3dc45a3dba4db353de7e5d4a8a545e5ec7`，初读工作树 clean。只读源码/现有契约守卫，未改生产、fixtures、docs；未运行测试、analysis、build、网络或其他验证命令。仅写入本私有报告。

## public issueTitle 的兼容方案

建议参数为 nullable String issueTitle 和 optional explicit titleCode；内部规则：

1. omitted/null 解析为 **exact legacy raw default** `'提醒注册失败'`，同时可以携带通用 app-owned title code。
2. 显式空串、空白和任何非空 String 原样保存。即使值恰好等于旧默认中文，也不能靠字符串相等推断 ownership。
3. 显式 titleCode 是调用者声明 app-owned title 的唯一额外信号；未给 code 的自定义 label 在 render 时保持 literal。
4. main 的外层 `issueTitle == null` 能明确辨别自有 default task label；可以在仍传原 call-time title 表达式的同时仅为该默认分支传 task titleCode。自定义 issueTitle 分支不传 titleCode，避免翻译用户/调用方标签。
5. legacy raw title 继续参与既有 signature，translation 不写回 title，不改变默认/显式 label 的 diagnostic 身份。nullable widening 不要求所有现有 String callers 改写。

新增 typed wrapper 无法免除内部 ownership 处理，而且会留下两套 public 入口。本仓库已有 direct named callers，nullable sentinel 的收益明确。若外部契约必须严格维持 nonnullable method type，可保留旧入口转交内部 common实现，但当前源码未见这种依赖。

## 实际 callers 与已查契约

12 个生产调用：main widget helper、todo_detail、quick_capture_fab、AI schedule 两处、habit list/detail各一处、countdown两处、anniversary两处、notification_history每日slot保存一处。它们当前都传String issueTitle；新signature保持这些输入有效，也保留显式自定义label的raw记录。

现有 `notification_service_test.dart` 用 `Future<bool> ensureReadyForReminder` 定位方法，检查调用 `_ensureChannelReadyOrRecord`、channel unknown 为 nonblocking/continue 等流程；未见对 `String issueTitle = '提醒注册失败'` 的精确签名断言。scheduler integration/popup fake 实现的是旧 `ReminderScheduleIssueSink`，所以 optional capability 应另建接口，不能向旧abstract method追加named参数。

现有 integration runtime契约会检查 raw中文title，例如待办/习惯/纪念日/倒数日注册失败；这些canonical字段仍必须保留，不能通过改变这些expect来容纳identity变化。

## NotificationService 完整 producer 范围

当前 `_recordScheduleIssue` 除方法声明外有28个调用：26处拥有literal外层文案，2处为公共raw record入口和alarm diagnostic bridge的透传。实现审查应核对26个owned site都有明确copy，两个raw透传保留未推断行为。

| owned 原因组 | 原control-flow事实必须保留 |
| --- | --- |
| init异常 | 记录blocking默认true，随后仍loadHistory |
| channel未知/blocked/silent/probe异常 | blocking=false，返回true继续注册；未知异常detail保留 |
| once past-time/permission未授权/提交后permission未确认/异常 | 返回false，blocking默认true，原scheduleTime和relatedId保留 |
| daily permission未授权/提交后permission未确认/异常 | 返回false，blocking默认true；重复文案与once区分 |
| alarm push fallback降级 | 保留现有默认blocking，不重新按code决定severity；嵌入的原issueTitle不解析 |
| immediate/show发送异常与权限 | immediate失败blocking=false；show的原默认blocking保持 |
| snooze旧提醒取消异常 | blocking=false，继续重新调度 |
| sendTest已提交但权限关闭/permission异常/发送异常 | 分别保留原blocking与return false；channel warning不被误清理 |
| scheduled popup diagnostic缺sink/exception | inAppOnly与fallback变体分别保存，返回false |
| scheduled alarm diagnostic缺sink/exception | 缺sink返回false；具体AlarmService issue桥接仍raw |

所有app-owned私有helper title String值仍为legacy raw，optional titleCode需要从每个内部literal调用入口一路传到最终copy构造；只在顶层方法赋code不够。异常Object不做contains/regex分类，copy只翻明确code对应的owned外层，detail作为literal参数保存。

## 状态、去重、历史与接口不变量

- NotificationScheduleIssue增加optional immutable copy，原title/message/happenedAt/scheduledTime/relatedId/blocking全保留。
- `_recordScheduleIssue`原signature仍只由raw title/message/scheduledTime/normalizedRelatedId/blocking组成；copy不入signature，renderer不调用record。
- duplicate和normal两个NotificationScheduleIssue构造分支都复制copy。duplicate仍更新时间、替换last对象并return，不新增notify。
- `_lastScheduleIssueIsPermissionOnly`仍读取canonical raw；requestPermission/refreshPermission的清理流程不改。不能把翻译文本反写导致权限问题不再清除。
- NotificationScheduleIssue不进入`duoyi_notif_history`。NotificationItem schema、scheduled history去重、read状态、pendingCount和batch notify/save规则不改。
- 新 `ReminderScheduleIssueCopySink` 是可选capability；旧ReminderScheduleIssueSink方法签名逐字保留。typed sink和raw sink只能选择一个record路径，不能先typed再raw重复记录。
- preflight metadata通过明确TodoReminderPreflightNotice/copy转换，scheduler并不从title/message恢复类型。full scheduler String aggregate仍属于后续工作。
- NotificationScheduleUnavailableException的optional copy保留既有raw字段、const constructor输入兼容和toString字节；_throwLastScheduleIssue只传捕获的copy，不猜未知异常原因。
- AlarmService未typed producer前，alarm bridge不附伪code，effectiveBlocking和dispatch结果不改。

## formatter / WidgetActionMessage 接线

WidgetActionMessage已在render入口一次解析effectiveLocale。新的issueCopy和已有preflightCopy都显式接收同一个locale；capturing只存descriptor，不提前render、不重新查询provider/native issue。自定义label/raw title/detail仍以原final字段保存。

NotificationUiCopy应优先检查明确typed copy，使用本次显式locale渲染title/message，不走formatIssueText的旧substring heuristic。无copy的旧raw fallback保持原契约；不能把“typed bypass heuristic”误说成所有旧raw/UI原因已经无损双语。显式locale renderer不得临时修改I18n.current。

如果一个descriptor同时带preflightCopy和issueCopy，需要明确优先级/互斥契约，当前main只给各自产生路径对应的copy；不能让无关copy覆写native raw detail。

## acceptance cases（本报告未执行）

1. omitted/null title → exact原raw default + owned通用title；显式原默认字面量/空串/空白/custom → 原raw title不变且不猜title ownership。
2. known code显式zh/en renderer，canonical中文raw字段与producer原literal逐字一致；exception detail含中文/引号/诊断后缀保留literal。
3. channel各warning仍blocking=false/ready=true；permission/past-time/调度异常仍false与原severity；sendTest/snooze各异步路径维持原结果。
4. duplicate30秒窗口、normal/duplicate copy保留、timestamp、notify次数、history/read/pendingCount与迁移前一致；locale render不创建新diagnostic/history。
5. typed formatter bypass heuristic；raw constructor/raw sink/alarm bridge没有copy时维持旧fallback。显式locale不影响global；排帧后语言变化时使用交付locale，账号变化仍抑制旧消息。
6. old sink fake编译/原runtime契约不要求新增接口；typed capability只record一次，preflight canonical字段与severity/time原值保持。
7. _throwLastScheduleIssue保留optional copy及legacy title/message/toString；不存在copy时raw异常保持raw。
8. 所有26个owned记录site及所有内部literal title入口有typed metadata；不得只覆盖widget preflight常见permission分支然后称整服务已完成。

## 实际生产源码审查结论

在 root 的 production-ready handoff 后，对八个生产文件及其相对基线 HEAD 的实际 diff 完成只读审查。发现并报告了一个遗漏：`sendTest` 的早期 `_ensureChannelReadyOrRecord(issueTitle: '普通通知测试异常')` 没有传 title code，导致 channel warning 的英文 message 搭配 literal 中文 title。root 已补 `NotificationIssueTitle.testWarning`，本轮复读在 `notification_service.dart:1702–1705` 确认修复。修复后未发现本轮范围内尚未解决的源码 blocker。

本轮只读生产源码、git diff 和既有 baseline；未读取正在编写的 fixture 内容，未运行 tests、Flutter analyzer、build、network 或干预其他进程。只有本私有报告发生写入。以下判断是源码证据，不是 frozen verification、编译或 runtime 证明。

### Descriptor 与 owned recorder 覆盖

实际新增类型为 final immutable `ReminderIssueCopy`，包含两个 const 构造：notification 和 preflight。notification 使用明确的 `NotificationIssueTitle`（17 个 code）与 `NotificationIssueNotice`（25 个 code）；preflight 直接持有既有 immutable `TodoReminderPreflightCopy`，不从 raw title/message 反推类别。所有实例字段均为 final；生产路径没有使用 `contains`、regex 或异常文本来选择 notice/title。

最终 `_recordScheduleIssue` 有 29 个调用（不含声明）：26 个 owned producers、两个既有 raw forwarding paths，以及新增 typed sink forwarding path。逐组核对如下；行号为本轮最终读取源码。

| owned producer | site 数 | 最终源码位置 | 保留的行为 |
| --- | ---: | --- | --- |
| init failure | 1 | 195 | 默认 blocking，随后 loadHistory |
| channel unknown/blocked/silent/probe exception | 4 | 628、642、656、674 | `blocking:false`，继续返回 true |
| once time/permission unconfirmed/denied/exception | 4 | 704、740、757、771 | 原 scheduledTime/relatedId，返回 false |
| daily permission unconfirmed/denied/exception | 3 | 822、838、851 | 原 relatedId，返回 false |
| alarm push fallback | 1 | 915 | 原默认 blocking；raw 嵌入标签不改 |
| immediate send failure | 1 | 950 | `blocking:false`，原异步 catch 路径 |
| public readiness time/permission | 2 | 992、1006 | 原 severity/time/id 与 false 返回 |
| show permission/exception | 2 | 1052、1064 | 原默认 blocking 和 return |
| snooze cancel exception | 1 | 1105 | `blocking:false`，仍继续重新调度 |
| sendTest unconfirmed/denied/exception | 3 | 1720、1734、1746 | 原 warning/error 差别及 false 返回 |
| popup missing sink/exception | 2 | 1951、1988 | inAppOnly 与 fallback code 分开，原 false 返回 |
| alarm missing sink/generic exception | 2 | 2016、2056 | 原 false 返回；existing AlarmService issue 优先 raw bridge |

四个私有 helper 仍要求原始 `String issueTitle`，仅新增可选 `NotificationIssueTitle? issueTitleCode`。所有 internal literal 调用（snooze、普通 once/repeat、AI、task、habit、anniversary、sendTest、scheduled push test、各 alarm fallback）均已携带相符的 code；once/daily/public readiness 转入 channel helper 时继续传 code。最后补齐的 sendTest helper call 也包含 code。

### Raw fields、模板与 ownership

- 对照 baseline 的 26 处 owned raw title/message：固定中文和标点保持原值。十个异常 suffix producer 在原 pre-record 位置保存一次 `final issueDetail = e.toString()`；旧 `($e)` 改为 `($issueDetail)`，同一 string 同时交给 raw message 与 copy.detail。原 debugPrint 后、record 前的诊断 string 转换位置和次数保持；没有额外二次 conversion，也没有过滤、trim 或重新分类 detail。
- descriptor 的 zh title/base-message 与各 producer 的原中文逐项相符。异常 detail 以原括号紧接在 base message 后；alarm fallback 的嵌入 label 以独立 literal/code 参数渲染，zh code 值与原内部 label 相符。en templates 保留 registration continues、already registered but silent/hidden、unconfirmed versus not registered、once versus repeat、in-app-only versus fallback unavailable 等原因差别；未以 generic permission heuristic 覆盖 detail。
- `ensureReadyForReminder` 的 omitted/null title 解析为 exact legacy raw `'提醒注册失败'`，并声明通用 registration title code。显式 `''`、空白、custom String 或显式旧默认中文均由 `??` 原样保存，且未给 code 时不声明 title ownership。显式 `issueTitleCode` 是调用者的 typed ownership 声明。
- main 保留原 `issueTitle ?? locale-dependent task label` 表达式；仅外层 `issueTitle == null` 分支声明 task title code。它把原 `issue.title/message/copy` 捕获到 WidgetActionMessage，不在 capture 时 render。旧 direct named String callers 仍适配 nullable widening；源码中没有发现 method tearoff/override 依赖，编译兼容性未执行验证。

### State、sink 与 exception

- `NotificationScheduleIssue` 原 fields/constructor defaults 保持，仅加 optional copy 和 presentation getters。record 的 raw signature 仍精确由 title/message/scheduledTime/normalizedRelatedId/blocking 组成，copy 不入 signature。
- duplicate 与 normal 两个构造都传 copy；duplicate 仍更新时间、替换 last issue、直接 return。没有新增 notify。permission-only 判定与 requestPermission/refreshPermission 清理逻辑保持 raw canonical 字段；render 不写回诊断。
- 没有改 NotificationItem JSON、history/unread、pendingCount、scheduled-history dedup、batch save/notify 或 dispatch timing。copy 不成为 history 内容。
- 旧 `ReminderScheduleIssueSink.recordReminderScheduleIssue` 的签名完整保留。新的独立 `ReminderScheduleIssueCopySink` 是 optional capability，不要求旧 fake/implementer 实现。scheduler 仅在 capability 存在且已有 explicit preflight copy 时走 typed record，随后 return；否则只走原 raw record。title/message/scheduledTime/relatedId/blocking 的值保持原值，不会双录。
- `NotificationScheduleUnavailableException` const 构造增加 optional copy；原 title/message/scheduledTime/relatedId 与 `toString() => '$title：$message'` 不变。`_throwLastScheduleIssue` 仅传捕获 issue 的 copy，不为 fallback/unknown 异常猜类型。
- 旧 public raw recorder 与 `_bridgeAlarmDiagnosticIssue` 均不构造 copy。alarm bridge 的 issue-id 检查、原 scheduledTime fallback、blocking 参数及 true/false 返回保持；本轮未 typed AlarmService producer，也未改变 scheduler 对其 raw Chinese reason 的 effectiveBlocking 判断。

### Locale 与 UI

`NotificationUiCopy.formatScheduleIssue` 优先识别 explicit copy，读取一次 `I18n.current` 并显式把同一 locale 传给 title/message getters；此分支直接返回 typed rendering，完全绕过原 `formatIssueText`。无 copy 的 null/zh/en fallback 和 substring heuristic 保持原契约。

`WidgetActionMessage.render` 仍只解析一次 effectiveLocale。issueCopy 的 title/message 均显式收到同一 locale；缺 issueCopy 时使用原 preflightCopy，缺两者时保留 literal subject/detail。若调用者同时提供两种 metadata，代码明确以 issueCopy 优先。main 的实际生产入口每次只给对应产生路径的 copy。所有 renderer 不修改 global locale、不访问 provider/native issue、不新增 record。

main 的两个 widget 反馈 helpers（`_showWidgetActionFeedback` / `_showWidgetActionFeedbackFromShell`）仍在既有 `WidgetActionScope.afterFrame` 的 origin/lifetime 检查之后，并在 mounted 检查之后执行 `message.render()`；新增 metadata 没有改变账号 guard 或反馈时间。

本轮结论仅覆盖新的 NotificationService typed owned producers 及其 metadata 接线。旧 raw fallback 仍保留原 heuristic，AlarmService 与 scheduler String aggregate 仍有未 typed 的 reason pipeline；不能据此宣称所有 legacy reason 已 lossless/bilingual。

### 第一轮审查 snapshot hashes

基线/读取时 HEAD：`b7c37c3dc45a3dba4db353de7e5d4a8a545e5ec7`。以下为 sendTest title propagation 修复后、尚未 frozen verification 的生产工作树 SHA-256；root 后续若修改或格式化，应以新 snapshot 重新对照。

| 文件 | SHA-256 |
| --- | --- |
| `lib/services/reminder_issue_copy.dart` | `b3e7db2b1ad6f1ba703cf79dfc9dd76502aa1968f075ac85fe5f1ac50892d819` |
| `lib/providers/notification_service.dart` | `ddce2a9333e303b8252fdfc5befc7526346288d0290f013ee1d60654fe44aa7d` |
| `lib/services/reminder_sinks.dart` | `729c490905da6b58005d758aa4833ab36f11e7c666edd5a8ae7ff853d6998c04` |
| `lib/services/notification_permission_exception.dart` | `e5129cf032a2dde4053de66fcfc19c3d5b8a00b9b1774af293332898db4a5abb` |
| `lib/services/reminder_scheduler.dart` | `68cb6bfcf1fcb095bf249daed0621bf21c66fb4045b10d5e0d3291ff535b21bc` |
| `lib/services/widget_action_message.dart` | `b9ca90b536a6189291d7b5fcdc3f1e5af4dc777e7db5a6a0b3e9d49835fcd098` |
| `lib/main.dart` | `8379c27f6b52abb5b54c7962c0ec746106ff7ac3dbd9836bc6e65e370d981889` |
| `lib/core/notification_ui_copy.dart` | `6e4dd4e6d9e42610ba08439137de8b6789e0c87aebaedc718f2d5b98218069b4` |

## 后续 owned display title 语义修正与最终复审

root 在第一轮后发现：task/registration 等 code 的英文 title 为 not registered，但 notice 为 channel warning（continue/already registered）或 permission unconfirmed 时，这个外层 display title 与实际 reason 不一致。raw canonical title 仍必须保持旧值；typed display title 应只针对六个 explicit notice（channelUnknown/channelBlocked/channelSilent/channelProbeFailed/oncePermissionUnconfirmed/repeatPermissionUnconfirmed）选择 neutral owned title。

本 agent 同意此修正，并补充 scheduledTestFailed 也要有 neutral mapping，因为 scheduled push test 会通过 once/channel helper 留下同类 warning。titleCode-null 的自定义 fallback 必须仍原样显示。其他 concrete failure notice、severity、raw dedup identity 与 registration decision 均保持。

因此第一轮“zh title 与 raw title 相符”只描述第一轮实现，不是这些 warning/unconfirmed 的最终 acceptance 条件；有明确 title code 时采用 intentional localized display difference 是正确行为。

最终复读确认：`ReminderIssueCopy.renderTitle` 仅对上述六个 explicit notice 启用 `renderCheckTitle`，且要求已有 explicit titleCode。preflight title 优先级保持；titleCode-null 的 fallback（包含空串、空白与显式旧默认字面量）原样返回。timePassed、permissionDenied、scheduleFailed 等 concrete failure notice 继续原 title mapping。这个判断只读取 code，不读取 raw message、blocking、locale history，也不修改任何调度 state。

`NotificationIssueTitle.renderCheckTitle` 明确映射八个可能使用 failure label 的 owned title codes：generic、repeating、task、habit、anniversary、AI、snooze 和 scheduled notification test。task 的 display title 现在是 `待办提醒状态需检查` / `Check task reminder`；scheduled test 是 `定时通知测试状态需检查` / `Check scheduled notification test`。其他 code 默认继续 `render(locale: locale)`，原 testWarning 已有 neutral title。

这些 warning/unconfirmed 的 raw title 仍为 canonical legacy failure label；新 zh/en display title 是有意的 presentation 差异，必须允许显示与 raw 身份不同。copy 的 message/detail、raw title/message、blocking、signature、duplicate/state/permission-clear/history 与所有 return values 均未被这次 title 修正改变。core formatter 与 WidgetActionMessage 继续给 title/message 显式传同一次捕获的 locale，不新增读取或改写 global locale。

root 通知 production formatting 完成且零改动后，收集了下面八个 SHA-256。除 descriptor 外，七个文件 hashes 与第一轮完全一致；descriptor 最终内容已复读，其余模板和 detail 逻辑保持。自 root 新增 no-git 限制后未再调用 git；整个任务没有运行 tests、analyzer、build、network 或干预其他进程。

### 最终格式化后 production snapshot hashes

| 文件 | SHA-256 |
| --- | --- |
| `lib/services/reminder_issue_copy.dart` | `e61c4d9e30d2d6021c34ee6962e4e5cba90129ce4f96e020d96701d76dfd5547` |
| `lib/providers/notification_service.dart` | `ddce2a9333e303b8252fdfc5befc7526346288d0290f013ee1d60654fe44aa7d` |
| `lib/services/reminder_sinks.dart` | `729c490905da6b58005d758aa4833ab36f11e7c666edd5a8ae7ff853d6998c04` |
| `lib/services/notification_permission_exception.dart` | `e5129cf032a2dde4053de66fcfc19c3d5b8a00b9b1774af293332898db4a5abb` |
| `lib/services/reminder_scheduler.dart` | `68cb6bfcf1fcb095bf249daed0621bf21c66fb4045b10d5e0d3291ff535b21bc` |
| `lib/services/widget_action_message.dart` | `b9ca90b536a6189291d7b5fcdc3f1e5af4dc777e7db5a6a0b3e9d49835fcd098` |
| `lib/main.dart` | `8379c27f6b52abb5b54c7962c0ec746106ff7ac3dbd9836bc6e65e370d981889` |
| `lib/core/notification_ui_copy.dart` | `6e4dd4e6d9e42610ba08439137de8b6789e0c87aebaedc718f2d5b98218069b4` |
