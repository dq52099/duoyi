# WidgetPublication 原生存储实现图

日期：2026-10-09。范围：`/home/ubuntu/duoyi-worktrees/widget-publication-20261009`。

本文件是后续实现的接入方案，不是已落地或已验收声明。本轮仅定向读取现有原生 bridge、reader 和平台配置；未修改生产/测试源码，未运行 Git、SDK、构建、检查、测试或网络请求。未读取 `widget_publication.dart` 或 Luna 的 fixtures。

沿用 `widget-publication-wire-schema-audit-oct9.md` 的 envelope、native epoch/lease、CAS、presentation floor 和 receipt 契约；不重新讨论 DTO schema。

## 1. 存储决定

**两平台使用 SQLite 单行保存完整 native envelope；SQLite 事务负责原子提交，固定锁文件负责一次操作从 CAS 到提交后读回的完整串行边界。**

| 项目 | 决定 |
| --- | --- |
| 权威数据 | `duoyi_widget_store_v1.sqlite` 中 singleton row 的完整 envelope BLOB。binding、epoch、lease/state、storeRevision、desired presentation floor、document、最后 receipt 一次提交。 |
| 事务 | Android `SQLiteDatabase.beginTransaction()` 的 EXCLUSIVE 事务；iOS `BEGIN IMMEDIATE`。先锁、重新读当前 envelope、严格 decode、CAS，然后 UPDATE；initialize 的 schema/首个 envelope 在同一个事务内建立。 |
| journal | 显式 `journal_mode=PERSIST`；不启用 WAL。PERSIST 保留 journal inode，避免把每次提交确认建立在删除 journal 文件上。journal 也是账号数据，应与 DB 一起保护、排除备份。 |
| 同步 | 每个可写连接确认 `synchronous=FULL`；iOS 再确认 `fullfsync=ON`，使用系统 SQLite 的 Darwin VFS 同步路径。不能忽略 PRAGMA 返回值或依赖默认设置。 |
| 操作锁 | 同目录固定 `duoyi_widget_store_v1.lock`；Android 所有参与者用 `FileChannel` 文件锁，iOS 所有参与者用 POSIX `flock`。锁文件永不替换/删除，不锁会被替换的数据 inode。 |
| 进程内协调 | 每个进程一个 store coordinator；所有读、写、读回及 Android 最终 UI 校验先取得同一个进程内 gate，再取得文件锁，最后进入 SQLite。禁止反向锁顺序和持锁回调 reentry。 |
| 协作规则 | 普通读取持共享文件锁，mutation 持独占文件锁。独占锁保持到 COMMIT、关闭提交连接、新连接读回、结果封装结束。SQLite 自身锁仍负责数据库事务和异常退出恢复。 |

固定操作锁是必要的补充：SQLite 的 COMMIT 会释放事务写锁；单靠该锁不能保证“COMMIT 后的新连接读回”之前没有另一个 writer 覆盖最后 receipt，也不能覆盖 Android 校验后的 `updateAppWidget` 调用。所有 app-owned writer 必须使用同一 coordinator/锁协议。

这不是 SharedPreferences/UserDefaults 的新 key 包装。其 setter、进程缓存、compatibility mirror 都不是权威提交确认来源；不修改 pub-cache。

### 平台支持边界

- Android 的 SQLiteDatabase 事务、FileChannel 文件锁和 Java gate 不要求引入新版 Jetpack 存储库。现有 `minSdk = flutter.minSdkVersion`，**数值尚未确定**；不能据本轮源读取宣称某个具体最低 Android 版本。PERSIST/FULL 的实际 SQLite 支持与有效配置须在接入证据中确认，拒绝静默降级 journal/sync 模式。
- iOS Runner/project 为 13.0，Widget extension 三种配置均为 14.0；系统 SQLite3、Foundation、POSIX lock 均适用于这些部署目标。extension 当前 `APPLICATION_EXTENSION_API_ONLY = YES`。
- SQLite 成功 COMMIT 配合有效同步配置，是事务 durability 的依据。读回校验的是持久化接口可见的精确内容；即使换连接，读回也不能单独证明物理介质已抗掉电。保证仍以 OS/VFS/存储设备正确履行同步为前提。

## 2. 文件布局与初始化

### Android

