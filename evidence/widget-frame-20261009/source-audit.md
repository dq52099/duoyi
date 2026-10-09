# Android immutable widget frame source audit — 2026-10-09

## 范围、结论与证据边界

只读审阅 `/home/ubuntu/duoyi-worktrees/widget-frame-20261009`，依据 `android-widget-snapshot-render-contract-oct9.md`。主审告知工作树已先合入 widget display commit `3d073b4`，frame 生产修改已停写；本审未用 Git 核验这些状态。新增 FrameCore / FrozenWidgetPreferences / RenderFrame、替换 Snapshot、11 个实际 renderer、相关 Copy / Theme 与 19 个 pure JUnit fixtures 均进行了源码追踪。没有修改生产文件或 fixtures，没有运行测试、编译、Flutter、Android、Gradle 或 Git delivery。本次唯一写入是本报告。

**revision1 有一项 must-fix：Calendar 月标题 formatter 未使用 frame 的冻结 zone。**raw / display map、typed adapter、fresh/session predicates、提交 fence、有界重试、11 renderer 覆盖、Focus accepted-only alarm 和 legacy action gating 的主要路径符合契约，未发现另一项需要修复的确定生产缺陷。

这是一份源码审计结论，不是执行或设备验收通过。主审要求收到本审证据后修复 Copy；本审已经停止读取生产文件，后续复审需等待修改完成通知。

## 1. Must-fix F1：Calendar 月标题仍读取系统默认 zone

**位置：**

- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt:80–84`：正确以 `frame.calendar()` 取得 now，并把它传给 `DuoyiWidgetCopy.calendarMonthTitle(now, compact, isZh)`。
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetCopy.kt` 的 `calendarMonthTitle`：中英文两分支均为 `SimpleDateFormat(pattern, locale).format(now.time)`，没有设置 formatter 的 `timeZone = now.timeZone`。

`now.time` 只是 instant，不携带 Calendar 的 zone。新建 SimpleDateFormat 默认使用创建时的系统 zone，因此标题仍可来自 live zone，而网格来自 frame zone。

**供主审 fixture / controlled-source 验收的确定输入：**frame 的 clock zone 为 `Asia/Shanghai`，wall instant 为 `2024-02-29T16:30:00Z`（当地 `2024-03-01 00:30`）；传入该 Calendar，但formatter创建时系统默认zone为 `America/Los_Angeles`。网格是3月，标题会是2月 / `Feb 2024`。若默认zone在最终validation前恢复为Shanghai，core的zone前后相等，无法发现构建期间这次混读。这正是冻结zone需要消除的内部不一致，不能只用最终zone check补偿。

**限定修复：**中英文两分支的formatter均显式设置 `timeZone = now.timeZone`，或直接使用frame的显式zone格式化接口；保留原中英文月份格式与compact行为。不要改网格、业务publication、day scheduler或其他显示规则。

**验收要求：**Calendar参数zone与默认zone不同，月份 / 年份均按参数Calendar；覆盖zh/en与compact/standard，至少包含跨月与跨年instant。然后静态确认Calendar渲染没有残余formatter默认zone依赖。此报告未执行该case。

## 2. 冻结 map 与 SharedPreferences adapter

### 2.1 同一 raw capture 与防御性复制

`DuoyiWidgetSnapshot.capture`先取一次`backing.all`，由`DuoyiWidgetFrameCore`调用`immutableValues`创建独立LinkedHashMap，StringSet深拷贝为unmodifiableSet，map为unmodifiableMap。SharedPreferences支持的scalar类型按原类型保留。

publication day / offset / nonce均从这份rawValues解析，未混用live typed getter。`nonce`仅以isNullOrBlank判可信，存储与比较保留原字节字符串，没有trim或重新生成。

render prefs来自raw的presentation projection，随后`DuoyiFrozenWidgetPreferences`再次防御性复制；构建过程不会修改raw。core的full map比较使用rawValues，绝不拿stale placeholders / effective mode比较writer状态。

### 2.2 全部读入口与编辑边界

