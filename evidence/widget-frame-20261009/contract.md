# Android widget snapshot render atomicity contract — 2026-10-09

## 决定、范围与证据边界

采用**逐 widget 冻结的 render frame + 统一提交前校验 + 最多一次重新捕获重绘**。一个 frame 必须同时冻结内容、匹配对象 ID、publication 的 day / offset / account nonce、locale、主题、有效显示密度、尺寸与渲染时钟。任何动作 URI 都由该 frame 的元数据构造。校验失败时丢弃整个 RemoteViews，不能保留旧内容后补读新 nonce，也不能把旧 payload 标记为今天。

这是一份供主审后续实施的契约；本次没有修改仓库、运行 Git、测试、编译、构建或 Flutter 命令。源码来自 `/home/ubuntu/duoyi`，基线 `67b548d` 由主审指定，本审未通过 Git 核验。没有读取进行中的 AGY widget 工作树。另只读检查了已安装依赖 `home_widget 0.7.0+1` 的 Android 插件源码。

前端 Calendar / Anniversary 修改先合入；主审再改这些 provider 的 render 包装、时钟输入和提交点。不得从本基线重新引入 Anniversary A2 / A3 行、旧 Calendar 排版或旧可见性规则。本契约不增加 publication 字段，不改 Dart publication writer，不写 day / offset / nonce，不计算账号业务数据，不启动 Flutter，不执行账号 mutation，不改变已完成的日界调度核心。

**保证须使用准确措辞：**冻结可以保证一个 RemoteViews 内的内容与元数据来自同一份 native map；主线程连续校验与提交可以保证已经在 native prefs 生效的清理先于后续旧 frame 提交时，旧 frame 被拒绝。它不能提供跨 Dart reset 请求、逐 key publication、Android widget service 和 launcher 的完整事务。第 8 节列出这些边界。

## 1. 基线问题与实际提交点

| 源码 | 已确认行为 | 契约要求 |
| --- | --- | --- |
| `DuoyiWidgetSnapshot.kt:16–21` | `isFresh` 每次独立读取时间、默认 zone、day 和 offset。 | freshness 使用 frame 的同一个时间与 zone；提交前另做一次有明确语义的校验。 |
| 同文件 `:24–54` | `forDisplay` 只冻结 fresh / sessionTrusted / isZh；`getString`、`getInt`、`getAll` 仍访问 live backing，其余 getter / contains / edit 全部委托 backing。 | 冻结完整 map，所有读入口仅使用冻结值；禁用通用编辑。 |
| 同文件 `:74–79` | `actionUri` 顺序读取 day / offset / nonce。 | 三个字段来自同一 frame，不能从当前 backing 补字段。 |
| 同文件 `:81–162` | `finishRender` 重新查询 live options，并两次调用 `isFresh`。 | 使用冻结 options 和 frozen freshness；只整理 RemoteViews，不提交、不调度。 |
| `DuoyiWidgetDisplayMode.kt:33–49` | per-widget style 的初始化、修改和删除确实会写 prefs。 | 保留既有受控样式写入，在捕获前使用真实 backing；不要交给冻结 adapter。 |
| `DuoyiWidgetTheme.kt:65–83,340+` | 主题读 string / boolean / int，背景位图规格也读 display mode。 | 所有主题和密度读取使用同一冻结 display map。 |
| `DuoyiTodoWidgetProvider.kt:206–249` | row title 与 ID 分开读取，完成动作附 publication 元数据。 | title、ID、完成 URI 必须同 frame；无安全 ID 时保留通用导航并隐藏完成控制。 |
| `DuoyiHabitWidgetProvider.kt:88–137` | quick label / ID 分开读取，checkin 动作附元数据。 | label、ID、动作同 frame；stale / 无 session 不挂 checkin 动作。 |
| `DuoyiFocusHabitWidgetProvider.kt:88,107–199,293–326` | 日期、remaining、chronometer 使用多次时间采样；compat getter 直接读 `prefs.all`；结束 alarm 在 UI 提交之前修改。 | all 必须冻结；时间统一；alarm 延后到被接受的提交路径。 |
| `DuoyiWidgetProvider.kt:190–195` | legacy 总览直接挂 `duoyi://action/start_pomodoro`，没有 snapshot 元数据。 | fresh 且 session trusted 时挂冻结元数据动作；否则挂通用 Focus 导航。 |

