# Android widget day-boundary refresh contract — 2026-10-09

## 决定与范围

在现有 widget registry / lifecycle / restore 路径上增加**一个全局、单次、非精确的本地日界／UTC offset 变化闹钟**。由独立的 private receiver 接收，再请求现有 provider 只读重绘并安排下一次。无需新 service、WorkManager、轮询、Flutter engine 或精确闹钟授权。

审阅源码来自 `/home/ubuntu/duoyi`，基线版本由主审指定为 `67b548d`；未使用 Git 核验或读取实施中的 AGY 工作树。实施隔离树由主审另备为 `widget-refresh-20261009`。本批只实施调度核心；原生快照读取／提交原子性另列已知 gap，不扩入本批。

本审应用 `android-intent-security` 技能核对组件与传入 Intent：显式 private receiver、immutable PendingIntent、严格 action allowlist、无 nested Intent 转发。没有修改仓库，没有运行测试、analyzer、构建或 Flutter 命令；只生成本报告。

## 1. 现有基础设施证据

| 位置 | 事实与复用方式 |
| --- | --- |
| `DuoyiWidgetVariantProviders.kt:349–376` | registry 已能枚举固定已知 provider，查询真实 `getAppWidgetIds(component)`，只对存在实例的 component 发显式 APPWIDGET_UPDATE。复用；不要创建第二套 provider 名单。 |
| 同文件 `:459–527` | 10 个 family 各有 standard / compact / detailed，另有 legacy 总览，共 31 个已知 component。active / pending pin 状态不等同于桌面实例。 |
| 同文件 `:201–230` | 恢复已有实例／variant component enable 状态。可在结尾调用 scheduler reconcile，返回 restored=0 时也执行。 |
| `DuoyiStyledWidgetProvider.kt:11–59` | 10 个 family 与其 variant 的共享基类；已有删除与 options 处理。适合补统一 lifecycle hook，避免逐 provider 复制调度。 |
| `DuoyiWidgetProvider.kt:22–37` | legacy 总览直接继承 AppWidgetProvider，须独立接入同一个 lifecycle hook，不能只改 Styled。 |
| `DuoyiWidgetRestoreReceiver.kt:9–28`、manifest `:145–156` | 已处理 BOOT_COMPLETED、DATE_CHANGED、TIME_SET、TIMEZONE_CHANGED、MY_PACKAGE_REPLACED 与两种 vendor quickboot；先 restore，再刷新所有实存 widget。扩展此既有系统入口进行 rearm。DATE_CHANGED 是补偿事件，不能作为准点／持续唤醒保障。 |
| `MainActivity.kt:96–116` | resume 后既有 restore 路径延迟 4.5 秒、60 秒节流；即使 restored=0 也调用 registry restore。把 reconcile 放到该 registry 方法中即可覆盖 resume 恢复，无需修改 Activity。 |
| `MainActivity.kt:470–472`、`home_widget_service.dart:707–717` | Flutter 发布／清理后通过 refreshAllWidgets 进入 registry。在 registry 更新入口 reconcile，可自然覆盖账号 clear／新发布后的调度。 |
| 所有 `duoyi_*widget_info*.xml` | 现有 updatePeriodMillis=1,800,000；保留作为系统 best-effort 备用刷新，不提高频率，不把它当精确 midnight 保证。 |
| `DuoyiFocusHabitWidgetProvider.kt:329–347` | 独立结束闹钟 requestCode=14101，优先 exact、无权限时 inexact；session 未发布时保留现有闹钟（198–199 行）。本批不改、不取消、不复用这个 token。 |
| `ReminderRingtoneScheduler.kt:474–499` | 提醒闹钟有独立恢复／播放语义；不把 widget 日期刷新加入提醒恢复、前台播放 service 或通知调度。 |
| `android/app/build.gradle.kts:47–53,104` | Java 17、core library desugaring 与 desugar_jdk_libs 2.1.5 已存在；可直接用 java.time 日期与 ZoneRules 算术，无需 SDK / Gradle 升级。 |

现有 Dart `notificationProgressMidnightTimer`（`main.dart:1884–1893`）仅用于通知进度，依赖进程存活，不是原生 widget 日界闹钟，不复用为后台保证。

## 2. 精确的目标时间语义

纯函数输入为一次捕获的 `now: Instant` 与 `zone: ZoneId`，返回严格晚于 now 的最早边界；调度调用每次重新获取系统当前 zone，不能缓存创建进程时的 zone。

