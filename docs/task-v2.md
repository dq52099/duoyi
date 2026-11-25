# 多仪 v2 升级任务清单

> 2026-11-22 当前：完成 `3863` 控制闭合（[closure-3863](../evidence/theme-widget-resume-20261116-v1000/main-current-control-source-3863/closure-3863.json)）、14 项 staged 交付、5 项规格缺口补齐及 Web UI / 桌面工作台重构（`v1.1.46+140012` / `4a317163eb5a`，`984/984` `ROOT == R` 同步）。后端 `156/156`、Kotlin `252/256`（仅 4 项 `Os.lstat` JVM 桩）、Robolectric Goal `72/72` / Focus `2/2` / Note `3630-run-03` `4/4`、Flutter 5 套视觉 `28/28`（`280` PNG + `8` 对比 JSON 最低 `8.939:1`）通过；重构前 `test/**/*_test.dart` `817/817` 全量闭合，重构后完整分析零问题（[analyze-6](../evidence/antigravity-inherit-20261121/desktop-web-refactor-analyze-6.log)）、受影响回归（`+124`/`+38`/`+53`）、`alignment-gate-final-pass` `1/8` 及新 Debug APK（`223,981,588` B，SHA-256 `d4cab1ac95e8429910fb1f88a82ac14c923f176bd96d846ed4ade06be9c41483`，v2 签名/3 ABI/31 Provider/223 小组件资源）通过，保留 `app-debug-2811.apk` 与 `prior-apk-preserved-1029.apk`。当前 `819` 份最新字节全量 `T-50`、`T-32/T-33/T-34`、`Group 8/8`、真机设备（[device-readiness](../evidence/antigravity-inherit-20261121/device-readiness/summary.tsv) `10/11` 缺失）与第 27 项发布门禁继续开放；详单见[当前总结](../evidence/antigravity-inherit-20261121/summary.md)。

> 2026-11-18 当前：Habit 快照已保留未操作习惯的原更新时间；87项相关回归通过，后续六处测试 lint 修改另有兼容审阅。完整项目分析2806零问题；最终 debug APK2811的构建、签名及31个 Provider 资源映射已接受。当前815份测试文件（814份host、1份设备integration）清单已核对，完整回归尚未执行；T-32/T-33/T-34/T-50、真实设备及性能继续开放。历史勾选只记录当期实施状态。最新范围与证据见[主会话记录](../evidence/theme-widget-resume-20261116-v1000/summary.md)。

> 2026-11-07 当前续接（v894）：日历本地事件、番茄钟房间/任务与日记AI结果弹窗使用实时主题路由；14项新入口回归通过，原生/路由契约88项与Swift提取逻辑58组通过，通知确认框可读字体重取证1项通过。Android生产重试已接共享coordinator，iOS14计时字形兼容保护已补；Android编译尝试因25GiB预算由守卫停止，尚未通过，未生成新APK。现有交互、分析和当前全量待实际终态；T32/T33/T34/T50、全路由/真实设备/通知/性能门禁继续开放。见[本批范围及证据](../evidence/theme-widget-resume-20261106-v894/summary.md)。

> 2026-10-26 当前续接（v867/v868）：两批均有六路实际AGY并发，结果全部收回。修复AI历史清空确认框在打开后切换默认iOS/毛玻璃主题时保留旧样式；完整原版8败/候选8过，10文件327项不同相关检查通过、整项目分析零问题、1771输入未变，8张最终图已查看。新增连续资源守卫通过20项Python生命周期与9项脚本契约，wrapper/alignment实际exit7传播已验证；当前约13.5GiB不足25GiB，build预检拒绝且未打包。产品/测试已变化，T-50对当前快照重新开放；v858仅保留历史快照验收。原生/通知/设备性能、全路由与完整MD门禁仍开放。见[本轮证据](../evidence/ai-history-live-clear-20261026-v867/summary.md)。

> 2026-10-26 当前本机验收（v858）：733份测试文件/62组覆盖齐全，9461过、8项条件跳过、零失败；九项指定时区/工作日补测均实际通过，v857逐项身份审计确认9469项不同检查通过、零未解决跳过。33组5653项按v845两文件差异审计明确兼容继承，其余29组重新执行，不冒称全部在新快照重跑。补测运行器误删必要开关已修复，保留原拒绝记录。随后仅流程脚本和任务/预算文档更新，产品与测试字节不变；T-50仅对该应用/测试快照关闭，T32/T33/T34、原生/通知/性能、完整MD门禁和新APK仍开放。见[当前验收](../evidence/priority-content-20261025/ios-help-current-v860.md)。

> 2026-10-25 小组件续接（v783）：修复失效帮助弹窗“知道了”不能关闭的问题，保留设置动作的原权限检查及覆盖页面保护；旧版概览资源增加选择器隐藏提示并保留旧实例刷新，纠正文档注册描述。原产品6项1过5败，候选6项及8文件123项完整相关检查通过，完整分析v780零问题，1769输入一致；Android36资源链接确认隐藏位2（引用资源为探针桩，非应用/设备验收）。v764因磁盘预算停止，40组5733部分通过不算全量；补测0项。T50、T32/T33/T34及原生/通知/性能/完整目标仍开放，未打包。见[当前证据](../evidence/priority-content-20261025/local-priority-current-v783.md)。

> 2026-10-25 当前续接（v661）：目标“下一次派发日”窄屏/大字号溢出及两主题低对比已修复；农历可见性测试改为实际揭示段落后测量，纪念日产品代码未改。主目录8文件118项回归与完整分析通过，1090输入未变；24场景96条文字最低对比13.71:1，12张图已查看。v633旧全套4551过/5条件跳过/1失败，v634补测0，均非通过；旧部分计数不复用。新全套v662准备覆盖732文件，v663补9项条件用例，v664按实际身份审计后才可由v665打包。最新接受APK仍v513，原生/设备/通知/性能和T32/T33/T34/T50继续开放。以[当前记录](../evidence/priority-content-20261025/local-priority-current-v661.md)及其终态文件为准。

> 2026-10-25 待办源码契约续接：v622终态637项部分通过、2项旧断言失败、1767输入未变，不能视为全套通过；v623补测0项，v625阻止打包。先核完全部144份源码契约，剩余72份加2份失败文件的v627检查为548过2败，无第三项问题。两份测试修正筛选标题调用空白匹配及位置提醒的旧固定阈值/返回语句，改为检查当前文字测宽、横竖排回退、滚动及账号守卫；产品代码未改。受影响原版11项9过2败，候选11项及主目录8文件73项回归通过（重叠不重复计数），v632完整分析零问题、1089输入不变。新全套v633仍731文件/62串行组，先144份源码契约，再单独长用例和全部页面；v634门控补9项条件用例，v635仅在完整通过后打包。T32/T33/T34/T50和原生设备验收继续开放。见[当前证据](../evidence/priority-content-20261025/todo-contract-current-v637.md)。