FrozenWidgetPreferences覆盖`getAll`、`contains`、string/stringSet/int/long/float/boolean，所有入口只访问同一内部immutable map，没有委托backing。StringSet无法改写frame，default set也返回副本；typed getter保留类型不匹配抛错的SharedPreferences语义，没有把所有字段强转字符串。

`edit()`显式拒绝，listener不能注册；unregister没有live注册可移除。Focus compat helpers继续从`prefs.all`读取冻结原类型String / Number / Boolean，未绕回HomeWidgetPlugin。

existing first-pin style初始化在`renderWidget`捕获前使用真实backing调用`saveForWidgetIfMissing`；delete / resize / pin生命周期的受控样式写入仍存在，不经过冻结editor。重试只重新capture/build，没有重复覆盖已有style。

**运行证据待补：**19个pure fixtures验证了core immutable map/StringSet行为，但不实例化Android SharedPreferences adapter；不能把它们等同于adapter签名编译或Android typed getters集成验证。

## 3. daily / no-session projection 与主题保持

### 3.1 可见账号字段清单

`DuoyiWidgetRenderFrame.displayValues`在非fresh时mask以下当前renderer业务输入：

- Todo count / Top3 count与Top3 text；habit percent / active count / summary / streak / quick label。
- pomodoro_today / focus_minutes_today / focus_summary / today_event_summary。
- goal / schedule / course / note / diary / anniversary / memorial 的1–3槽文本。
- calendar_month_summary，以通用本地化“Month view · Plan your day”替换旧publication的月份文案。
- 明确entity-ID regex与habit_quick_check_id置空；不是旧的任意`endsWith("_id")`。

当前11个renderer的业务getString/getInt与各itemIntent fallback已逐项对照。未发现可见旧账号字段从未mask的另一键回读。`brand_app_title`、nav labels与theme按契约属于允许保留的冻结外观/通用导航，未当作entity业务内容清空。

无可信session时另外删除全部`focus_timer_*`，并重置`next_focus_label`为本地化通用25分钟标签。all / typed getter / contains观察同一masked map，因此no-session不会因compat getter看见旧timer，又显示running / paused / livechronometer；没有timer label旧内容回显路径。

**语义细节：**Todo detailed的derived summary仍可能用masked 0生成“今日待办 · 0项”，而其主要count在finishRender中变成`—`。这沿用既有renderer派生文案，不泄漏旧值；本审不另扩大为copy重设计或must-fix。如产品希望所有derived数值文案也统一待刷新，可另行定义copy变更。

### 3.2 不清主题ID与密度一致性

`widget_theme_brand_id`和`widget_theme_card_skin_id`不匹配entity-ID regex，保持冻结原值；theme boolean / int /颜色 /背景asset同样来自frame prefs。Theme bitmap规格继续读该id的冻结effective mode，没有live options读取。

core的mode优先级与既有上限一致：instance→global→standard，尺寸过小或compact偏好为compact，detailed要求≥250×170，否则standard；缺有效尺寸保留偏好。display map把该id的effective mode固定下来，provider与finishRender使用同一mode / frozen options。

locale投影固定为core解析得到的en/zh，Copy.resolveLocale因而不会进入系统fallback读取；systemLocaleTag在capture与validation均检查。保存非法/缺失偏好的情况下，也不在构建中重新选locale。

## 4. 提交 fence、重试与主线程顺序

### 4.1 校验覆盖

`DuoyiWidgetFrameCore.rejectionReason`按raw map、options、zone、local day、offset、system locale、wall/elapsed skew与running countdown跨endsAt检查。full raw equality覆盖同账号同tuple但payload/title/ID已更新的ABA，不仅比较day/offset/nonce。options包括min/max width/height与style字段。

sessionTrusted要求合法canonical day、Int offset在[-1080,1080]和非空String nonce；fresh还要求day/offset等于capture clock。元数据类型错误不会被认作可操作fresh。原stale frame也不会根据live数据临时升级；raw变更必须重新build。

