# Android widget day-boundary implementation audit — 2026-10-09

## 结论与范围

**本轮已发现的源码问题全部闭合，没有剩余必修项。** 日期／DST 算术、单一非精确闹钟、private immutable Intent、registry inventory 和 lifecycle rearm 均通过静态审阅。初读发现新增 receiver 的派发异常 containment 遗漏，主审已修复，本审已复读确认。

只读工作树 `/home/ubuntu/duoyi-worktrees/widget-refresh-20261009` 的八个生产路径：Policy、Scheduler、Receiver、Styled、legacy WidgetProvider、VariantProviders、RestoreReceiver、AndroidManifest。对照最终 `android-widget-day-boundary-contract-oct9.md`，并用普通源码 diff 核对五个已存在路径相对 `/home/ubuntu/duoyi` 的变化。没有读取其他 AGY 工作树，没有修改仓库，没有使用 Git、测试、构建、compiler 或 Flutter 命令；只写本报告。

沿用已读取的 `android-intent-security` 技能检查 private receiver、显式 component、immutable PendingIntent 和 action allowlist。

## 已闭合修复

### P2 已闭合 — 新 receiver 截住刷新派发 RuntimeException

位置：[DuoyiWidgetDayBoundaryReceiver.kt:16](/home/ubuntu/duoyi-worktrees/widget-refresh-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetDayBoundaryReceiver.kt:16)。

初读时，`requestUpdateForAllWidgets()` 的 query / enable / sendBroadcast RuntimeException 可穿透只含 try/finally 的新 receiver，导致 Android 接收器执行失败并可能终止应用进程。

主审随后在 receiver 16–17 行加入 catch RuntimeException 和固定通用 Log.w 消息。本审复读确认：invalidate 仍在前；18–20 行 finally reconcile 保持；没有增加立即重试、服务或轮询。scheduler 的 reconcile 也已自行 catch RuntimeException。该新增入口的源码问题已闭合。

RestoreReceiver 的 15–16 行仍保留原有派发异常外逸模式；该问题在基线已存在，不属于新增 regression。本次修复按主审范围只落在 private DayBoundaryReceiver，未扩大既有恢复逻辑。

静态修复验收通过：刷新 query / enable / broadcast 的 RuntimeException 被 catch；finally 仍尝试安排下一边界；异常路径不写 publication、不重发 mutation、不进入紧循环。未运行异常 fixture。

## 已通过的静态审阅