> 2026-10-25 静态卡片契约修正：v611因纪念日标签构造调用改为多行，触发旧单行源码断言失败后主动停止；终态2607过/5条件跳过仅统计21个完成组，另有当前组1项已知失败，不能视为全套通过。1767输入停止时未变，v612补测0项、v614未启动打包。仅修正一份测试对空白/可选尾逗号的匹配，保留原有样式与标签/日期顺序断言；原版4项3过1败，候选4项及9文件146项回归通过，v621完整分析零问题、1089输入未变，产品代码未改。新全套v622仍覆盖731文件/62串行组，优先144份源码契约；v623再执行9项条件补测，v624打包仍由完整终态门控。全部旧部分计数不复用，T32/T33/T34/T50与原生设备验收仍开放。见[当前证据](../evidence/priority-content-20261025/date-card-format-current-v626.md)。

> 2026-10-25 全套验证清单修正：v602在10组2395项通过、1项条件跳过、0项测试失败后，因运行中的后端数据库与定时备份变化被输入保护中止；不是完整通过。v603补测0项，v609门控拒绝且未启动APK。已核实其余1767份源码/配置输入全部未变；后续清单精确排除backend/backups、backend/uploads及两份运行数据库/SQLite侧文件，保留全部源码和构建输入保护，不停止服务、不删除数据。新全套v611仍覆盖731文件，每进程至多12文件串行，v612仅在完整通过后补测9项时区/工作日；打包v613继续门控并保留旧APK。T32/T33/T34/T50与原生设备验收仍开放。见[当前本机验证](../evidence/priority-content-20261025/local-verification-current-v615.md)。

> 2026-10-25 自习室账号边界续接：修复旧账号异步响应写回好友/邀请/排行、持久化回调及新账号诊断/加载状态；补齐默认 iOS / 毛玻璃主题页面中旧错误提示、管理面板误开及创建邀请码对话框误关闭的账号检查。有效 Provider 基线42项中20过22败，实际挂载页面基线152项中104过48败（所有正常账号正控通过）；修复后主目录10文件275项不同相关检查通过，新增测试规范修正后194项复核通过（重叠不重复计数），v605完整分析零问题，1089输入未变。v575因验证此新缺陷主动停止，561项部分通过不算完整回归；v576未执行补测。全套改用v602覆盖731文件，并由v603门控执行9项时区/工作日补测，以实际终态为准。最新APK尚未包含本次与纪念日页面改动，T32/T33/T34/T50、原生小组件/通知/设备性能及完整目标仍开放。见[当前账号边界证据](../evidence/priority-content-20261025/focus-account-current-v606.md)。

> 2026-10-25 生日/纪念日与个人资料续接：修复默认 iOS / 毛玻璃主题的长文截断、统计/徽标/天数低对比及窄屏重排。主目录相关165项与个人资料35项共200项不同检查通过；48场景1248条文字测量均完整，最低对比11.40:1；16张最终截图已查看。v574完整分析零问题，1087输入未变。旧全套v540终态不通过（原日志4383过/5条件跳过/2资料夹具失败）；资料夹具已验证修正。全套v575随后因验证新发现的账号竞态主动停止（561项部分通过、2333输入未变，不算完整回归），v576未执行补测；该链已终止。T50、原生小组件/通知/设备性能及完整目标仍开放；旧APK保留，新页面尚未重新打包。见[当前证据](../evidence/priority-content-20261025/anniversary-profile-current-v577.md)。

> 2026-10-25 通知主题续接：主目录7文件255项相关检查、历史静态失败相关75项和完整分析v512通过，1086验证输入未变化。修复通知三页毛玻璃背景及提醒注册页连续滚动、英文完整标题和状态说明对比；56组168条文字测量最低5.73:1。96张主目录截图与已审候选一致，70个不同画面已查看、26张精确复用；1078份main/runtime Dart一致、1521份未分配输入保留。v513 APK本地打包与签名检查已通过。原全套v515发现1条过时的后台标签宽度源码断言后主动中断，2332输入未变；该轮不算通过。后台断言修正后21项和v524分析通过；随后全套v525发现小组件单行计量与日记懒加载夹具共12项失败并主动中断，2332输入未变，该轮及其未运行补测均不算通过。两份夹具修正经原版3类复现、候选12项及主目录262项回归验证通过（零跳过/失败），当前完整分析v533零问题，1086输入未变；产品代码与786个APK构建输入未改。全套v534在4830项通过、5项条件跳过、0项测试失败时于下一文件加载阶段停滞，确认无编译/测试子进程及CPU进展后主动中断（2332输入未变，非通过终态）；v535执行0项补测。同一文件在独立默认进程v539中252项通过，2332输入未变。为避免长驻进程再次卡住，新的v540/v541采用全量文件清单分批串行及门控补测，728文件必须各运行一次，不复用旧部分通过计数；T50、Launcher/WidgetKit/真机通知/性能及完整目标继续开放。详见[本批证据](../evidence/priority-content-20261025/summary.md)。

> 2026-10-25 当前批：同步冲突实时状态主目录173项、黄历相关64项及完整分析通过（1086输入不变）。黄历月格历史24项失败已在本次范围修复，3744条测量与已审候选完全一致，最低文字对比7.25:1；104个不同画面已查看，16张精确复用。1078份main/runtime Dart一致，1446份未分配文件保留。本次v501 APK打包、签名、3 ABI及31 WidgetProvider检查通过，786构建输入不变；全量回归由v503单独记录；T50与原生/真机/通知/性能/完整目标继续开放。使用现有运行目录、串行验证与12/20 GiB磁盘门槛。详情见[本批证据](../evidence/priority-content-20261025/summary.md)。

> 2026-10-24 当前内容批（v487）：HOST修复我的页云同步状态卡的长说明/重试提示省略及低对比，待同步标签独立排列，图标随标题顶部对齐。有效原版40项中7过33败，候选40项通过；主目录7文件141项不同相关检查及完整分析通过，1085个分析输入不变，1077份main/runtime Dart一致，1075份未分配Dart保留。200张最终图与已审候选一致，80个不同画面已审、120张精确复用，最低实测文字对比13.25:1。v486本地debug APK通过v2签名、3 ABI、31 WidgetProvider及786个不变构建输入检查，见sync-status-final-postguard-v487.json。同步Provider/控制器不变；未增加手动同步或备份功能。T49仅本快照关闭；T50、黄历24项、待单独确认的旧超时、原生小组件/通知/设备/性能及完整目标仍开放。未安装、发布或部署；新增代理0，独立核查六路并行。