```kotlin
val nextDay = now.atZone(zone).toLocalDate()
    .plusDays(1).atStartOfDay(zone).toInstant()
val nextOffsetChange = zone.rules.nextTransition(now)?.instant
val boundary = listOfNotNull(nextDay, nextOffsetChange)
    .filter { it.isAfter(now) }.minOrNull()
```

- 日期采用 ISO / Gregorian 本地 civil date。先做 LocalDate.plusDays(1)，再 atStartOfDay(zone)；不能用 now+86,400 秒或以 UTC 的日期代替本地日期。
- atStartOfDay 采用该 zone 下一 civil date 的最早有效时间：午夜 gap 可落到当日第一个有效时刻；重复午夜选择最早有效 offset；被跳过的整天自然前移到下一个存在的本地日期。
- nextTransition 指**任何 UTC offset transition**，包含 DST、半小时 DST 和政治性 offset 调整。若它早于下一个本地日开始，先在那里重绘，使同一天的 offset freshness 失效；否则先午夜。两者同 instant 时只需一次。
- 闹钟延迟投递或跨过数日时，用**实际接收时**的 now / zone 重算下一边界，不循环补播旧午夜，不依赖旧 Intent 时间／日期 extras。每次新目标严格在未来，避免 past-trigger 紧循环。
- 时间手动前移／后移、zone 变更后立即重绘，并以新的 now / zone 替换旧闹钟。ZoneRules 在当前边界触发后重新查询，不能固定每日 24 小时 repeating alarm。

## 3. 非精确、无新增授权的调度

使用一个固定身份的 PendingIntent 和单次 `AlarmManager.RTC_WAKEUP`：API 23+ 调 `setAndAllowWhileIdle`；若仍支持更低 API，使用普通 `set` 兼容分支。不调用 setExact / setExactAndAllowWhileIdle、canScheduleExactAlarms，不请求 exact 权限，不依赖 manifest 已有 exact permission 是否获批。

实际投递允许平台批处理、Doze、厂商省电延迟，**不承诺 00:00 准点**。这是日期 UI 的 best-effort 唤醒；保留现有周期／时间广播／resume / publish 路径补偿。一天通常一次，必要时另有 offset transition 一次；禁止每分钟自唤醒。

PendingIntent 固定为：

- 显式 `DuoyiWidgetDayBoundaryReceiver` component。
- 独立私有 action，例如 `com.duoyi.duoyi.WIDGET_DAY_BOUNDARY`。
- 独立 requestCode，例如 14102；与 focus 14101 / 其他提醒 token 分离。
- `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`（按现有 minSdk 兼容 API 23 之前）；无 payload、widget id、日期、账号 nonce、deep link、nested Intent 或外部回调。

token 的不变性靠 component / flags / receiver 隔离；action 名字本身不充当秘密。多次 reconcile 只替换同一个闹钟，不能累积多个 token。取消用完全同一 component / action / requestCode / flags 身份；不能调用全局 cancelAll。无需持久化旧目标或旧账号，仅从当前时钟和实际 widget inventory 重算，避免 reboot 后缓存误阻止 rearm。

## 4. 生命周期与所有权

| 触发 | 动作 |
| --- | --- |
| 首次 enable / 首次 update / pin / restored / options update | 查询 registry 实存实例；有任一实例则安排下一个边界。首次 enable 尚查不到 id 时，随后 update / restored / options 路径补上。 |
| 删除任意实例 / disabled | 重新查询所有已知 component；其他实例仍存在就保留／替换闹钟，最后一个被删除则取消。最终 disabled 再 reconcile，防删除回调附近 inventory 延迟。 |
| alarm fire | allowlist action → 查询当前实存 widget → 请求现有 provider 重绘 → finally reconcile；没有实例只取消，不发送无意义更新。 |
| boot / package replacement | 沿用 existing restore enabled providers → 刷新当前实例 → finally rearm；OS reboot 已清除旧 alarm。不读取未解锁 credential storage，不新增 LOCKED_BOOT_COMPLETED 路径。 |
| DATE_CHANGED / TIME_SET / TIMEZONE_CHANGED | 沿用 Restore receiver，立即刷新所有实存实例，finally 重算并替换 alarm。 |
| app resume / Flutter refreshAllWidgets / account clear / publication | 利用现有 registry restore / request-update 路径 reconcile；与刷新业务解耦，reconcile 自身只 set/cancel，不再次 request update。 |
| force-stop / uninstall | 不宣称可绕过平台。uninstall 由 OS 清除；force-stop 后等用户重新启动，再由 existing resume / publish 路径恢复。 |