| 项目 | 证据与判断 |
| --- | --- |
| 本地日期／DST | Policy 9–22 行从同一 now / ZoneId 计算 LocalDate.plusDays(1).atStartOfDay；选择更早的 nextTransition；严格 `isAfter(now)`，额外 loop 防非未来 day start。不用固定 24 小时，gap / overlap / skipped day 由 zone date 算术处理。 |
| 权限与 Android API | Scheduler 69–77 行 API 23+ setAndAllowWhileIdle(RTC_WAKEUP)，低 API 普通 set；不调用 exact API 或 canScheduleExactAlarms，不新增权限。java.time 的既有 Java 17／desugar 前提已由契约基线核对；本轮未编译。 |
| 一个 PendingIntent | Scheduler 14–15、60–66 行固定 action、requestCode 14102 和显式 private component；API 23+ immutable。没有 payload / nonce / id / URI extras。相同 token set 替换旧 alarm，cancel 使用同 mutability 身份和 FLAG_NO_CREATE，不创建空 token。 |
| 正确取消与 focus 隔离 | Scheduler 80–85 行仅取消并销毁 14102 token，无 cancelAll；不引用或复用 focus 14101。五个现存路径的 diff 只增加 scheduler hook／inventory／private receiver 声明，legacy render 和既有 focus manifest 配置未改变。未额外读取 scope 外 focus provider 文件。 |
| 真实 inventory | VariantProviders 235–239 行遍历同一 allWidgetProviderClasses，查询实际 getAppWidgetIds 数量，无 ensureProviderEnabled 或 pin prefs 计数。原名单仍是 10 family×3 + legacy，共 31 类；没有建立不一致的新名单。 |
| 零实例／多实例 | Controller 55–60 行零 count 取消；存在任意实例则一 alarm。cancel / schedule false 返回 FAILED；handoff 前清 scheduledAt，失败或抛异常仍可重试，删除一个不误取消其余实例。 |
| lifecycle | Styled 13–20 行和 legacy 23–33 行在 super dispatch 后 finally reconcile；Scheduler 19–26 行覆盖 enabled/update/options/restored/deleted/disabled。因 hook 在 onReceive，子类不调用 super.onUpdate 也不丢 rearm。 |
| restore / resume | VariantProviders 230–231 行强制 reconcile，返回 restored=0 也执行；利用既有 resume restore 调用恢复 alarm。RestoreReceiver 对既有系统 action 先 invalidate，finally reconcile；未扩大 supportedActions。 |
| fire / 延迟投递 | DayBoundaryReceiver 11–20 行仅 accept 精确 action，清 dedup cache，再 dispatch current registry 更新，catch RuntimeException 并 finally reconcile。新的 now / system zone 在 Scheduler 39–40 行获取，无旧目标时间 / 日期 extras 回放。 |
| 无递归／重复 alarm | reconcile 只读 installed count 再 set/cancel，不 requestUpdate；registry requestUpdate 的 finally 和 provider lifecycle 多次进入时 Controller scheduledAt 去重。receiver invalidate 后第一次成功 rearm，后续同边界为 UNCHANGED；force restore 故意重新交给系统。两层 synchronized 没有反向调用或锁循环。 |
| scheduling exception | Scheduler 49–53 行捕获 query / policy / AlarmManager RuntimeException，invalidate cache 并保留未来生命周期重试；query 失败不被误认作零实例。controller 端 schedule false / cancel false 可观察失败，不假报成功。没有后台紧循环。 |
| Intent 安全 | manifest 145–147 行 exported=false、enabled=true、无 intent-filter；receiver 未读取 extras 或转发 nested Intent。exported Restore 保持原系统／vendor action；新 alarm action 未挂到 exported receiver。 |
| publication / mutation | 新 Policy／Scheduler／Receiver 没有 SharedPreferences 写入、Dart engine、网络或业务 mutation；只调现有 provider 更新。不会把旧 day / offset / nonce 更新成 fresh，opaque token 不携带旧账号内容。 |

## 有界设备／运行时验收缺口

下列项目是本轮未执行的验收，不是已证实的源码错误：

- Android 23 / 31+ 无 exact grant，屏幕关闭／Doze／OEM 省电下 inexact alarm 的实际投递；不能承诺 00:00 准点。
- 首次 pin、31 类的有效实例／各密度、删一个／删最后一个、inventory 在 delete / disabled 附近的系统更新时间；多个实例仍只有一个 alarm。
- 进程退出、boot / unlock、package replace、时间／时区手改、resume restored=0 与 force-stop 后用户重启恢复。
- 月底／leap-day／跨年、早于午夜的 DST transition、半小时 transition、午夜 gap / overlap 和 skipped civil date 的纯 fixture；源码算法符合契约，但未运行 case。
- 跨午夜运行／暂停／结束专注，确认现有 14101 与 live timer 的实际设备行为；日界 token 无碰撞的静态结论不等于设备验收。
- 账号 clear／部分发布时的实际 stale 呈现、当前 publication 的后续恢复和旧 mutation nonce 拒绝。

原 native Snapshot live SharedPreferences 读取／UI commit 原子性仍是契约明确列出的既有 gap；本批没有修复或扩大它。immutable alarm token 不构成 immutable payload / atomic render 的证明。

## 交付判断

新增 receiver 的 RuntimeException containment 已补齐并复读通过；此八文件调度范围没有剩余已发现的源码必修项。之后仍须由主审安排既定 pure fixtures 与有界设备验收；本报告不宣称测试、编译或设备已通过。

STOP