> 2026-10-24 当前内容批（v473）：HOST修复日历无时间卡片，采用共享iOS/毛玻璃表面，长备注自然换行；状态标签独立一行避免挤断英文标题，保留完成划线及逾期/冲突底纹和图标。有效原版24项失败、候选24项通过；主目录12文件185项相关检查及完整分析通过，1084个分析输入不变，1076份main/runtime Dart一致，1074份未分配Dart保留。时间线定位、紧凑内容和拖动源码逐字节不变。72张最终图与已审候选一致，50个不同画面已审、22张精确复用，最低实测对比4.83:1。v472本地debug APK通过v2签名、3 ABI、31 WidgetProvider及786个不变构建输入检查，见calendar-untimed-final-postguard-v473.json。T49仅本快照关闭；T50、黄历24项、待单独确认的旧超时、原生小组件/通知/设备/性能及完整目标仍开放。未安装、发布或部署；新增代理0，独立核查六路并行。

> 2026-10-24 当前内容批（v463）：HOST修复日历农历头与节气/节日文字低对比度，保留彩色底纹、图标、字号及自然换行，最低实测对比由1.99:1提升至12.01:1。有效原版40项中6过34败，候选40项通过；主目录10文件117项相关回归及完整分析通过，1083个分析输入不变，1075份main/runtime Dart一致，1073份未分配Dart保留，农历头和标签之外源码逐字节不变。120张最终图与候选一致，80个不同画面的头部已审、40张精确复用。v462本地debug APK通过v2签名、3 ABI、31 WidgetProvider及786个不变构建输入检查，见calendar-lunar-final-postguard-v463.json。T49仅本快照关闭；T50、黄历24项、待单独确认的旧超时、原生小组件/通知/设备/性能及完整目标仍开放。未安装、发布或部署；新增代理0，独立核查六路并行。

> 2026-10-24 当前内容批（v452）：HOST修复日历纪念/课程摘要，采用共享iOS/毛玻璃表面和主题文字色；纪念按所选日期显示和计算次数，非今天标题改用“当日”及对应英文。原版20项失败、候选20项通过；实际主目录9文件77项相关回归和完整分析通过，1082个分析输入不变，1074份main/runtime Dart一致、1071份未分配Dart保留，日记入口字节不变。96张主目录摘要图与已审候选一致（28张不同画面已查看、68张精确复用），最低对比度13.31:1。v451本地debug APK通过v2签名、3 ABI、31 WidgetProvider及786个不变构建输入检查，见calendar-summary-final-postguard-v452.json。T49仅本快照关闭；T50、黄历24项、待单独确认的旧超时、原生小组件/通知/设备/性能及完整目标仍开放。未安装、发布或部署；新增子代理0，独立命令六路并行。

> 2026-10-24 当前内容批（v439）：HOST修复日历日记入口，统一共享iOS/毛玻璃表面与按钮语义，提示和长标题自然换行；最低对比度由3.85:1提升至13.36:1，最小触摸高度由42.9px提升至48px。有效原版24项失败、候选24项通过；实际主目录9文件94项相关回归通过，测试弃用API等价迁移后24项复测与完整分析通过（复测不重复计数），1081个分析输入不变、1073份main/runtime Dart一致、1071份未分配Dart保留。48张主目录入口图与已审候选逐字节一致，真实主题/语言切换保留页面，底缘点击进入当天编辑页且返回不写入日记。v438本地debug APK已通过v2签名、3 ABI、31 WidgetProvider及786个不变构建输入检查，见calendar-diary-final-postguard-v439.json。T49仅当前快照关闭；T50、黄历24项、各自待确认的旧超时、原生小组件/通知/设备/性能及完整目标仍开放。未安装、发布或部署；新增子代理0。

> 2026-10-24 当前内容批（v425）：HOST修复隐藏小组件入口返回栏，提示对比度由约3.73–3.82:1提升至至少13.53:1，按钮真实高度由40px提升至44–48px。真实字体原版12项失败、候选12项通过；主目录6文件88项相关检查及完整分析通过，1080分析输入不变，1072份main/runtime Dart一致，1069份未分配Dart保留。真实语言设置/主题切换保留页面，按钮底缘点击返回我的；24张最终图与已审候选逐字节一致。v423本地debug APK的v2签名、3 ABI、31 WidgetProvider和786个不变构建输入检查通过，见hidden-return-final-postguard-v424.json。同时修正两个无障碍文字测量的粗体扫描误报，6项负向检查继续拦截实际界面粗体。T49仅当前快照关闭；T50、黄历24项、各自待确认的旧超时、Launcher/WidgetKit/通知/真实设备/性能及完整目标继续开放，未安装、发布或部署。新增子代理0，独立核查并行，Flutter/Dart/Gradle串行。

> 2026-10-24 历史阶段（v359）：三次均有实际六路并发记录，共19次AGY调用已全部终止：3份带错误警告的返回、15次明确额度错误、1次流中断，不能视为19路成功。全部Flash账号及最高版本Sonnet high链均不可按要求继续，已确认原writer停止并由HOST接手。小组件主题目标候选通过既有28项；未知ID恢复跟随候选原版4红/1正控、候选5及相关49项通过。新触摸/邮件标签夹具仍在隔离串行验证，包含修正字体行框误报与已复现的后台大字号面板溢出；无新候选合入主目录，v331仍仅适用原快照。完整目标继续开放。

> 共 52 项任务，按里程碑分组。每项标注文件、依赖、验收标准。

> 当前验收说明（2026-10-22）：以下实施勾选保留历史记录。当前完整 Flutter 回归未通过，不能以历史勾选推断整项目完成；[权威终态与后续局部验证](../evidence/full-test-priority-current-20261022/summary.md)记录原 6571 通过、8 跳过、32 失败，后续已修复过时静态断言；2026-10-25 黄历月格24项及相关64项通过，完整回归待重跑。T-50 恢复为未完成；真实通知、Launcher/WidgetKit、多人协作及性能验收仍各需证据。

---

## M0: P0 代码缺口修复

- [x] **T-01** Holiday Calendar 补充 2026 年中国法定节假日数据
  - 文件: `lib/services/holiday_calendar.dart`
  - 添加 2026 年元旦、春节、清明、劳动节、端午、中秋、国庆数据
  - 添加 2026 调休上班日数据
  - 验收: `HolidayCalendar.isHoliday(DateTime(2026, 1, 1)) == true`