clock冻结wall、elapsed、zone，1秒wall/elapsed增量容差明确；普通渲染流逝不触发每次重试，day/offset/zone变化仍独立拒绝。countdown只有真正从capture前未到endsAt跨到已到时拒绝，第二帧可以作为expired重绘。该校验对全部renderer生效，属于保守一致性检查。

### 4.2 最多两次构建、无递归恢复

`DuoyiWidgetFrameAttempts.run`仅repeat(2)：capture→build→check；失败记录reason并重新捕获，不复用旧views / URI / metadata。第二次仍失败不commit、不执行effect。不调用requestUpdateForAllWidgets / provider递归，不增加payload写入或Flutter启动。

Snapshot外层捕获RuntimeException，build或updateAppWidget异常结束该id、返回false；provider forEach会继续后续id。commit成功返回后才触发acceptedEffect；effect异常仅安全日志，不回滚UI或广播重试。日志没有用户内容或nonce。

### 4.3 validate→commit无可重入应用callback

`renderWidget`显式检查main looper；off-main直接跳过。实际before-commit lambda只读backing.all、当前clock、options与locale；传入run的commit是固定`manager.updateAppWidget`。build与finishRender发生在validation之前；validation通过到commit之间没有用户callback、prefs编辑、post/await、广播或切线程操作。generic helper形式虽使用lambda，实际生产调用没有在该间隙执行外部自定义逻辑。

acceptedEffect是明确的**提交后**callback，其唯一生产实例是Focus alarm；不参与validate前后重新读payload或nonce。已有HomeWidget插件默认main-thread handler同步commit的线程证据继续适用；本次未修改插件或引入background writer。

这保证的是当前同进程native main-looper调用顺序，不是系统widget service / launcher的绘制事务。若以后增加background/process writer，该writer仍需实际协调；本helper没有给任意并发writer提供锁协议。

## 5. 11 renderer覆盖、配对与presentation合并保持

| 实际renderer | shared renderWidget入口 | 关键确认 |
| --- | --- | --- |
| Calendar | 42 | frame.calendar / frozen height；summary与schedule1 target成对helper；F1为唯一残余live zone读取。 |
| Diary | 36 | 三槽text与各槽ID都从frame prefs；itemIntent无session时读空ID回generic。 |
| Goal | 36 | 同上，保留各密度与空secondary row规则。 |
| Note | 36 | 同上。 |
| Legacy | 46 | 日期header由frame.formatTime；start action fresh gating；不再raw自动开始。 |
| Habit | 36 | quick label / ID / description / URI同frame，fresh且ID非空才挂checkin。 |
| Schedule | renderer内shared入口 | today摘要/三槽/targets均冻结，stale ID置空。 |
| Todo | 44 | title/ID/contentDescription/完成URI同frame，fresh且ID非空才绑定完成动作。 |
| Focus | 39 | wall/elapsed/zone与accepted-only timer effect，详见下一节。 |
| Course | 36 | 三槽text / ID同frame。 |
| Anniversary | 37 | 保留合入display结果的A1/A2/M1/M2/M3 union与paired选项，无A3来源。 |

表中行号是本次只读源码定位。compact / detailed variants继续继承这些renderer，未复制31份逻辑。全源搜索实际`updateAppWidget(`只有Snapshot的统一commit处；没有遗留`forDisplay` /旧`isFresh` /旧`hasPublishedSession`调用。provider render body已没有live getAppWidgetOptions、Date()/Calendar.getInstance()或wall/elapsed采样；HomeWidgetPlugin只用作update入口取得backing与生命周期样式清理。

Calendar / Anniversary的presentation合并内容保持：Calendar独立事件行按matching summary-targethelper绑定；Anniversary union取selectedItems后逐行setText/target，visibility由selected item存在与density决定。Snapshot不再恢复A2/A3旧判空；其optionalRows继续只处理其他family。

Todo helper接收frame，而不是任意SharedPreferences；Habit/Focus/legacy也使用frame型actionUri。`actionUri`要求frame.fresh，day/offset/nonce均来自core原值。未发现A title/ID在重试时补读B nonce或复用第一帧PendingIntent的问题。