以下 **11 个实际 renderer** 当前都直接调用 `updateAppWidget`，必须全部迁移；其 compact / detailed variants 继承对应 renderer，无需复制 31 份逻辑。

| Provider | forDisplay | finishRender / updateAppWidget |
| --- | --- | --- |
| Calendar | 35 | 141 / 142 |
| Diary | 33 | 140 / 141 |
| Goal | 33 | 144 / 145 |
| Note | 33 | 140 / 141 |
| Legacy `DuoyiWidgetProvider` | 37 | 197 / 198 |
| Habit | 33 | 152 / 153 |
| Schedule | 33 | 155 / 156 |
| Todo | 41 | 201 / 202 |
| FocusHabit | 40 | 284 / 285 |
| Course | 33 | 145 / 146 |
| Anniversary | 33 | 148 / 149 |

表中行号仅为本基线定位，前端合并后会变化。覆盖判断使用类名和实际调用点，不以行号计数。

## 2. 冻结 frame 的最小数据模型

可沿用 `SharedPreferences` 类型以减少 provider 参数改动，但返回值必须是真正的内存只读实现，不能再使用 `SharedPreferences by backing`。建议概念模型如下，具体命名由主审决定：

```text
RenderFrame
  rawValues             deep immutable copy of backing.all
  displayPreferences    typed, immutable presentation projection
  publication           raw day, raw offset, raw nonce from rawValues
  clock                 wallMillis, elapsedRealtimeMillis, zone, localDay, offset
  locale                resolved widget locale + relevant system fallback stamp
  widget                id, relevant frozen options, preferred/effective mode
  sessionTrusted        published-session predicate from rawValues
  fresh                 trusted publication + local day/offset equality
```

### 捕获规则

1. 在 Android 主 looper 上取得真实 backing，先执行既有 `saveForWidgetIfMissing(backing, id, providerStyle)`，再捕获 frame。重试阶段不重复初始化 / 覆盖样式。
2. **一次** `backing.all` 取得 raw map；复制它，深拷贝其中的 StringSet。String、boolean、int、long、float 等 scalar 可直接保留类型和值。捕获 publication 字段也从此 map 取，不能再分别调用 live getter。
3. 捕获一次 wall clock、一次 elapsed realtime 和一次当前 zone（保留该 zone 的固定对象 / ID），以同一个 wall instant 计算 ISO/Gregorian 本地日期与 offset。不能分别用 `Date()`、`Calendar.getInstance()`、`TimeZone.getDefault()` 重新决定日期。
4. 取得该 id 的 options，保存渲染实际用到的 min width / min height 及有影响的 style options；Bundle 不能作为任意 live 可变引用继续传递。推荐保存不可变 scalar 结构。effective mode、Calendar 高度规则与 `finishRender` 全部使用这份结构。
5. 从 raw `widget_locale` 和捕获的系统 locale fallback 一次解析 locale。若原偏好缺失 / 非法，应让 display adapter 暴露捕获时解析得到的 `en` / `zh`，防止 renderer 再次访问变化中的 `Locale.getDefault()`；raw map 保持原值供校验。
6. 一个 widget 从构建到提交使用同一 frame。多个 id 可逐个捕获，各自提交前校验；不能认为一次 provider 广播对全部桌面实例有批量原子性。

### adapter 必须覆盖全部读入口