- [x] **T-02** ReminderScheduler.syncTodos 直连替换 dynamic 兜底
  - 文件: `lib/providers/todo_provider.dart:530`
  - 将 dynamic 调用改为直接调用 `scheduler.syncTodos()`
  - 移除 `TODO(task-14)` 注释
  - 验收: postponeOverdue 后提醒重新调度

- [x] **T-03** ReminderScheduler.syncGoals 直连替换 dynamic 兜底
  - 文件: `lib/providers/goal_provider.dart:225`
  - 将 dynamic 调用改为直接调用 `scheduler.syncGoals()`
  - 移除 `TODO(task-14.1)` 注释
  - 验收: 目标变更后提醒重新调度

- [x] **T-04** Goal 编辑页集成 RecurrenceEngine.nextOccurrence
  - 文件: `lib/screens/goal_edit_screen.dart:528`
  - 依赖: T-01（节假日数据就绪）
  - 替换 `RecurrenceRule.nextAfter()` 为 `RecurrenceEngine.nextOccurrence()`
  - 验收: 带节假日跳过的目标显示正确下次派发日

- [x] **T-05** 纪念日提醒支持 alarm kind
  - 文件: `lib/providers/notification_service.dart:304`
  - 依赖: T-30（Anniversary 模型增加 reminderKind 字段）
  - 当 `kind=alarm` 时调用 `AlarmService.scheduleFullScreen`
  - 验收: 纪念日强提醒可全屏弹出

- [x] **T-06** 生产音频入口迁移，保留 AudioService 兼容 shim
  - 文件: `lib/services/audio_service.dart`、`lib/services/focus_sound_service.dart`
  - 历史勾选记录生产调用迁移；兼容类仍标记 deprecated，未删除。
  - 核对生产 import/调用与兼容转发边界；不以全源码 AudioService 零匹配作为验收，也不替代实际播放或完整门禁。

---

## M1: 日历枢纽强化

- [x] **T-07** 日历事件统一详情底部弹层
  - 新增/扩展 `CalendarEventActionSheet` widget
  - 显示: 标题、时间、来源模块标签
  - 操作: 完成/打卡/开始专注/改期/编辑/跳转详情/删除
  - 验收: 点击日历任意事件弹出统一操作面板

- [x] **T-08** CalendarActionRouter 跨模块操作分发
  - 新增 `CalendarActionRouter` 类
  - 依赖: T-07（操作面板就绪）
  - 完成操作写回 `TodoProvider`/`HabitProvider`/`GoalProvider`
  - 改期写回原模块
  - 验收: 在日历中完成待办后，待办列表同步更新

- [x] **T-09** 日历页按类型筛选
  - `CalendarScreen` 顶部增加类型筛选 chips
  - 支持多选/全选
  - 验收: 选中"习惯"后只显示习惯事件

- [x] **T-10** 日历冲突提示增强
  - `CalendarAggregator._markConflicts` 增加视觉标记
  - 详情面板显示冲突列表
  - 依赖: T-07（详情面板就绪）
  - 验收: 同时段课程+待办显示冲突标记

- [x] **T-11** 今日页与日历页共享排序规则
  - 抽取排序逻辑到 `CalendarAggregator`
  - `TodayScreen` 使用相同排序
  - 验收: 两个页面事件顺序一致

---

## M2: 多次提醒完善

- [x] **T-12** 稍后提醒 (Snooze) 功能
  - 通知 action 按钮: 5分钟后/10分钟后/30分钟后
  - 点击后重新调度一次性提醒
  - 验收: 点击"5分钟后"按钮，5分钟后再次收到通知

- [x] **T-13** 通知点击深链到具体详情
  - 确认所有通知 payload 格式统一为 `duoyi://type/id`
  - 验证 `TodayDetailRouter` 处理所有类型
  - 验收: 点击待办通知直接打开该待办详情页

- [x] **T-14** 单条提醒失败不中断整轮调度
  - `ReminderScheduler` dispatch 中已有 try-catch
  - 确认 `resyncAll` 中每个 sync 独立 try-catch
  - 输出 `ReminderHealthReport`
  - 验收: 模拟一条提醒注册失败，其余提醒正常下发

---

## M3: 通知健康检查完善

- [x] **T-15** MIUI/HyperOS 设备检测与清单
  - `PermissionHealthService` 增加 MIUI/HyperOS 品牌检测
  - 输出自启动、后台限制、锁屏通知的检查项
  - 验收: 小米设备显示专门配置清单

- [x] **T-16** 测试通知结果记录
  - 发送测试通知后记录时间和结果
  - 在通知健康页展示最近测试记录
  - 验收: 点击测试通知后列表新增一条记录

- [x] **T-17** 返回前台自动刷新权限
  - `WidgetsBindingObserver.didChangeAppLifecycleState` 中刷新权限
  - 权限变化后重新调度提醒
  - 验收: 从系统设置授权通知后返回应用，状态自动更新

---

## M4: 时间足迹集成

- [x] **T-18** 番茄完成自动生成 TimeEntry
  - `PomodoroProvider` 完成时发布 `DomainEvent`
  - `TimeAuditProvider` 订阅事件自动创建 `TimeEntry`
  - 验收: 完成25分钟番茄后时间足迹新增一条记录

- [x] **T-19** 待办完成时可选记录耗时
  - `TodoProvider.completeTodo` 后弹出可选耗时记录对话框
  - 依赖: T-18（TimeEntry 模型就绪）
  - 用户可跳过或输入耗时
  - 验收: 完成待办后弹出对话框，记录后时间足迹可见

- [x] **T-20** 统计页时间分布图表
  - `StatisticsScreen` 增加时间分布 section
  - 按模块/标签的饼图和趋势折线图
  - 使用 `fl_chart`
  - 依赖: T-18、T-19（有足够数据来源）
  - 验收: 统计页显示本周时间分布

- [x] **T-21** 日历页添加时间段入口
  - 日历详情面板增加"添加时间记录"操作
  - 依赖: T-07（详情面板就绪）、T-18（TimeEntry 模型就绪）
  - 验收: 从日历可直接创建时间记录

---

## M5: 共享协作 MVP

- [x] **T-22** 验证后端 workspace API 完整可用
  - 测试 `POST/GET /api/workspaces`, invites, members
  - 修复缺失字段或接口
  - 验收: curl 测试所有 workspace 接口返回正确

- [x] **T-23** 邀请码创建与加入流程
  - `ShareScreen` 增加创建邀请码 UI
  - 依赖: T-22（后端接口就绪）
  - 输入邀请码加入工作空间
  - 验收: A 创建邀请码，B 输入后加入空间