- 使用 app-private 的 `widget_publication_store/` 目录；若确定 minSdk ≥21，放入 `Context.noBackupFilesDir`。数值未确定前，方案可用版本分支：≥21 使用 no-backup 目录，更低版本使用 `Context.getDir(..., MODE_PRIVATE)`，并为该目录配置备份排除；不得无保护地把 binding/lease 随备份恢复。
- 同一目录存放 DB、journal、固定 lock。widget receivers/restore 与 Activity 都使用 `applicationContext` 和相同规范路径，不从 Activity 生命周期持有 store。
- 源 main/debug/profile manifest 及 home_widget plugin manifest 没有 `android:process` / `directBootAware` 声明；当前源配置是默认 app 进程和凭据加密存储。这里只是源证据，最终 merged manifest 的结果尚未获取。
- 源 application 没有显式 `allowBackup`、`fullBackupContent`、`dataExtractionRules`。低版本 fallback 的备份排除是实际接入工作，不能据本轮称已配置。合并后出现远程进程时，必须让其也使用同一路径/锁协议；出现 direct boot reader 时，不得改成读取旧 mirror。

### iOS

- 用 `FileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.duoyi.duoyi")` 取得容器，在其中建立专属 `Library/Application Support/WidgetPublicationStore/`。不能拼接普通 Runner sandbox 路径。
- Runner 和 DuoyiWidgets 的 entitlements 均已有该 App Group。DB、journal、lock 使用一致的 file protection；建议 `completeUntilFirstUserAuthentication`，首次解锁后允许 extension 读取。
- host initialize 时设置并确认专属目录/文件的 protection 和 `isExcludedFromBackup`；排除整目录，包含残留 journal 和锁。首次解锁前、App Group 不可用或保护设置失败，返回 unavailable/未确认；不改用 UserDefaults 账号数据。
- extension 只读现存 store，不建 schema、不发 epoch/lease、不创建新权威数据。gallery locale 也从同一经过验证的 store/presentation 路径读取；失败时仅使用静态/system-locale 的无账号占位文案。

### 不把“不存在”和“打不开”合并

1. 只有确定权威 DB 路径不存在，才能返回 `absent`。一个无锁的 absence 观察可能随后过时；initialize 必须在独占操作锁内重新核实不存在，防止与另一 initialize 竞争。
2. 目录/锁由 explicit initialize 创建。已有 DB 却缺失固定锁，不能临时换新锁继续操作；返回未确认并进入显式恢复。
3. 已有空 DB、缺 singleton/table、坏 envelope、`SQLITE_NOTADB/CORRUPT` 都不是首次初始化许可。禁止 SQLiteOpenHelper 的 drop/recreate、删库或自动 defaults 修复。
4. SQLite DB schema version 与 envelope protocol version 都严格检查；未知版本返回 unsupported，不自动 destructive migration。
5. 首次 initialize 在 SQLite 建立事务前可能已产生 DB 文件。此时 crash 可留下空文件；随后 fail closed，显式恢复。这是有意保留的失败状态，不能为方便初始化而把空文件判 absent。
6. 正常 rollback-journal crash recovery 由 SQLite 完成，不是重设 owner。host 在操作锁内以现存 READWRITE DB 打开/恢复后，必须重新验证 envelope。只读 extension 若无法执行 hot-journal recovery，则返回暂不可用，等 host 恢复；不创建副本或恢复旧 prefs。

## 3. 一次 mutation 的完整顺序

所有批准的 mutation 共用下面路径：`openWidgetWorkspace`、`invalidateWidgetWorkspace`、`advanceDesiredWidgetPresentation`、`publishWidgetPublication`。

1. 在 bridge 解析协议/operationId/requestDigest，校验类型和请求结构。把不可变请求送入后台 store coordinator；不读取 live Flutter provider，不根据 Dart document 授予 epoch。
2. 获取进程 gate、独占固定文件锁。打开现存 DB（只有确认为 absent 的 initialize 可 CREATE），确认 schema/journal/sync 模式；开启事务。
3. 从 singleton 严格读取 envelope。先检查同 operationId 的最后 receipt：digest 相同则返回原提交的 `alreadyApplied`，不重做 CAS、轮换 epoch或增加 revision；同 ID 不同请求拒绝。
4. 未命中 receipt 时，再执行 expected storeRevision/epoch/lease、binding、publicationRevision 和完整 presentation floor 的校验。读取 API 不授予 writer lease。
5. 仅 native 的 open/invalidating transition 生成 opaque epoch/lease；正常 resume 保留 epoch并发新 lease；reset/relogin 轮换 epoch。清理时 tombstone、sealed、撤销 binding/lease 和 receipt 一次写入。presentation floor 不因账号切换归零。
6. 将新完整 envelope 与 receipt 写入同一 singleton transaction；COMMIT。Android 必须等 `endTransaction()` 真正结束：`setTransactionSuccessful()` 只是标记，不是 ack。iOS 必须检查 `sqlite3_step/exec(COMMIT)` 的实际结果。
7. 仍持独占操作锁，关闭提交连接，以新连接/新 transaction 读取 singleton（不从进程 cache/旧 transaction 读取）。严格 decode，并核对 operationId、requestDigest、committedStoreRevision、epoch/lease/state、document publication revision 和 desired/applied presentation。精确 bytes 或等价的严格 envelope 内容必须与提交值一致。
8. 只有 COMMIT 成功且读回吻合，才封装 `applied`；命中旧 durable receipt 返回 `alreadyApplied`。随后释放 SQL/文件锁/gate，再把结果投递到 Flutter messenger 所需线程。