其他详情itemIntent的URI permissiveness是原renderer协议，本次只是冻结输入，未扩大为global URI改造；Calendar/Anniversary继续用已合入的严格presentation helper。raw account actionURI的安全性依赖现有Dart消费端校验，本批没有取消旧PendingIntent token。

## 6. Focus、timer/date边界与14101 effect

### 6.1 时间与UI输入冻结

Focus date由frame.formatTime，timer now由frame.wallMillis，base由frame.elapsedMillis与毫秒差计算，不以已截断秒数反推。remaining helper显式接收now；count-up保持完整millisecondbase，展示秒数做安全上限。

Focus Copy的summary/hint新增显式timezone参数，生产调用都传frame.zone；结束时刻HH:mm也用frame.formatTime。Copy保留默认timezone兼容参数，但本次Focus调用未触发默认分支。除了F1 Calendar formatter，没有发现另一处render期间默认zone决定内容。

timerRunning要求有效endsAt或count-up startedAt；live视图受sessionTrusted、running和平台支持控制，no-session的masked compat值不会把旧chronometer启动。paused、expired、无exact权限显示endtime等既有行为保留。

### 6.2 deferred effect与边界顺序

Focus `:198–200`只创建deferred指令，`:285`随BuiltViews返回；构建阶段不schedule/cancel。trusted session时接受后安排running countdown的frozen endsAt或按既有语义取消；untrusted session指令为null，**保留14101**。被拒绝的A帧和commit失败的帧均不执行cancel / schedule，不能覆盖B的timeralarm。

accepted-only effect使用原固定显式immutable token14101与既有exact→inexact fallback。scheduler里在accepted调用期间采当前wall判断是否已到endsAt，是系统effect的时刻检查，不用于生成UI或重新选择payload。未发现它回读账号prefs、修改publication或递归即时广播。

跨midnight / offset时，frame freshness可变stale，而合法published session仍trusted；绝对timer不会仅因daily stale被删除。若day为空 / nonce非法，timer键被mask且alarm保留；系统投递旧14101只沿现有Focus update路径读取当前publication。没有碰日界14102，没有改变day scheduler的时间算术或token。

day / offset与timer expiry在check→Binder调用后的极小窗口仍可能发生，属于原契约明确的系统时钟边界；既有time/day/timer恢复入口补偿。不能声称本次把clock和Binder变成事务。

## 7. 已读19个pure JUnit fixtures与待验收范围

`DuoyiWidgetFrameCoreTest.kt`是已结束但未运行的fixture稿，源码包括19个@Test：immutable map/StringSet、合法session元数据与inclusive offset bounds、nonce不改写、stale trust、midnight、same-offset zone变更、DST、same-tuple raw payload更新、options、system locale、locale解析、正常time增量、clock jumps、countdown expiry、effective mode、首次reject/第二次accept、两次reject、throwing commit不执行effect。

这些fixtures与core公开API吻合，但本审没有编译或执行，不能报告19/19通过。它们没有覆盖下面Android边界：

- FrozenWidgetPreferences全部getter / contains / all / edit与Android接口签名；getStringSet防御性返回。
- RenderFrame.displayValues的no-session全面mask、主题ID保留、canonical locale投影与matching URI真实构造。
- first-pin样式初始化在capture前、11provider / variants实际走shared helper、RemoteViews可见性与主题规格。
- Looper guard、production validation/commit连续路径、AppWidgetManager异常继续处理下一id。
- 真正AlarmManager accepted-only effect、no-session保留14101、拒绝帧不cancelB alarm、exact fallback与14102不冲突。
- held-await/mock MethodChannel及Dart reset已发生但native clear尚未落地的接口边界。
- F1的formatter默认zone与frame zone分离case。

上述需要主审后续安排适当fixtures / mocked integration / platform验收，不应由purecore tests推导成平台成功。本审没有为了覆盖缺口改测试或请求运行。

## 8. 交付仍须保留的明确限制