- [x] **T-24** 共享标识在列表展示
  - 待办/目标列表中共享项目显示共享图标
  - 依赖: T-22（workspace 数据可用）
  - 验收: 共享待办条目有明显的共享标记

- [x] **T-25** Viewer 权限限制
  - viewer 角色禁止编辑/删除/完成操作
  - 依赖: T-22（权限模型就绪）
  - UI 禁用相关按钮
  - 验收: viewer 无法编辑共享清单

---

## M6: 成就事件管线

- [x] **T-26** DomainEventBus 接入 AchievementEngine
  - `AchievementProvider` 订阅 `DomainEventBus.events`
  - 匹配成就规则触发解锁
  - 验收: 完成10个待办后自动解锁对应成就

- [x] **T-27** 解锁成就弹层反馈
  - 成就解锁时显示轻量 SnackBar 或 Overlay
  - 依赖: T-26（解锁逻辑就绪）
  - 不打断当前操作流
  - 验收: 解锁成就时底部显示提示

- [x] **T-28** 成就进度云同步
  - `achievement_states` 加入 `CloudSyncProvider` payload
  - 依赖: T-26（成就数据生成）
  - 验收: 登录新设备后成就进度恢复

---

## M7: 课程表/纪念日深化（倒数日恢复可见）

- [x] **T-29** 倒数日可见主流程恢复
  - 当前版本恢复倒数日新增、搜索、日历聚合、导出和深链入口
  - 旧倒数日数据继续兼容读取/编辑路径，避免历史数据丢失
  - 验收: 更多应用、搜索、日历、导出和深链均能处理倒数日

- [x] **T-30** 纪念日 ReminderConfig.kind 概念引入
  - `Anniversary` 模型增加 `reminderKind` 字段
  - `ReminderScheduler.syncAnniversaries` 支持 alarm 路由
  - 验收: 强提醒纪念日全屏弹出

- [x] **T-31** 课程事件从日历深链到课程详情
  - 日历课程事件点击跳转 `CourseScheduleScreen`
  - 依赖: T-07（日历详情面板就绪）
  - 验收: 点击日历中的课程可查看课程详情

---

## M8: 小组件增强

- [ ] **T-32** 小组件完成待办操作
  - Android widget 增加完成按钮
  - 通过 `MethodChannel`/`HomeWidget` 回调标记完成
  - 验收: 在桌面直接完成待办
  - 当前: 代码与宿主契约已有覆盖；Android Launcher / iOS WidgetKit 真实动作验收未完成，保留未勾选。

- [ ] **T-33** 小组件深链到具体对象
  - 确认 widget URI 正确跳转到详情
  - 依赖: T-13（深链路由就绪）
  - 验收: 点击小组件待办项进入该待办详情
  - 当前: 小尺寸对象根目标、深链守卫与 Flutter 接收已有局部证据；真实小组件点击验收未完成。

- [ ] **T-34** 数据变更推送小组件更新
  - `TodoProvider`/`HabitProvider` 变更后通过宿主编排调用 `HomeWidgetService.push`，完整文档经原生通道提交并确认后请求刷新
  - 验收: 完成待办后小组件数量同步更新
  - 当前: 前台2.2秒防抖/8秒最短间隔与后台最多两轮排空已合入；iOS捕获busy最多2次25ms重试、持续busy请求30秒重载，单次DTO派生全部时间线条目及刷新决策，见[当前限定验收](../evidence/priority-content-20261024/main-ios-capture-postguard-v235.json)。这些不是实际OS刷新保证。已有发布、清理、失效响应及恢复的宿主/原生合成验证；原生测试准备现状方面，除原应用 18 项插桩测试外，已独立打包 Store 运行时宿主（22 packaged / 0 executed，详见 [Store 宿主总结](../evidence/widget-store-runtime-host-20261023/summary.md)）与跨进程锁宿主（2 packaged / 0 executed，详见 [跨进程锁宿主总结](../evidence/widget-cross-process-host-20261023/summary.md)）两套独立测试包，均处于 0 executed 状态；实际 Launcher/WidgetKit 刷新与真机验收未完成，保留未勾选。详见 `docs/widget-publication-channel.md` 和 `docs/device-regression-evidence.md`。

---

## M9: 体验优化

- [x] **T-35** 统一 EmptyState/LoadingState/ErrorState 组件
  - `result_states.dart` 实现三件套
  - 替换各页面自定义空状态
  - 验收: 所有空状态视觉一致

- [x] **T-36** Backend cloud_sync_v2 schema 对齐
  - 后端 sync payload 字段与新 Goal/Todo 模型对齐
  - 新模型 `time_entries` 加入同步
  - 依赖: T-18（TimeEntry 模型就绪）
  - 验收: 同步后数据完整无丢失

- [x] **T-37** 全局搜索覆盖新模块
  - `GlobalSearch` 增加 TimeEntry、Workspace 搜索
  - 依赖: T-18（TimeEntry 就绪）、T-22（Workspace 就绪）
  - 验收: 搜索关键词可命中时间记录

- [x] **T-38** 备份导出包含所有新模型
  - `BackupService` 包含 `time_entries`、`achievement_states`
  - 依赖: T-18（TimeEntry 就绪）、T-26（成就数据就绪）
  - 验收: 备份导入后时间足迹完整

---

## M10: 智能化增强

- [x] **T-39** 中文自然语言日期解析
  - 解析"明天下午3点"、"下周一"、"后天"等表达
  - 集成到 `QuickCaptureFab`
  - 验收: 输入"明天下午3点开会"自动填充日期

- [x] **T-40** 看板视图
  - `TodoScreen` 增加看板视图切换
  - 自定义列分组
  - 验收: 可在看板和四象限间切换

---

## M11: 专注与习惯增强

- [x] **T-41** 专注标签分类统计
  - `PomodoroSession` 增加 `tag` 字段
  - 统计页按标签分类专注时间
  - 验收: 不同标签专注时间分别统计

- [x] **T-42** 习惯弹性打卡
  - `Habit` 模型增加 `weeklyTarget` 字段（如 5次/周）
  - UI 显示本周完成进度
  - 验收: 设置5次/周后显示 3/5 进度

---

## M12: 数据可视化

- [x] **T-43** 周报/月报生成
  - 自动汇总一周/一月的完成数据
  - 包括: 待办完成率、习惯坚持率、专注时长、目标进展
  - 依赖: T-18、T-20（时间数据和图表基础就绪）
  - 验收: 我的页面可查看本周报告

---

## M13: 测试与验证

- [x] **T-44** Holiday Calendar 2026 单元测试
  - 依赖: T-01
  - 验收: 覆盖所有法定假日和调休日断言