原生 receipt 是提交的一部分；channel result 不参与事务。Dart 接受 ack 前仍须核验当前 account generation、writer lease 和 desired presentation，旧 ack 不能改写新会话缓存。

### 失败及 ack 丢失

| 情况 | 行为 |
| --- | --- |
| parse/CAS/owner/presentation 不通过，尚未写入 | 返回对应 invalid/conflict/mismatch/superseded；不改 DB、不发刷新/告警效果。 |
| gate/file lock/SQLite 在开始 mutation 前 busy | 有限等待或返回 transient busy；不把它判 absent，不无限阻塞 UI/extension。 |
| schema/envelope corrupt 或 unsupported | fail closed；不写替代 tombstone，不回退 legacy，不通过 open 偷换新 epoch。 |
| COMMIT IO 错误、COMMIT 成功但读回错误/不符 | `durabilityUnknown`。不发 applied，不推进 Dart cache；当前进程 quarantine 写能力，不继续使用旧 lease 提交或声称自动回滚。 |
| 提交/读回已成功，channel ack 丢失或 engine 被销毁 | 存储仍有效。相同 operationId/digest 重试读取 receipt 得到 alreadyApplied；不重复存储 mutation/副作用。 |
| 最后 receipt 已被另一合法操作替换 | 旧 retry 返回 conflict/unknown；不能通过换最新 expected revision 重放旧内容。本方案不承诺无限 receipt 历史。 |
| crash 在 COMMIT 前/后 | SQLite 恢复给出完整旧/新 envelope；恢复后仍需严格验证。不能用“crash occurred”推导已提交或未提交。 |

`durabilityUnknown` 不能用简单重复写相同值清除。后续恢复必须在操作锁内重新打开现存 DB、完成 SQLite recovery、验证完整 envelope；若要重新证明当前内容的同步提交，需明确恢复 transaction 的成功 COMMIT 与新连接读回，并记录恢复 receipt、撤销/更换 writer capability。恢复请求必须携带当前已验证 workspace/presentation context；无法证明时维持 blocked，不覆盖损坏/未来版本 store。进程重启本身不是内容身份校验或 durability 恢复证明。

## 4. Android 接入位置与渲染边界

现有入口与新增文件均属于 `android/app/src/main/kotlin/com/duoyi/duoyi/`。

| 文件/位置 | 后续职责 |
| --- | --- |
| `MainActivity.kt:119` 的 `configureFlutterEngine`；`:440` 的 `duoyi/widgets` handler | 注册 app-owned publication bridge。现有 channel 可加入批准的五个 API；存储工作使用 applicationContext/coordinator，结果返回原 engine。Activity 销毁不撤销已提交事务。 |
| 新 `DuoyiWidgetPublicationBridge.kt` | MethodChannel 参数/结果适配、后台任务和 messenger lifecycle；不拥有数据库权威缓存。 |
| 新 `DuoyiWidgetPublicationStore.kt` | 路径、进程 gate、固定文件锁、SQLite 配置/事务、CAS、native token、receipt、读状态、quarantine。没有依赖 Activity 的静态引用。 |
| 新 `DuoyiWidgetPublicationEnvelope.kt` / decoder | 严格 envelope/document decode 与 typed flat projection；沿用已批准的 Int/Long 分类。不得把所有 JSON Number 转 Double/Long 后交给现有 getInt。 |
| `DuoyiWidgetSnapshot.kt:30` capture；`:57` revalidation | 用 store snapshot/token 取代 `backing.all` 的账号/主题/locale 来源；保留独立 per-widget display mode、options、clock/system locale。 |
| `DuoyiWidgetFrameCore.kt`、`DuoyiWidgetRenderFrame.kt`、`DuoyiFrozenWidgetPreferences.kt` | frame 携带 canonical storeRevision/epoch/document/presentation 状态及不可变投影；frozen prefs 继续适配现有 provider。不得从 legacy account keys 填缺项。 |
| `MainActivity.kt:470` 的 `refreshAllWidgets`、registry/restore receiver | 发更新请求/恢复 provider，读取已确认 canonical；不得在 restore 中合成 publication、owner或 lease。 |