- Dart reset generation/nonce尚未在native prefs落地时，native frame不能立即感知；只能拒绝**已经生效**的clear/data变化。现有消费端generation/nonce防护继续保留。
- map冻结不是Dart多keypublication transaction。正常push/clear的空day fence受保护；theme-only逐key更新仍可能捕获稳定中间palette，本批没有revision或atomicbatch协议。
- full raw equality拒绝same tuple但内容不同；无法证明数据未曾变更后又全部变回相同。合法账号clear/newsession应更换nonce。
- 已被系统接受的旧RemoteViews不能被这次check撤销；launcher绘制与多widget切换仍可能延迟。clear仍需提交安全替代视图，不能承诺reset瞬间所有桌面画面消失。
- 无额外worker/process writer的main-looper ordering是当前实现前提；future并发写入必须重新协调。
- wall/elapsed容差和最终check后的时间变化无法消除；设备timer/day更新仍best-effort。末尾重试失败不创建新的轮询/后台恢复机制。

## 9. revision1结论与后续最小动作

修复F1 Calendar月标题的显式zone绑定，保持当前frame / masking / commit / alarm设计不变。修改结束后只需对该限定diff复审，并由主审收集核心测试、Android编译及必要集成/设备证据。

在F1修复前，本审不对完整冻结zone契约给出通过；除此之外未发现新的确定must-fix生产缺陷。已经停止生产读取，等待主审完成修订后再作限定复审。

STOP。

## 10. Revision2 — Calendar 冻结 zone 修复与新增 fixtures 的限定复审

主审通知生产再次停止写入后，本审仅只读复审 `DuoyiWidgetCopy.calendarMonthTitle` 的限定修复和新增 `DuoyiFrozenWidgetPreferencesTest.kt`，并读取这两个文件的 SHA-256。没有运行检查、编译或测试，没有扩大生产审阅范围。

### F1 已修复

`DuoyiWidgetCopy.kt:302`（中文）与`:305`（英文）的 SimpleDateFormat 均显式执行 `.apply { timeZone = now.timeZone }`，然后格式化 `now.time`。formatter不再依赖创建时的系统默认zone，月份标题与传入的frame Calendar保持同一zone；原zh/en与compact/noncompact格式不变。第1节的revision1 F1保留为历史证据，**在revision2已经关闭**。

### 新增10个fixture的源码核对

新增fixture `DuoyiFrozenWidgetPreferencesTest.kt:169–186` 使用 `Asia/Shanghai` Calendar、固定instant `2024-02-29T16:30:00Z`，在调用formatter前把默认zone改为 `America/Los_Angeles`。它迭代compact=false/true，分别调用en/zh分支并断言March / 3月，共覆盖四组合；finally恢复原默认zone，避免该fixture完成或失败后污染其他用例。该case针对revision1的真实zone混读，而不是仅测试默认zone与Calendar相同的普通路径。

文件其余fixture覆盖typed getters / contains / all的同一冻结值、类型错误、StringSet不可变与default防御性复制、edit拒绝、fresh projection、stale entity-ID清空而主题ID/locale/mode保留、双语daily文本与counter mask、no-session timer全部读入口不可见、trusted daily stale保留绝对timer字段。源码共10个@Test。

本审只核对fixture输入、断言与清理逻辑；没有编译或运行，不报告10/10或29/29通过。新增fixtures补充了第7节中adapter/projection的源码验收覆盖，provider/Looper/Binder/AlarmManager与真实widget设备边界仍不能由这些fixtures单独证明。

### 文件指纹

| 文件 | SHA-256 |
| --- | --- |
| `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetCopy.kt` | `f8aa96e8c4148c6b67d81d2c062841b44cd100ab07f8d4feda95911f3dc73cbd` |
| `android/app/src/test/java/com/duoyi/duoyi/DuoyiFrozenWidgetPreferencesTest.kt` | `5456304f5326fc2cba2c64166c553aaa95e1448e8aedf829e7532fffdb42ae7b` |

**revision2限定源码复审通过，无剩余must-fix。**结合revision1已审路径，当前没有未关闭的确定生产缺陷；运行与平台验收由主审收集，原第8节的native clear落地、theme多key更新、launcher延迟与时钟末尾窗口等契约限制仍保留。

已完成报告追加并停止生产读取。

STOP。