- `getString`、`getStringSet`、`getInt`、`getLong`、`getFloat`、`getBoolean`、`contains`、`getAll` 全部从冻结 presentation map 读取。
- `getAll` 与 typed getter / contains 必须对 masking 后的字段一致；不能只在 `getAll` 删除 focus timer，却让 `getLong` 仍取到旧值。Focus 的 boolean / int / long compat helpers 必须继续获得它们原来支持的 String / Number 原始类型，不能统一转成字符串。
- StringSet 不共享 backing 或可变返回引用；返回不可变集合或防御性副本。`getAll` 不暴露可修改内部 map。
- typed getter 的类型与 fallback 行为应保持 SharedPreferences 约定，不能静默将所有错误类型转换为另一类型。对 publication 元数据用安全读取 / 类型判断；缺失、非法 day、非法 offset、空 nonce 不作为可操作的 fresh publication。
- `edit()` 显式拒绝调用，不能 silently no-op，也不能代理到 backing。renderer 不需要 listener；不注册 live listeners。现有 style 初始化 / 删除 / resize 写入继续持有真实 backing。
- raw comparison map 和 display map 分离：stale 文案、数字占位、effective mode、locale 归一化与 focus masking 不得回写 raw map，更不能污染提交校验。

## 3. fresh、daily stale 与 no-session 的分工

`sessionTrusted` 表示已有可识别的 published session：day / nonce 非空，元数据格式满足约定。它不等于“今天的数据”。`fresh` 还要求 saved day / offset 与 frame 捕获时的本地 day / offset 相等。**不允许 nonce 为空但 day 恰好为今天的 payload 挂实体 mutation 动作。**

| frame 状态 | Daily 内容 / entity ID | Focus timer | 操作入口 |
| --- | --- | --- | --- |
| Fresh + trusted session | 冻结真实内容与匹配 ID | 使用冻结绝对时间状态 | Todo 完成、Habit checkin、Focus start 使用同 frame 元数据。 |
| Daily stale + trusted session | 既有 stale 文案、数字 `—`、空 entity ID | 仍可显示当前 published session 的跨午夜绝对计时 / 暂停状态 | 通用导航与刷新；不挂过期 daily mutation URI。 |
| Day 为空 / nonce 为空 / 不可信 publication | 安全 stale 占位、空 entity ID | 所有 `focus_timer_*` 在 display map 中不可见；不显示 live chronometer，不沿用旧 paused/running 文案 | 通用导航与刷新；无完成 / checkin / auto-start；**保留现有 14101 alarm**。 |

### stale projection 的两项必要修正

1. **只清实体 ID。**基线 `key.endsWith("_id")` 会同时清空 `widget_theme_brand_id` 和 `widget_theme_card_skin_id`；这些是外观配置。明确列出对象 ID 族（todo / habit quick check / goal / schedule / course / note / diary / anniversary / memorial 的当前已使用字段），不要清主题 ID，也不要清 per-widget display mode。
2. **无 session 时不要暴露中间账号内容。**projection 至少覆盖所有当前 renderer 显示的账号内容、数值、实体 ID 和 timer 字段。沿用合并后已有 stale copy；对未覆盖的业务字段补安全空值 / 通用占位。重点检查 `calendar_month_summary`、`next_focus_label`、辅助统计和可见 secondary rows，不能因 `staleMessage` 未列出某键而读回账号旧数据。主题、有效密度、locale 与通用导航文案可保留冻结外观行为。

Calendar 可按 frame 当前本地日期生成网格 / 月份标题，Focus / legacy header 可按同一个 frame 格式化日期；这类原生日期 presentation 不产生新业务 publication。Anniversary 倒计时 / 排序 / ID 不在原生重新计算。合并后的 Anniversary 行数与 copy 是权威结果；不要以此报告旧表格生成额外 A2 / A3。

## 4. 统一提交校验：不能只比较 day / offset / nonce

每个 renderer 的最终 `updateAppWidget` 改为统一 helper；helper 是唯一获准接受 frame 并提交 RemoteViews 的位置。

### 校验输入与条件

在主 looper 上紧邻提交取得 current raw map / relevant options / current clock stamp，至少检查：