### 写入移到后台后，保留最终接受顺序

当前 `DuoyiWidgetSnapshot.renderWidget` 在同一主线程段 capture/build/revalidate/`updateAppWidget`，效果在 UI 接受后运行；仅保留 main-looper 断言已不足以阻止后台 store writer。

具体替换方式：

1. capture 取得一个严格 verified envelope 和独立 widget style/options；build 沿用其 immutable projection。build 可以不持存储锁。
2. 最终接受段在 main looper **非阻塞尝试**获取进程 gate与共享文件锁；拿不到则 reject/安排后续更新，禁止等待后台长事务导致 main thread 长时间阻塞。
3. 持锁读取 fresh canonical，核对 captured storeRevision/epoch/leaseState/document revision/presentation context，再执行既有 clock/offset/options/system locale/style/expiry 检查。对于 sealed/cleared/unavailable，只有无账号的适当 frame 可接受。
4. 共享锁与 gate 保持到 `manager.updateAppWidget` 成功返回。所有 writer 必须先取得该 gate/独占文件锁，因此不能在最后检查和 UI 提交间改变 canonical。
5. 同步 accepted alarm/refresh effect 在该接受顺序内执行；不得 reenter store mutation。如果 effect 实际异步排队，执行时再次在 gate/文件锁下校验捕获的 epoch/store/effect context；不要仅因 enqueue 时通过而晚到执行。
6. 失败 build/Binder/revalidation 不执行 accepted effect。保持现有有限 recapture/rebuild 行为，不把 corrupt/unavailable 转成 legacy frame。

main 接受段只能做短读取/校验及现有 UI 调用；SQL busy timeout 和文件锁均使用非阻塞/有限策略。进程 gate 必须先于 SQLite，避免 worker 持 SQL 锁等待 main gate，而 main 又持 gate 等 SQL 的死锁。

任何账户 invalidate/open/presentation mutation 的刷新和 alarm reconcile 都必须排在 durable canonical commit 后。mutation 的 alreadyApplied 分支不再发布副作用；单独的刷新重试必须注明要刷新的已提交 revision 并重新检查当前状态。storeRevision、每个 widget effect context 和确定性 alarm identity 应用于去重/替换；不能承诺 SQLite 与 AlarmManager 的跨系统 exactly-once。

## 5. iOS host/extension 接入位置

| 文件/位置 | 后续职责 |
| --- | --- |
| `ios/Runner/AppDelegate.swift:92` 的 `didInitializeImplicitFlutterEngine` | 当前只调用 GeneratedPluginRegistrant；在该 engine 的 plugin registry/messenger 上注册 publication bridge，不能只依赖 didFinishLaunching 时的 root controller。建议 host bridge 实现 FlutterPlugin，由该 registry 的 registrar 获取 messenger并按 engine 注册一次。 |
| 新 `ios/Runner/DuoyiWidgetPublicationBridge.swift` | 仅 Runner target；Flutter 方法适配、后台 serial store operation、main/messenger 回调及已提交后的 WidgetCenter reload 请求。 |
| 新 `ios/WidgetPublicationShared/DuoyiWidgetPublicationStore.swift` | Runner + DuoyiWidgets targets；App Group path、SQLite3、固定 flock、严格 read result。共享核心提供存储操作，但 extension 入口仅调用只读方法，不授予 writer capability。 |
| 新 `ios/WidgetPublicationShared/DuoyiWidgetPublicationEnvelope.swift` | 两 target；纯 Foundation/CoreFoundation 的严格 envelope/document decoder、typed projection。排除 NSNumber Boolean 当数字，不通过 Double 损失整数精度。 |
| `ios/Runner.xcodeproj/project.pbxproj:346`、`:356` Sources | 两个 shared 文件均加到 Runner 和 DuoyiWidgets source phase；bridge 仅 Runner。两 target 显式链接系统 `libsqlite3.tbd`/SQLite3 module；不把 Flutter/UIKit host code 链入 extension。 |
| `ios/DuoyiWidgets/DuoyiWidgets.swift:1221`、`:1238` | `getTimeline` 与 `entry()` 从 store 一次读出 validated immutable projection，替换 dictionaryRepresentation 账号来源。future entries 继续复用同一 publication。 |
| `ios/DuoyiWidgets/DuoyiWidgets.swift:2219` | gallery locale 从 validated presentation 读取；不留下独立 UserDefaults widget locale writer/reader 作为新协议权威来源。 |