- [x] **T-45** ReminderScheduler syncTodos/syncGoals 集成测试
  - 依赖: T-02、T-03
  - 验收: 模拟待办/目标变更后验证提醒调度

- [x] **T-46** 日历冲突检测属性测试
  - 依赖: T-10
  - 验收: 随机生成事件组合验证冲突标记

- [x] **T-47** TimeEntry 自动生成测试
  - 依赖: T-18
  - 验收: 番茄完成事件触发 TimeEntry 创建

- [x] **T-48** Workspace 权限判断测试
  - 依赖: T-22、T-25
  - 验收: viewer/editor/owner 权限边界断言

- [x] **T-49** 当前全项目分析退出 `0`、零问题（2026-11-22 桌面重构后：[analyze-6](../evidence/antigravity-inherit-20261121/desktop-web-refactor-analyze-6.log) `76.1s`；重构前：[final2](../evidence/antigravity-inherit-20261121/flutter-analyze-full-final2.log) `17.2s` 与 [2806](../evidence/theme-widget-resume-20261116-v1000/current-full-analyzer-acceptance-2806.json)；随后仅更新闭合文档，产品/测试字节不变；不关闭 T-50/真实设备门禁）
  - 2026-11-22 [APK验证](../evidence/antigravity-inherit-20261121/apk-verification.json)：新 Debug APK `build/app/outputs/flutter-apk/app-debug.apk`（`223,981,588` B，SHA-256 `d4cab1ac95e8429910fb1f88a82ac14c923f176bd96d846ed4ade06be9c41483`，[构建守卫](../evidence/antigravity-inherit-20261121/alignment-gate-final-pass/7_8_debug_apk_build.guard.json) `minimumObservedFreeGiB=27.454`）通过 v2 签名、3 ABI、31 Provider 与 223 项小组件资源检查，并保留 `app-debug-2811.apk`（`3e631e87...`）与 `prior-apk-preserved-1029.apk`（`47e18675...`）；不代表真机或 12 门禁验收。
  - 2026-11-18 [APK接受2811](../evidence/theme-widget-resume-20261116-v1000/current-final-apk-terminal-acceptance-2811.json)：当前 debug APK构建/签名/31个Provider资源映射通过，原APK与失败记录保留；不代表整项目或设备验收。
  - 2026-11-07 [v894分析日志](../evidence/theme-widget-resume-20261106-v894/full-analyze.log)退出0；219项不同Flutter局部检查、30项纯Kotlin/JUnit及58组Swift提取逻辑通过。当前739文件全量待终态；Android完整编译、更新APK及设备门禁仍开放。
  - 2026-10-25 [小组件帮助与历史入口v783](../evidence/priority-content-20261025/local-priority-current-v783.md)：8文件123项相关检查与完整分析v780通过，1769输入一致不变；随后仅任务/矩阵文档变化。T50和原生设备门禁仍开放。
  - 2026-10-25 [今日完成保留v763](../evidence/priority-content-20261025/local-priority-current-v763.md)：10文件120项不同相关检查全过，完整分析v759实际退出0、零问题，1091输入一致不变；v745为真实缺口停止，1727部分计数不复用，T50待v764/v765/v766实际终态。
  - 2026-10-25 [静态契约修正v744](../evidence/priority-content-20261025/local-priority-current-v744.md)：产品未改，一份测试修正Note附件共享路由默认值检查，六文件109项相关回归通过；[完整分析v743](../evidence/priority-content-20261025/style-modal-analysis-v743.outcome.json)实际退出0、零问题，1091输入不变。v738全套不通过，v739未补测，T50由新v745/v746/v747链的实际终态决定。
  - 2026-10-25 [本批收敛v737](../evidence/priority-content-20261025/local-priority-current-v737.md)：反馈10项、Mine整份53项及AI整份31项，共94项不同检查通过，三处产品实现保留；[完整分析v736](../evidence/priority-content-20261025/route-state-analysis-v736.outcome.json)实际退出0、零问题，1091输入不变。733文件62组全量v738及v739补测/v740身份审计待真实终态，T50保持开放。
  - 2026-10-25 [本机续接v732](../evidence/priority-content-20261025/local-priority-current-v732.md)：反馈产品未改，四项新实时主题检查及原有六项状态检查全过；[完整分析v731](../evidence/priority-content-20261025/feedback-detail-analysis-v731.outcome.json)实际退出0、零问题，1091输入不变。Todo此前107项输入范围保持，T50待当前源码最终全量门禁。
  - 2026-10-25 [待办象限文字v726](../evidence/priority-content-20261025/todo-quadrant-current-v726.md)：12文件107项不同相关检查通过；[完整分析v725](../evidence/priority-content-20261025/todo-quadrant-analysis-v725.outcome.json)退出0、零问题，1091输入与候选/回归一致且不变。24张选择项截图已查看，T50仍待当前源码最终全量门禁。
  - 2026-10-25 [待办详情弹窗v721](../evidence/priority-content-20261025/todo-modal-live-current-v721.md)：95项不同相关检查通过；新测试三处花括号问题修正后，该文件6项重跑通过，其他89项输入不变（不重复计数）。[完整分析v720](../evidence/priority-content-20261025/todo-modal-analysis-v720.outcome.json)零问题，1091输入不变。T50仍待最终全量执行。
  - 2026-10-25 [笔记附件弹层修复v713](../evidence/priority-content-20261025/note-attachment-live-current-v713.md)：12文件153项不同相关检查通过，[完整分析v712](../evidence/priority-content-20261025/note-attachment-analysis-v712.outcome.json)退出0、零问题；1091绑定输入与候选/回归一致。新快照全量T50待最终执行。
  - 2026-10-25 [完整分析v700](../evidence/priority-content-20261025/main-goal-profile-analysis-v700.outcome.json)退出0、零问题，1091个输入未变；已与v702/v703完整测试快照绑定。后续仅有验收文档更新。
  - 2026-10-25 后台标签过时源码断言仅修正测试；原文件3项及现有两种主题真实渲染18项通过，当前完整分析[v524终态](../evidence/priority-content-20261025/main-priority-analysis-v524.outcome.json)零问题，1086输入不变。产品及786个APK构建输入未改；原v515中断不算通过，T50由新v525全量回归记录，原生/真机与完整目标继续开放。
  - 2026-10-24 [readability最终绑定](../evidence/priority-content-20261024/readability-final-postguard-v330.json)：19文件197项相关检查、主目录完整分析通过，1074输入未变化，1066份Dart一致；414张最终截图已核对，v318本地debug APK绑定786个不变输入并通过签名/31个Provider检查。T-50、黄历24项及真机性能仍开放。
  - 2026-10-24 [iOS捕获当前主目录验收](../evidence/priority-content-20261024/main-ios-capture-postguard-v235.json)：v225三文件保护式合入，57项相关回归与v226全分析通过，1070输入不变、1062Dart；仅对此快照关闭。Foundation7组和Swift语法解析不是WidgetKit类型检查/OS刷新证据；主题/日记新候选及完整目标/T50/黄历24项仍开放。
  - 2026-10-24 [后台排空当前主目录验收](../evidence/priority-content-20261024/main-lifecycle-postguard-v206.json)：95项小组件相关回归及v204整项目分析通过，1070输入不变、1062Dart；仅对此快照关闭。后台为有界即时尝试，不代表OS/Launcher/WidgetKit执行；新[v205 APK源码绑定](../evidence/priority-content-20261024/android-debug-postguard-v208.json)通过，完整目标/T50/黄历24项继续开放。
  - 2026-10-24 [分享响应式当前主目录验收](../evidence/priority-content-20261024/main-share-reflow-postguard-v166.json)：实际107项相关回归通过、全分析零问题，1068输入不变，1060Dart匹配v165且保留1057份旧基线；[60张主目录图](../evidence/priority-content-20261024/visual-review/main-share-reflow-regression-v166-review.json)与已审候选逐字节一致。仅对此快照关闭；完整目标继续开放。
  - 2026-10-24 [倒计时单复数当前主目录验收](../evidence/priority-content-20261024/main-countdown-plural-postguard-v157.json)：v156合入后实际62项相关回归通过、全分析零问题，1067输入不变，1059Dart匹配且保留1058份旧基线；[67张主目录图](../evidence/priority-content-20261024/visual-review/main-countdown-plural-regression-v157-review.json)与已审候选逐字节一致。仅对此快照关闭；完整目标继续开放。
  - 2026-10-24 [小组件/分享/倒计时当前主目录验收](../evidence/priority-content-20261024/main-countdown-postguard-v137.json)：全分析零问题，1067个输入不变，1059份Dart与v136集成一致；27文件339项相关回归通过，[317张主目录截图](../evidence/priority-content-20261024/visual-review/main-countdown-regression-v137-review.json)全部与已审图字节一致。仅对此快照关闭T-49；全套T-50/黄历24项/原生真机性能和完整目标继续开放。
  - 2026-10-24 [小组件/分享当前主目录验收](../evidence/priority-content-20261024/main-widget-share-postguard-v125.json)：全分析零问题，1065个输入不变，1057份Dart与集成哈希一致；17文件277项回归通过，250张主目录截图与已审图片字节一致。仅对此快照关闭T-49；倒计时候选仍在隔离验收，T-50/黄历/原生真机性能及完整目标开放。
  - 2026-10-24 v90当前快照通过：[主目录全分析v86](../evidence/priority-content-20261024/main-three-scope-analysis-v86.outcome.json)零问题，1060输入不变；[交付后复核](../evidence/priority-content-20261024/main-final-analysis-postguard-v90.json)绑定1053份Dart。v76合并181项及清理后8项重跑通过，后者不重复计数；100张最终图及6张重跑图均与已审图字节一致。新隔离候选未合入，T-50及完整目标保持开放。
  - 当前[主目录完整分析v37](../evidence/priority-content-20261024/main-admin-countdown-full-analysis-v37.outcome.json)零问题，1051个输入不变；[集成后复核](../evidence/priority-content-20261024/main-admin-post-analysis-v37.json)确认1044份Dart一致。管理页12px圆角/44px动作经15项新验证与38项相关回归、8张图片查看后集成；个人页、倒数日和回退测试保持已集成。分享/预览正文候选待验收，T-50及真实设备/性能/完整目标仍开放。此前v34分析和v31 API诊断保留各自历史范围。
  - 2026-10-24 [当前主目录完整分析](../evidence/priority-content-20261024/main-content-full-analysis-v27.outcome.json)零问题，1048个输入不变，22.7秒终态0；[当前集成绑定](../evidence/priority-content-20261024/integrated-current-v26.stage.json)记录1041份Dart一致、1027份未分配基线不变。Controls26项及个人页9/7/23项、Mood8项已通过；新邮箱标签及其他页面候选仅在隔离目录，未替代主目录。T-49仅对此快照关闭，T-50及真实设备/性能/完整目标仍开放。早期27项诊断与180秒超时及下列历史通过记录保留其各自范围。
  - 2026-10-24 当前[六路保留流程交付](../evidence/priority-retained-flows-20261024/summary.md)收回33次AGY调用，完成Today生产力文案、Diary生成洞察及Calendar/Profile/Habit/Todo保留交互的局部修复。最终205个不同Flutter检查通过（含显式UTC/Apia5项），清理后10项重跑不重复计数；172张最终图片完成查看或字节一致核对。[整项目分析](../evidence/priority-retained-flows-20261024/main-final-clean-analysis-v4.outcome.json)零问题，1042个输入不变，1035份Dart与隔离目录一致，1016份原基线Dart不变。T-49仅对此快照关闭；T-50、黄历24项失败、原生/真机/通知/性能及完整目标仍开放。
  - 2026-10-24 前批[挂载弹窗与日记交付](../evidence/retained-widget-dialogs-20261024/summary.md)记录六路实际并发及十一项已终止后续作业；修复添加帮助动态主题、日记英文单复数及大字号元数据溢出，提取习惯确认展示并验证原有注销行为。最终198项不同Flutter检查、47项提取Swift逻辑检查通过，111张最终图片完成复核或字节一致核对。[整项目分析](../evidence/priority-main-routes-20261023/retained-widget-dialogs-final-current-v3.outcome.json)零问题，1031个输入不变；1027份Dart文件与隔离目录一致。一次AGY后续作业在写入后因额度耗尽退出，保留代码由主会话独立验收。T-49仅对此快照关闭；T-50、既有视觉/本地化问题、全路由及真机门禁仍开放。
  - 验收: 退出码为 0，无 error 级别问题
  - 2026-10-24 前一批[小组件与主题优先交付](../evidence/widget-theme-priority-20261024/summary.md)收回六并发及八次后续作业，完成主题持久化提交边界、日记/成就指标重排、iOS日历附件日期和习惯确认取消入口。最终226项不同Flutter检查及40项提取Swift逻辑检查通过，73张最终图片完成直接复核或字节一致核对。[整项目分析](../evidence/priority-main-routes-20261023/widget-theme-priority-final-current-full-analysis-v2.outcome.json)零问题，1026个输入不变，1022份Dart文件与隔离目录一致。T-49仅对此快照关闭；T-50、真机/WidgetKit渲染、全路由及完整目标仍开放。
  - 此前[次级页面六路并发验收](../evidence/secondary-live-parallel-20261023/summary.md)完成共用底部弹层、成就分享实时主题和受控弹窗主题遮罩修复。最终26项及相关49项通过，共75个不同检查；156张最终图片完成直接复核或字节一致核对。[当时整项目分析](../evidence/priority-main-routes-20261023/secondary-live-final-current-full-analysis-v2.outcome.json)零问题，1023个输入不变，1017份运行Dart文件与主目录一致。该历史快照中的窄屏英文指标断词已由上方新批次局部修复；测试字体缺字、T-50及原生/真机/完整目标仍开放。
  - 此前[设置流程六并发交付](../evidence/settings-live-parallel-20261023/summary.md)完成附件标题/44dp目标与打开中弹窗主题修复；最终26项及相关12+22项通过，119张最终图片复核完成。[当时整项目分析](../evidence/priority-main-routes-20261023/settings-live-final-current-full-analysis-v2.outcome.json)零问题，1015个绑定输入不变且交付前再核对一致；1009份运行Dart文件与主目录一致。该记录保留其历史快照范围；T-50及真机/完整目标仍开放。
  - 2026-10-23 六项并发验证与四象限修复完成后，当前整项目 `flutter analyze --no-pub` 退出 0、无问题，覆盖 lib/test/integration_test/tool 与项目配置，1009 个绑定输入未变化且交付前再次核对一致；见[当前完整分析终态](../evidence/priority-main-routes-20261023/widget-live-final-current-full-analysis.outcome.json)。同批[最终合并回归](../evidence/shared-controls-review-20261023/widget-live-final-29.outcome.json)29/29 通过，详见[本批范围与限制](../evidence/widget-live-parallel-20261023/summary.md)。此前新增测试的编译与夹具错误已修正；T-50 与真实设备门禁仍未完成。