1. **raw publication 相等：**captured day / offset / nonce 与当前值字节 / 类型一致；nonce 只用空白检测判可信，比较时不 trim、不补值、不生成新值。
2. **raw 数据相等：**本批推荐完整 deep raw map structural equality，避免维护遗漏的 render-key 清单。只比较三元组不足：同账号同一天的 push 可先置空 day、更新内容后再发布相同 day / offset / nonce，构成三元组 ABA。即使 tuple 又变回相同，内容 / ID 或主题不同也必须拒绝旧 frame。以后若缩小为 relevant-key projection，必须覆盖全部实际读键和 fallback 键，且有覆盖验收；不能使用 display map 的 stale 值比较。
3. **尺寸 / 密度仍适用：**当前 relevant options 与捕获值一致；存储的 global / instance mode 已在 raw equality 中校验。不得在校验后临时换皮肤或换密度复用旧布局。
4. **时钟域一致：**当前本地 day、UTC offset 和 zone ID 与 frame 捕获值一致。zone 改到相同 offset / day 也需要重捕获，保证 Calendar / 时间格式语义一致。有效 locale / 系统 fallback 也保持一致。
5. **fresh frame 仍 fresh：**原来可操作的 frame 在此刻仍有可信 session，且 publication day / offset 匹配当前本地时间。原本 stale / no-session frame 不因 live 数据后来 fresh 就临时升级；raw equality 失败后必须重新构建。
6. **timer 时间结果仍适用：**正在运行的 countdown 若在构建期间跨过 `endsAt`，拒绝并重捕获为 expired；普通时间流逝不因毫秒变化而每次拒绝。wall 与 elapsed 的增量明显不一致时视为手动时钟调整并重捕获，可采用明确且可测试的约 1 秒容差。容差用于区分连续采样误差与时钟跳变，不用于放宽 day / offset 校验。

完整 map equality 可能因另一个 widget 的 style 写入产生保守拒绝，这在有界重试下可接受。style 初始化必须先完成，避免 provider 自己必然使第一帧失效。不要使用不稳定 hash 作为唯一相等判断。

### 执行顺序

```text
真实 backing：初始化既有样式
attempt 1:
  捕获 frame → 使用 frame 构建完整 RemoteViews → finishRender(frame)
  主线程：validate(frame) → 若通过立即 updateAppWidget(id, views)
  若成功，执行该 frame 获准的 deferred timer-alarm effect
若 validate 失败:
  丢弃 views 和所有未执行 effect
attempt 2（最多一次重新捕获）:
  用最新 frame 从头构建并校验 / 提交
再次失败:
  不提交，不执行旧 effect，结束本 id；继续其他 id
```

- 最多两次 build；不用无限循环，不递归调用 provider，不在失败时立即广播 `APPWIDGET_UPDATE` / `requestUpdateForAllWidgets`。重试发生在当前调用内，直接重新捕获构建。
- 第二次捕获为稳定 daily stale / no-session 时，可提交它完整构建的安全占位。不是把第一份 views 清几行、补读当前 nonce 后提交。
- 第二次仍变化则不做第三次 fallback commit；保留 launcher 当前状态，由既有 publication / clear 刷新、options / 时间广播、日界 alarm 或系统周期刷新恢复。只记录不含内容 / nonce 的 reason 与 widget id。
- `updateAppWidget` 抛 RuntimeException 时，本次不算成功，不执行 deferred effect，不重复提交相同 RemoteViews；短日志后结束该 id，避免阻断余下 widgets。不得把 binder 失败转为账号 publication 写入。
- helper 不向外提供“校验通过”的长期 token，也不允许调用者校验后 await / post / 切线程再提交。校验和实际提交之间不得有用户 callback、prefs 写入或可重入异步操作。

## 5. 样式、主题与 PendingIntent 的保留规则

### 样式写入与渲染读取分离

保留 `saveForWidget`、`saveForWidgetIfMissing`、`clearForWidget` 在 pin / resize / 删除的既有职责。provider 第一 pin 的默认密度必须在 freeze 前用真实 backing 初始化；“冻结 adapter 的 edit 抛错，然后忽略初始化失败”不是兼容方案。

有效密度继续遵守用户所选上限：小于 180×100 dp 或用户 compact 时 compact；只有用户 detailed 且至少 250×170 dp 时 detailed；其余 standard；无有效尺寸时沿用偏好。以合并后的 UI 规则为准保留其他 family 高度阈值。主题 bitmap 尺寸、可见行数、bottom nav、`finishRender` 必须使用同一个有效 mode / frozen options，不能各自重新读取。