共享 store/decoder 应只使用 extension-safe 的 Foundation/CoreFoundation/SQLite/POSIX API。FlutterPlugin 注册、UIKit lifecycle、WidgetCenter reload 发起属于 host；不因为两个 target 都包含 shared 文件就让 extension 执行 open/initialize。

getSnapshot/getTimeline 的短读取使用共享操作锁和只读 SQLite transaction，将完整 envelope 复制解码成一次 capture，然后释放锁。extension 不在后续 dates.map 逐 entry 重读、不等待 Dart hydration、不把旧 UserDefaults rows 与新 canonical locale 混合。

iOS WidgetKit 不提供与 host commit 原子绑定的“OS 展示提交”接口：extension 读取时获得完整旧/新 envelope；之后 host 可能 sealed 或发布更新，而已构建 timeline 仍可被 OS 展示。账号 transition durable barrier 与后续 `reloadTimelines` 提供更新顺序，不能证明旧画面立即消失。action 仍必须在 host 验证当前 epoch/auth generation。不能宣称通过持锁生成 timeline 就消除了 OS 调度延迟。

## 6. Ack 能证明什么

| 阶段 | 可确认内容 |
| --- | --- |
| SQLite transaction + effective sync config 成功，新连接精确读回 | 完整 canonical envelope 与 receipt 已通过存储 durability 接口；Dart 可以在当前 generation 校验后更新 accepted cache。 |
| compatibility mirror 写入成功 | 仅旧消费者数据更新；不能改变权威 owner/floor/lease，不影响 canonical ack；mirror 失败也不能撤销已提交 canonical。 |
| Android updateAppWidget / iOS reloadTimelines 成功返回 | native 已接受/发起更新请求；不证明 launcher/WidgetKit 已展示。 |
| alarm scheduling/reconcile 返回 | 该效果请求的结果；不与 canonical transaction 原子绑定。crash 在 canonical 与效果之间需要基于有效 store 的后续 reconcile。 |

因此 native mutation ack 应继续使用批准字段，并独立记录 `refreshRequested/refreshFailure` 等请求阶段结果。clear barrier 的成功依据是 canonical sealed/tombstone 的 durable commit，不能把尚未完成的 OS 展示称作账号数据已从屏幕消失。

## 7. 有限的后续接入证据

这些是未来实现需要提交的证据；本轮没有执行。

1. Android effective min/compile SDK、merged manifest 默认进程/direct boot/backup 策略；iOS 两 target 的 shared source、SQLite linkage、entitlement 和 implicit-engine bridge 注册归属。
2. 两平台实际 DB/journal/lock 路径、同 inode 的协作锁、有效 PERSIST/FULL 配置；iOS fullfsync/protection/backup exclusion，以及多个 host engine/extension 并发的旧或新完整读取。
3. 在 CAS/COMMIT/读回间强制交错：第二 writer 无法插入 commit→readback；Android writer 无法插入最后验证→UI commit；operation retry 不重复 epoch/revision/效果。
4. 原生存储的 crash、IO/full-disk、commit ack loss、busy、hot-journal recovery、protected storage unavailable；分别证明 no false applied、no legacy fallback、未知结果不继续旧 lease 写入。
5. absent、已有空 DB、corrupt、未来版本、sealed/cleared、恢复后的 binding 校验；证明不自动认领备份/旧 mirror，不自动覆盖坏 canonical。
6. 使用批准 typed projection 接现有 frame/timeline；证明业务文档、per-widget style/options 和 presentation 来源分离，并保持已批准的数值类型、清理卫生与 accepted-effect 顺序。

不需要再展开逐 provider UI 审计。完成这组具体接入证据后，才能把本方案描述为已实现/已验证。

## 8. 仍然存在的明确失败状态

- COMMIT 后的确认失败会暂时 quarantine writer，即使 DB 后来显示新值；需明确恢复，不把“读到了新值”自动当已确认。
- 首次创建中 crash 留下空 DB、固定锁丢失、未知 schema、真实 corruption，需要显式恢复；fail closed 的代价可能是暂时无账号 widget 内容。
- 设备首次解锁前、App Group/磁盘暂不可用、只读 extension 无法恢复 hot journal时，不能保证立即生成新 timeline。
- 存储可确认、刷新可请求，但 OS 旧画面与效果交付有独立延迟/失败窗口；storage ack 不扩大到屏幕或 alarm exactly-once。
- Android 数值 min SDK/merged manifest、实际 SQLite/VFS 同步表现与 iOS 链接配置尚未通过平台证据核实。本文件不将这些未执行的证据写成验收结果。

本报告交付后停止源码读取。