- [ ] **T-50** `flutter test --no-pub` 全通过（当前 `test/**/*_test.dart` 共 `819` 份 host 测试 + `1` 份设备 `integration_test`；Web 桌面重构前 `817/817` 份 host 已全量闭合且零未解决，Web 桌面重构后已通过受影响 `+124`/`+38`/`+53` 回归、`1/8` 及 `analyze` 零问题，最新字节完整 `819` 份全量尚待重跑）
  - 验收: 所有测试用例通过
  - 2026-11-21/22 [汇总记录](../evidence/antigravity-inherit-20261121/summary.md)：Web 桌面重构前 `817/817` 份 host 测试执行（`28` 批 `t50-batches/results.json` `10,850` 过 / `4` 条件跳过 / `53` 批内失败 + 独立 `main_bootstrap_widget_host_test.dart`），4 项条件跳过在 `TZ=America/Los_Angeles`（`17/17`）与 `TZ=Pacific/Apia`（`3/3`）实测通过，全部受影响文件经 `post-t50-fixes-recheck`、`ai-schedule-final-recheck`（`92/92`）、`more-apps-retained-route`（`48/48`）及 `main-bootstrap-bare`（`1/1`）闭合，零未解决；Web 桌面重构后 `alignment-gate-final-pass` `1/8` 通过、`2/8` 在 `+392` 因外部编译内存超限中断，受影响回归 `+124`/`+38`/`+53` 通过。
  - 历史快照依据为[v858终态](../evidence/priority-content-20261025/current-chain-v858.outcome.json)与[v857身份审计](../evidence/priority-content-20261025/conditional-coverage-v857.json)：9469项不同检查通过，零未解决跳过。完整清单含33组5653项按v845显式差异审计继承；本轮v867已改变产品/测试，该验收不自动扩展至当前字节。历史v764等拒绝或部分结果不作为当前验收依据，原生/设备及完整目标不随T50关闭。
  - 2026-10-25 [最终本机验收v706](../evidence/priority-content-20261025/local-suite-acceptance-v706.json)：733份测试文件、62组完整串行执行，9422过/9条件跳过/0失败；9项条件用例全部在相应时区实际补测通过，[v705身份审计](../evidence/priority-content-20261025/conditional-coverage-v705.json)逐项一致，共9431项不同用例通过，无未解决跳过，历史部分结果复用0。验收时1769个输入不变；之后仅更新验收文档，代码/测试/配置保持原快照。T32/T33/T34及真机通知/性能仍开放，新APK尚未打包。