主题 string / boolean / int、brand / skin ID、背景 asset 与颜色全部来自 frame。允许纯 bitmap cache / drawable 构建；缓存 key 要包含既有渲染规格，不带账号内容。主题 renderer 不因此获得 payload editor。

### 动作 URI 与 token

`actionUri` 应接收 frame / frozen publication，而非允许任意 live prefs。ID、title、accessibility 文案与 URI 都在一个 frame 中绑定。提交失败时不把生成的旧动作挂到新 frame；每次重试重新构造完整 views。

安装依赖的 `HomeWidgetIntent.kt:13–44` 使用显式 MainActivity、`Intent.data = uri`、requestCode=0 与 `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`。URI 的 ID / day / offset / nonce 均参与 PendingIntent 身份，因此新 nonce 会产生不同 token，而不会更新旧 nonce URI token。创建旧 token 本身不会启动 Activity / Flutter，也不是账号 mutation。

本批可以继续在构建阶段创建这些 URI 唯一的 activity tokens：

- 必须把全部账号绑定信息放在冻结 URI 的 data 中，不能改为仅放 extras 并以相同 data + FLAG_UPDATE_CURRENT 改写已显示 token 的账号信息。
- 通用 tab / refresh tokens 不携带账号 ID / nonce，保持既有导航行为；不要在 token extras 添加 frame 账号状态。
- 不主动取消丢弃 frame 的 token：同一 token 可能仍被桌面旧视图引用。点击时由现有 Dart 消费端校验账号 / day / offset。
- fresh + trusted 才为 legacy auto-start、Focus auto-start、Todo 完成、Habit checkin 创建并绑定可执行 mutation URI。daily stale / no-session 改挂通用目标页。旧 legacy raw start URI 必须迁移，不能因它没有实体 ID 就绕过 stale 门槛。
- Todo `quick_todo` 是新建编辑页入口，没有冻结实体 ID；保持该导航功能。不能把编辑页入口当作原生执行创建任务。

## 6. Focus 专项：同一时钟、无 session 屏蔽与延后 alarm

### 时间计算

Focus helper 不再自行调用 `System.currentTimeMillis()`；date header、expired 判断、remaining、count-up elapsed、结束时刻格式与 chronometer base 使用 frame 捕获的 wall / elapsed / zone / locale。

```text
countdown baseElapsed = capturedElapsed + (endsAt - capturedWall)
count-up baseElapsed  = capturedElapsed - max(0, capturedWall - startedAt)
remaining display    = max(0, endsAt - capturedWall), 按现有单位 / 上限处理
```

chronometer 用准确毫秒差做 base，不以已截断的秒数反推 base。paused timer 使用冻结 stored remaining，不启动 chronometer；无可信 session 时 chronometer 停止 / 隐藏，timer 文案为通用占位，compat getters 也看不到旧 timer 数据。

保持既有平台语义：count-up 支持、API 24+ countdown chronometer、无法 exact 时显示结束时刻、运行 / 暂停 / expired 可见性规则均保留。影响显示的 capability 在 frame 构建时一致使用；实际调度仍处理权限变化与原有 inexact fallback。

### alarm effect

基线在 `:198–199` 提交前调用 `scheduleTimerFinish`。改为构建一个 deferred 指令，只有该 frame 校验通过且 `updateAppWidget` 调用成功返回后，在同一主线程连续段执行：

- trusted session 且有效 running countdown：安排该 frozen `endsAt`。
- trusted session 且暂停 / 停止 / 已结束 / count-up：按既有逻辑取消 14101。
- **no-session / invalidated day：无指令，保留现有 alarm。**不能用 masking 后的 running=false / endsAt=0 取消真实旧 alarm。
- validate 失败 / build 失败 / UI commit 抛错：无指令；不能由被拒绝的 A frame 替换 B 的 timer alarm。
- 使用原显式 immutable token **14101** 与既有 exact / inexact fallback，不新建每账号 token、不写 prefs、不碰日界 token **14102**。多个成功的 Focus 实例重复安排同一 frozen endsAt 可以保持幂等，避免每个实例增加不同 alarm。
- 调度是单独系统调用，不能和 widget Binder commit 宣称为一个事务。调度失败不回滚已提交 UI，也不反复广播重试；记录安全日志，沿用既有恢复入口。