`DuoyiStyledWidgetProvider` 的共用 hook 应在 framework 生命周期 dispatch 完成后 reconcile，例如 base onReceive 中对 widget 生命周期 action 的 allowlist + `try/finally`。所有子类目前调用 super.onReceive；不要只覆盖 base onUpdate，因为子类 onUpdate 并不统一调用 super。legacy 的 onReceive 同样接入。也可用成对 onEnabled/onDisabled/onDeleted/onRestored callbacks，必须覆盖已有 variants 和 legacy。

registry 应提供统一实存 component / id inventory；查询来源仅 AppWidgetManager 对固定已知类的结果，不信任 incoming EXTRA_APPWIDGET_IDS、不以 pending pin / active provider prefs 代替真实存在。alarm 只调用 registry，不能直接散落构造各 provider 名。

registry 的 request-update 和 restore 入口、provider lifecycle、alarm receiver 可能多次 reconcile：行为须幂等、只保留一个未来 alarm，没有广播递归。若 render request 失败，finally 仍安排下一边界；日志不输出账号 nonce 或用户内容。接收器只做短小原生查询／dispatch，不启动 app / Flutter / 网络；无需新 service 或长期异步工作。

## 5. 哪些 widget 重绘、如何保持 stale / account 边界

使用 `requestUpdateForAllWidgets` 更新**所有实际安装的 31 个已知 component 中的实例**，涵盖 todo、focus、habit、calendar、schedule、goal、course、note、anniversary、diary 的三种密度及 legacy。虽 note / diary 等内容本身未必每天变化，当前统一 snapshot day freshness 仍每天失效；不能只刷新 Calendar / Anniversary 后让其他 widget 持续显示已过期 daily 数据。

- provider 继续从 `DuoyiWidgetSnapshot.forDisplay` 读取；午夜／offset 改变时旧 payload 进入既有 stale 文案、清空对象 `_id`、数字占位。Calendar 网格／日期 header 可按当前 zone 的本地日期重绘。
- 原生日期刷新**不计算新待办、日程、Anniversary 剩余天数，不改 producer 排序，不写 widget_snapshot_day / offset / account_nonce**。真正的新数据仍由 Dart 当前账号 publication 发布。不得“把旧 payload 的 day 改成今天”伪装 fresh。
- focus 在同一 published session 下可跨午夜继续绝对时间计时；daily stale 与 timer session trusted 是两套已有语义。原结束 alarm 14101 保持，day alarm 不负责结束专注、不重置 timer，也不清除其旧 token。
- day alarm token 是 immutable、无账号和内容的 opaque 触发器：账户 A 时创建的 token 在账户 B 时投递，只请求 provider 读取投递时的当前 publication，不携带／回放 A 的旧对象，也不能重借 B 的 nonce 给 A 的 id。

### 现有 fence 与明确的快照 gap

已有 Dart writer 序列化 queue（`home_widget_service.dart:211–219`）；reset 立即增加 generation / 更换 nonce（281–291），clear 先置空 day（310–320）；push 先置空 day（497–504），写 payload / offset，并核对 generation、locale、当前本地 day / offset 后才最后发布 day（659–691）。当前 widget mutation consumer 还验证 day / offset / account nonce（198–208）。本批全部保持。

**不能称 baseline native render 已原子／immutable：** `DuoyiWidgetSnapshot.forDisplay:25–52` 只冻结 fresh / sessionTrusted 布尔，getString / getInt / getAll 仍读取 live SharedPreferences。渲染期间 clear / publication 变更可能混合读取，尚无统一冻结 payload / before-commit fence。本批不把 opaque immutable alarm token 的安全性等同于 immutable render snapshot，也不据此宣称消除此 gap。

另批如需要加强，应冻结同一 publication 的字段与 `(day, offset, nonce)`，action URI 使用同一冻结元数据，并在 UI commit 前核对当前 publication / 时钟 fence；失败丢弃旧 render 或重绘安全 stale，不能给旧 id 重绑定新 nonce。此次 scheduling 文件范围不扩入 Snapshot / 各 provider render 提交点重写。

## 6. 最小生产修改范围：8 个文件