- [x] **T-51** `python3 -m unittest discover -s backend` 全通过
  - 验收: 后端所有测试用例通过
  - 2026-11-21 当前全量检查：156 项全通过（0 失败/错误/跳过，`50.343s`，隔离临时库且无外部网络连接），见[后端结果](../evidence/antigravity-inherit-20261121/backend-full-result.json)。
  - 2026-10-23 当前全量检查：156 项通过，源码输入不变；使用临时数据库并禁止 socket 连接，详见[后端终态](../evidence/android-debug-current-20261023/backend.outcome.json)。 2026-10-24 [四项输入字节复核](../evidence/priority-content-20261024/backend-retained-inputs.json)仍一致，沿用该验证范围，未重新执行。

- [x] **T-52** 手工回归清单更新
  - 更新 `docs/manual-regression-checklist.md`
  - 覆盖所有新增功能的回归路径
  - 验收: 清单覆盖 M0-M12 全部用户可见功能
  - 2026-10-23 补充第 33 节默认 iOS / 毛玻璃、保留草稿的语言切换与系统小组件对照步骤；条目仍待真机执行，局部自动验证范围见[本轮报告](../evidence/account-status-live-locale-20261023/summary.md)。

---

## 依赖关系速查

```
T-01 ← T-04（节假日数据 → Goal 编辑页）
T-01 ← T-44（节假日数据 → 单元测试）
T-02 ← T-45（syncTodos → 集成测试）
T-03 ← T-45（syncGoals → 集成测试）
T-07 ← T-08, T-10, T-21, T-31（详情面板 → 操作分发/冲突/时间/课程）
T-10 ← T-46（冲突检测 → 属性测试）
T-13 ← T-33（深链路由 → 小组件深链）
T-18 ← T-19, T-20, T-21, T-36, T-37, T-38, T-47（TimeEntry → 下游）
T-22 ← T-23, T-24, T-25, T-37, T-48（Workspace API → 下游）
T-25 ← T-48（权限限制 → 权限测试）
T-26 ← T-27, T-28, T-38（成就引擎 → 下游）
T-30 ← T-05（纪念日模型 → alarm kind 支持）
```