daily stale 并不抹掉一个可信 published session 的绝对 timer；跨午夜 / offset 变化时 timer 继续按绝对 instant 计时。日界调度只触发读取当前 frame，不写 timer，不接管 14101。

## 7. 最小迁移范围与实施顺序

| 文件 / 位置 | 最小职责 |
| --- | --- |
| `DuoyiWidgetSnapshot.kt` | immutable raw / display snapshot，publication / time predicates，明确 entity-ID masking；frame 型 `actionUri` / `finishRender`；统一有界 capture-build-validate-commit helper。也可将 helper / data class 分到一个小 native 文件。 |
| 11 个实际 provider | backing 与 display 变量分离；style init 在 freeze 前；render body 进入 frame builder；取消直接 UI commit；fallback、主题、动作都读 frame。variants 继续继承。 |
| Focus provider | compat all 读取冻结值、统一时间参数、deferred 14101 effect、fresh action gating。 |
| Legacy provider | date header 使用 frame、raw auto-start URI 迁移、统一提交。 |
| Calendar provider | 前端合并后只迁移时间 / options 输入与提交 wrapper，保留已合入排版。 |
| Anniversary provider / Snapshot optional rows | 前端合并后保留实际行结构，不恢复本基线 A2 / A3 helper。 |

正常情况下无需改 `DuoyiWidgetDisplayMode` 的存储协议、`DuoyiWidgetTheme` 的 palette 算法、Dart writer、registry / restore、manifest、day-boundary scheduler。若需要小参数改动，使 helper 接收冻结 options / clock，限定为数据来源迁移。

建议顺序：先实现纯 frame / adapter / predicates，再 shared commit helper，再所有 providers 与 Focus / legacy 特例，最后静态搜索确认无遗漏的 live reads / direct commit。此报告仅定义将来的验收，不授权本审运行这些命令。

## 8. 线程证据、check→commit 边界与不能承诺的事项

### 现有 native 顺序可使用，但必须保留

已安装 `HomeWidgetPlugin.kt:34–36` 以默认 `MethodChannel(binaryMessenger, "home_widget")` 注册 handler，没有 background task queue；`saveWidgetData:47–79` 在 handler 内完成 `Editor.commit()` 才返回。当前 provider `onUpdate` 是同步 AppWidgetProvider callback；manifest 未指定 widget 独立 process；没有 goAsync / worker render。Dart 的 `Future.wait` 并不使这些 native handler 同时执行。

因此当前 native 写入与 provider render 在同一主 looper 排序。必须让 final validate 和 `updateAppWidget` 保持同一连续 main-looper segment。若将来把渲染移到 worker：可在 worker 构建 immutable views，但最终 validation + commit + deferred accepted effect 必须回到主线程作为一个闭包；不能只做 mutex，因为当前插件 writer 并不获取新 mutex。若出现其他线程 / process 的 prefs writer，需要全部参与真实 writer/commit 协调，现有 before-commit predicate 本身不解决该并发模型。

### 明确保留的限制