| 文件 | 有界职责 |
| --- | --- |
| 新 `DuoyiWidgetDayBoundaryPolicy.kt` | Foundation-only java.time 纯函数：给定 now / zone，返回严格未来 day / offset 边界。无 Context / SharedPreferences。 |
| 新 `DuoyiWidgetDayBoundaryScheduler.kt` | 单 token set / cancel / reconcile；读取实存 inventory，使用当前 now / zone，处理平台调度失败。 |
| 新 `DuoyiWidgetDayBoundaryReceiver.kt` | manifest private，单 action allowlist，无 incoming payload，refresh + finally rearm。 |
| `DuoyiWidgetVariantProviders.kt` | 复用已知类清单，提供实存 inventory；request-update / restore 后 reconcile，避免递归。 |
| `DuoyiStyledWidgetProvider.kt` | 全 family / variants 共用生命周期 hook。 |
| `DuoyiWidgetProvider.kt` | legacy 共用同一个调度器的生命周期 hook。 |
| `DuoyiWidgetRestoreReceiver.kt` | 既有系统恢复／时间 action 后 finally rearm。不加入新私有 alarm action。 |
| `AndroidManifest.xml` | 新 private receiver `android:exported="false"`、enabled=true、无 intent-filter、无新增权限。 |

已有 Restore receiver exported=true 与 vendor quickboot 兼容路径保留；标准系统 action 依赖 Android protected broadcast。vendor 自定义 quickboot 不可仅凭 action 名称视作已认证，因此只能进入现有只读 restore / render / rearm，不能扩为账号发布或 mutation。新私有 alarm action 不挂在该 exported receiver 上。没有 nested Intent，自然不需新增 IntentSanitizer 依赖或签名权限。

## 7. 必要验收 case（仅规定，未执行）

### 纯 unit / fixture

- UTC / Asia/Shanghai 日末；非整小时 offset（Asia/Kathmandu），负 offset 与 UTC 日期不同；月底、跨年、28/29/30/31 天。
- America/New_York 春 DST gap、秋 overlap：先 offset transition，再下一 local day；Australia/Lord_Howe 半小时 DST；无 future transition 的固定 zone。
- 历史午夜 gap / overlap、Pacific/Apia 跳日：目标是最早有效 day start；不可 now+24h。transition 恰等于 now 时不重复安排过去边界。
- 延迟投递跨数日、手动前移／后移时钟、换 zone：目标始终严格未来，按新的实际 now 重算，不补播旧事件。
- 零实例取消；first add 安排；两 family / variants 多实例只一 alarm；删一个保留、删最后一个取消；pending pin / active flag 而无真 id 不安排。
- alarm PendingIntent 的固定 component / action / requestCode、immutable flags，无 payload / nonce；与 14101 的身份不同，cancel 不影响 focus。
- lifecycle 重入与重复 reconcile 幂等；update dispatch 失败仍 rearm；compute / platform schedule 失败不 tight-loop、不启动轮询。

### 设备验收

- Android 23+ 和 31+ 未授予 exact 权限仍能安排并投递 inexact alarm；屏幕关闭 / Doze / 厂商后台限制下记录投递偏差，验收 best-effort，不声称准点。
- 各 family 的 standard / compact / detailed、legacy 首次 pin、resize、restore、删除一个／全部；只有确实存在的 widget 被更新。
- app 进程退出后日界；boot / unlock 后恢复；package replace；系统日期／时间／时区手动改变；resume 恢复（包括 restored=0）；force-stop 后用户重启恢复。
- 午夜／DST 后旧 publication 文案变 stale、对象 id 不复用；重新打开 app 发布后恢复 fresh，Calendar 日期正确。
- 跨午夜运行／暂停／结束专注，14101 finish alarm / live chronometer / absolute end 不受日界 cancel 或 rearm 影响。
- A 建 alarm → logout / switch / day 清空或 partial write → alarm fire：不写 publication、不发 mutation、不回放 A payload。旧 widget mutation nonce 拒绝规则保持；native live-read 原子性 gap 单列，不冒称此 case 证明其已修复。
- 外部 app 不能向新 exported=false receiver 注入刷新；未知 action 被忽略，无 extras / nested Intent 可改变 provider、账号、目标或触发业务操作。

## 8. 风险与验收界限

非精确 alarm / 系统广播／widget 周期更新均受平台与 OEM 策略影响，强制停止不能自动绕过；系统 timezone rule 更新也要靠后续 reconcile 重新读取规则。native-only refresh 只能展示安全 stale，不能在 app 不运行时生成最新业务数据。保持现有 restore 的 bounded 原生任务，避免唤醒后启动 Flutter 或用户界面。native immutable render / commit fence 是已知后续工作；本批只承诺调度与 opaque token 边界正确。

STOP