1. **Dart reset 请求并非已落地的 native clear。**`resetAccountCache` 立即改 Dart generation / nonce，但 clear 是排队异步执行，并在 init 后才先写空 day。native frame 看不到尚未到达插件的 Dart generation 变化。清理请求之后、native invalidation 之前，A frame 仍可能通过。已有消费端 generation / nonce 校验降低旧动作风险；若要求 reset 请求瞬间禁止 native commit，需要新增有序 native invalidation / generation 协议，超出本次不改 publication writer 的范围。
2. **已落地的 native invalidation 可以拒绝旧 frame。**空 day / 新 nonce / 新 raw 内容在 final check 前已经可见时，A 不得再提交。相同主线程连续段避免普通 handler 在 check 与 Binder invocation 之间插入清理。但清理发生在 UI 已提交之后，不能撤销那次已接受调用；clear 必须通过既有 refresh 提交安全替代视图。
3. **Launcher 不参加账号事务。**`updateAppWidget` 返回表示系统调用接受 / 完成，不表示 launcher 已绘制。旧 views 可在清理前已被系统接受、在清理后仍短时可见；不会因 immutable frame 自动擦除。不能承诺所有 31 个 component 同时切换、OEM 无延迟或已有旧画面立即消失。
4. **冻结 map 不是多 key publication 事务。**正常 push / clear 先清空 day、最后发布 day，frame 可拒绝 / mask 中间内容；但是 `updateTheme:252–278` 逐 key 保存 palette 时不清空 day。某个中间 palette 可能在 capture 与 check 时都稳定，于是通过。这份改动保证一帧使用同一份 palette map，不保证该 map 是一整个逻辑主题版本。要保证完整主题 transaction，须另做 atomic native batch / producer revision 等协议，本批不做、不夸大。
5. **ABA 与不可见历史。**full raw equality 能拒绝相同 tuple 下不同 payload；不能证明捕获后从未发生过“变了再全部变回相同”。账号 clear 应更换 nonce，已落地后的新账号不能复用旧 nonce。若 writer 违反该协议，读取端无持久 revision 无法恢复丢失的历史。
6. **真实时间变化仍有末尾窗口。**day / offset / zone / timer-expiry check 之后，时钟仍可跨界或被系统修改；无法与 wall clock 建事务。日界 / 时间广播 / timer alarm 负责补偿重绘。1 秒 skew 容差也意味着同日同 offset 的亚秒跳变可能不触发重试；不能宣称时钟绝对原子。
7. **清理 / publication 失败和进程死亡。**day 为空的持久状态应继续显示 no-session 安全占位，不帮 producer 补 day；已有 alarm 和系统 refresh 是 best-effort。达到重试上限后不制造新恢复机制 / 后台循环。

## 9. 规定的验收 case（仅计划，未执行）

### A. immutable adapter 与一致绑定的 unit / fake-prefs case

- 捕获 A 的 title、ID、day、offset、nonce 后，修改 backing 为 B；A 的全部 getter / getAll / contains 仍只看到 A 或其冻结 stale projection。其 action URI 仍是 A 的 ID + A 的元数据；绝不能得到 A ID + B nonce。
- StringSet 在 backing / 调用者端被改动不改变 frame；验证所有 boolean / int / long / float getter，尤其 theme dark 与 timer compat String / Number 类型。
- 用 fake SharedPreferences 记录读取次数：捕获只读一次 all；build 期间无 backing getter；final validation 允许独立一次 current map 读取。adapter edit 必须拒绝，正常 first-pin style 初始化仍成功且在 capture 前。
- 主题 brand / skin `_id` 在 daily stale 时保持；实体 ID 被清空。stale 时数字 `—`、当前 row 可见性、语言、主题位图规格与 effective mode 保持一致。无 session 所有 timer 读入口都看不到旧值。

### B. native held-build / mock-commit case

- 捕获 A 后暂停 builder，在 fake store 写空 day / B nonce / B payload，再恢复：A commit sink 调用次数为 0；第二次只能提交完整 B 或安全 stale。
- 同账号同 day / offset / nonce 发布不同 title / ID；tuple ABA 相同但 raw map 不同：A 被拒绝，证明不能只检查三元组。
- 在 build 中改主题、global mode、该 id instance mode或 relevant widget options：整帧拒绝；重试内容、bitmap 规格、密度与 finishRender 尺寸均来自新 frame。
- 两次捕获都发生变化：最多两次 build，0 次不合法提交，0 次 deferred alarm，0 次 retry broadcast，0 次 payload write；其他 widget id 仍继续处理。
- commit fake 抛 RuntimeException：不执行 timer effect，不立即重播，不终止整个 id 批次。成功 commit 后 effect 才调用一次。
- production guard 要求主 looper；将 validation 与 commit 人为拆开并让 fake 在间隙写 clear，应能展示漏洞。该负例防止把一次 boolean check 宣称为跨线程事务。最终 main-looper闭包内不可插入异步点。

### C. clock / offset / timer case

- capture 在 midnight 前、commit 在后；同一天 DST / 非整小时 offset transition；zone 改到相同 day / offset；Calendar 月底 / 跨年：第一次拒绝，第二次用新 local date / zone。不能保存新 day / offset。
- wall clock 同日跳前 / 跳后，elapsed 连续；用固定 tolerance fixture 验证 skew 判断。普通 200ms 渲染流逝不应每次失效；offset / day 改变始终拒绝，不受 tolerance 放宽。
- running countdown build 时跨 endsAt：重捕获 expired；count-up 与 paused 正常保持；chronometer base 与 frame wall / elapsed一致，helper 不二次采时。
- day stale 但 session trusted 的跨午夜 timer 继续；no-session 携带历史 running / paused / endsAt raw 数据时，UI 占位、无 live timer / mutation URI、14101 完全不被取消 / 重排。
- A frame 原计划 cancel 14101，在 build 间隙 B 发布 running timer：A 的 cancel 不执行；B accepted frame 按 B endsAt 调度。拒绝 UI frame 不得改变 alarm。
- 验证 14101 与日界 14102 身份不冲突，既有 exact / inexact 降级保留；无新增 exact 权限或 Flutter 调用。

### D. Dart held-await / mocked MethodChannel 交互 case

这些用例验证既有 producer / consumer fence 与 native frame契约的接口，不要求本批重写 Dart：

- 用可控 Completer 持住 `init` / nonce read、某次 saveWidgetData 或最后发布 day，触发 account reset，再放行旧 push：旧 generation 不得重新发布 A nonce / fresh day；queued clear 最终空 day / 新 nonce，之后才允许新账号 publication。
- 把 mock plugin store 的 native apply 时刻与 Dart Future 完成时刻分开：native 已写空 day但 await 未返回时，A frame 必须被拒绝；仅 Dart reset 而 native invalidation 尚未到达时，明确验证不能承诺 native 已拒绝，同时旧 bound action 在消费端被 generation / nonce 拒绝。
- 持住 hydration / action validation await，期间 clear / 切号：恢复后 A 的完成 / checkin / start 动作不作用到 B；`_handleBoundWidgetAction` 在 `main.dart:4246–4270` 的 generation 与上下文检查仍保留。nonce 重绑定不是通过新 frame 本地修复旧 URI。
- 原生 stale 重绘 / retry 不调用 saveWidgetData、不启动 engine、不发送 background mutation；刷新按钮点击后才沿既有用户操作路径进入应用。
- theme-only saves 用可控逐 key await 展示中间 map 的残余限制，避免测试只比较最终 palette 就声称逻辑主题 transaction 已实现。

### E. 合并后的静态范围核对

- 11 个实际 renderer、31 个既有 component 的继承覆盖全部到 shared helper；没有漏掉 legacy 或 variant。
- provider render body 无 live `HomeWidgetPlugin.getData` getter、无 direct `updateAppWidget`，仅 shared commit helper 调用实际提交；style / delete / options lifecycle 的 backing 写入仍存在。
- Calendar / Focus / legacy 无独立 `Date()` / `Calendar.getInstance()` / remaining helper 自行采时；`finishRender` 无 live options / freshness 重采。
- PendingIntent metadata 全部 frozen；legacy raw auto-start 已消除；safe stale 不绑定 mutation；Focus alarm 不在 build 阶段执行。
- 合入前端 Calendar / Anniversary 结果后再检查，不恢复 Anniversary A2 / A3；无 Dart publication 字段、manifest / scheduler 扩散，无递归即时广播。

## 10. 可接受的交付表述

完成实施并取得上述证据后，可以报告：“Android widget 每次渲染使用同一份不可变 native snapshot，动作 ID 与 publication 元数据一致；最终提交前拒绝已改变的 payload / 已落地的账号清理 / 日期时区或尺寸变化，并进行最多一次只读重绘。”

不能报告：“账号 reset 瞬间桌面已原子清空”、“所有主题多键更新已是事务”、“launcher 完全不存在旧图窗口”、“清理前提交的旧 UI 已被撤销”或“时钟与 Binder commit 严格原子”。这些需要额外 producer / platform 协议，不能由冻结 map 与一次 before-commit check 推导。
