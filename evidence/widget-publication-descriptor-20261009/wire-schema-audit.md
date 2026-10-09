# WidgetPublication draft 与 wire/store 契约

日期：2026-10-09
冻结 draft：[widget_publication.dart](/home/ubuntu/duoyi-worktrees/widget-publication-20261009/lib/services/widget_publication.dart)，任务提供基线 99cd7da；未运行 Git 核验。
只读结论；未改生产/测试，未执行 SDK/build/check/test/network，未读取真实 prefs/token 或 live AGY worktree。

## 1. Draft 判断及必须修正项

现有 draft 的基础结构可保留：

- 顶层恰好十字段；未知版本、额外/缺失 key、未知 state/locale、错误 primitive 类型均拒绝。
- values 的 89 字段覆盖现有 accountPayloadDefaults 去掉 nonce/locale/day/offset 四项后的完整集合：73 String、13 integer、3 bool。
- values 均为 primitive，Map.unmodifiable 的防御复制足够；metadata 为 final。toJson/toFlatValues 返回新 map，不改原 descriptor。
- identity metadata 由顶层投影，values 无法另塞 nonce/day/locale 覆盖它们；style/options 继续在外部。
- literal 不 trim/normalize/toString。tryFromJson 在 keys 为 String、values 非 null 后才 Map.from，对普通 JSON Map 不属于未经检查的泛型 cast。

**接线前 must-fix：**

1. 将 integer 分为 Int32 和精确 Long，使用第2节的字段范围；当前统一允许 signed 53-bit，不适配 Android 的严格 getInt。
2. cleared/blocked 必须清除全部 67 个业务值，不能只要求 day 空；精确字段分组见第3节。
3. published day 的年份必须 1..9999。当前 DateTime.utc 校验可接受 year 0000，iOS snapshot 明确要求 year>0。
4. localeRevision 的 wire 语义必须覆盖完整 presentation，包括 locale、brand、theme；旧 theme 请求不能只因 locale 未变而取得新的版本。
5. 补 native-owned durable owner binding/envelope、读状态、bootstrap、CAS 与失败/ack 状态机。descriptor 合法不授权发布。

tryDecode 返回 null 仅表示不能解析；尚未接线，不能据其注释声称 unknown canonical 的 blocked 行为已经实现。reader 必须另区分 absent、corrupt、unsupported、cleared/blocked 和 durabilityUnknown，禁止一律当作“首次初始化”。

## 2. 精确数值与跨平台投影

| 字段 | v1 范围 | Android frozen/legacy 投影 |
| --- | --- | --- |
| todo_count、todo_top3_count、pomodoro_today、focus_minutes_today | 0..2147483647 | Kotlin Int / putInt |
| habit_percent | 0..100 | Int / putInt |
| habit_active_count | published 为 -1..2147483647，保留现有 -1 unknown sentinel；非 published 必须0 | Int / putInt |
| focus_timer_remaining_seconds、focus_timer_total_seconds | 0..2147483647 | Int / putInt |
| widget_theme_corner_radius_dp、widget_theme_control_radius_dp、widget_theme_border_width_dp | 0..2147483647 | Int / putInt |
| focus_timer_started_at_millis、focus_timer_ends_at_millis | 0..9007199254740991；非 published 必须0 | Long / putLong，包括数值0 |
| publicationRevision、localeRevision、capturedAtMillis | 0..9007199254740991；published publicationRevision>0 | Long；不放入 getInt 的 flat 数据 |
| snapshotUtcOffsetMinutes | -1080..1080；非 published 必须0 | Int，投影为 widget_snapshot_utc_offset_minutes |
| ownerEpoch | 非空 opaque String，精确比较 | String，不能当数值或 trim 后重新绑定 |

todo_count 与 todo_top3_count 来自同一个现有 todoCount，完整 publication 应保持二者相等。无需新增未经业务依据的 timer 状态限制；合法 timer phase 仍交给现有 resolver。保存未知值时不能 clamp 以“通过”此 schema。

依据：

- [DuoyiFrozenWidgetPreferences](/home/ubuntu/duoyi-worktrees/widget-publication-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFrozenWidgetPreferences.kt:19) 的 getInt/getLong 使用严格 Int?/Long? cast。
- [FrameCore](/home/ubuntu/duoyi-worktrees/widget-publication-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetFrameCore.kt:38) 要求 offset 是 Int；错误投影为 Long 会使 session 不可信。
- [Focus compat getters](/home/ubuntu/duoyi-worktrees/widget-publication-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt:312) 虽接受 Int/Long，甚至 clamp seconds，但不能依靠它替代 wire 校验；其他 counter reader 直接 getInt。

不要把 JSONObject/MethodChannel 解码后的 Number 原样交给 frozen prefs：小数字和大数字的运行时类型可能不同。按字段 manifest 验证整数、范围后，明确 toInt/toLong。不可先转换再检查，不接受 double 截断、String 数字或 Boolean 当 integer。

Swift 使用严格 NSNumber/Int64 路径，排除 CFBoolean 类型，验证 finite/exact/range 后转换；所有 Bool 独立解码。Darwin Int 宽度不能成为 v1 扩大 counter 范围的理由。

JSON 的整数检查以解码值为准；Dart web 不能总是区分整数 token 与 1.0/1e0，不宣称 DTO 做了数字词法验证。所有版本/时间保持精确整数，不使用 double 存储。达到最大 revision 必须明确失败，不能 wrap/reset 复用。

published parser 可接受历史合法 day，不能据“不是今天”拒绝整个持久化 document。真正 publish 的 day/offset/capture context 及当前日期边界在 store/controller 接纳时校验；stale reader 继续现有规则。

## 3. cleared/blocked 的精确字段组

root 已确定非 published document 使用**空业务字符串**，由 renderer 提供安全 locale placeholder。避免与可变 I18n defaults 字符串逐项比较，也不猜测某段 row/body 是 app-owned。

### 3.1 必须空字符串：55 项

- todo_top3_1/2/3 及各 _id：6项；
- goal_highlight_1/2/3 及各 _id：6项；
- anniversary_highlight_1/2 及各 _id：4项；
- course_highlight_1/2/3 及各 _id：6项；
- note_highlight_1/2/3 及各 _id：6项；
- memorial_highlight_1/2/3 及各 _id：6项；
- diary_highlight_1/2/3 及各 _id：6项；
- schedule_highlight_1/2/3 及各 _id：6项；
- today_event_summary、calendar_month_summary、focus_summary、habit_summary、streak_summary、next_focus_label：6项；
- focus_timer_label：1项；
- habit_quick_check_id、habit_quick_check_label：2项。

### 3.2 必须0：10 项

todo_count、todo_top3_count、habit_percent、habit_active_count、pomodoro_today、focus_minutes_today、focus_timer_started_at_millis、focus_timer_ends_at_millis、focus_timer_remaining_seconds、focus_timer_total_seconds。

### 3.3 必须 false：2 项

focus_timer_count_up、focus_timer_running。

### 3.4 保留完整、类型正确的 presentation：22 项

brand_app_title、nav_todo、nav_habit、nav_calendar、nav_focus（5项），以及全部17项 widget_theme_* manifest 字段。这些值仍须来自同一 locale/brand/theme 快照；不包含 instance style。

顶层 snapshotDay=""、snapshotUtcOffsetMinutes=0。capturedAtMillis 是清理记录时间或0，保留精确 Long 范围。cleared/blocked 的 publicationRevision 可为0，或在同一 epoch 内按正常单调序列更新。

clear builder 可以以 accountPayloadDefaults 为起点，但只对 canonical tombstone 将上述67项归零/置空。不要把旧 defaults 内 app placeholder 当作账号业务数据保留，也不要改动 legacy renderer 的 fallback 契约。

## 4. Durable binding 放置决定

**稳定账号 binding 放在 native-owned、一次原子提交的 store envelope 中；不加入公开十字段 document、89 values 或 deep link。**

建议 authoritative key：duoyi_widget_store_v1。其 native envelope 最少包含：

~~~text
storeSchemaVersion = 1
storeRevision
binding = null | { kind: account|guest, key: opaqueStableWorkspaceKey }
ownerEpoch
writerLeaseId = null | nativeIssuedOpaqueId
leaseState = active|sealed
desiredPresentation = { revision, locale }
document = strict ten-field WidgetPublication
lastReceipt = { operationId, requestDigest, committedStoreRevision, resultMetadata }
~~~

storeRevision 为全 store 单调 Long，不因 logout 重置。publicationRevision 是当前 ownerEpoch 内的 document 序列；新 epoch 可以从 cleared rev0开始。document.localeRevision 是 device 的 presentation 序列，不因 owner 变化归零。

document.ownerEpoch 必须等于 envelope.ownerEpoch。active binding、lease、document、desired floor 和 receipt 在同一 envelope 原子提交。任何解码/关联不一致都 fail closed。

draft 的 storageKey 可保留为 document-only compatibility mirror；它不能成为独立授权来源。native reader/controller 解码 authoritative envelope，抽取经过验证的十字段 document，再 toFlat 投影。一个残留 mirror 不能覆盖 sealed envelope 或获得新 owner。

Account binding 使用既有稳定 local account identity（userId 优先，之后既有 username/email fallback）；不给 renderer/deep link 暴露它，不使用 auth token。

Guest binding 使用明确持久化的 guest workspace ID。例如新增 app-local duoyi_guest_workspace_id_v1，跨 guest restart 保留，真正 workspace reset 时轮换/清除。它与 native binding 相互校验；缺失时创建新 ID，清空 canonical 后从已验证 guest models 发布新快照，不能从旧 widget nonce 认领。

native-issued epoch 每次真正账号/workspace reset 都轮换；同账号再次登录仍是新 epoch。正常同账号/同 guest restart 可保留 ownerEpoch，但 open 会发新 writerLeaseId 并增加 storeRevision，封住旧 engine/旧 writer。lease 不加入 mutation URL，action 继续绑定 workspace epoch/day/offset，并在当前 auth generation 下执行。

## 5. Bootstrap 的唯一许可来源

现有 [AuthProvider load](/home/ubuntu/duoyi/lib/providers/auth_provider.dart:241) 在 hydration 期间保持 blocked/transition；262 的读取先处理 owner mismatch/residual，再写 _state、persist owner，最后解除 blocked。783 的 owner 比较允许既有 guest import；930 保存稳定 owner。

main 已在 auth load 前注册 cleanup callbacks，[启动顺序](/home/ubuntu/duoyi/lib/main.dart:977)为 locale → auth → 其余关键 provider。新 open 点必须满足：

1. auth hydration 实际成功，blocked=false、transition=false；startup timeout 返回不等于成功。
2. captured AccountLocalDataCleaner generation 在 await 前后仍当前。
3. 当前 AuthState 和经其 validation/persist 的 local owner 一致；不能单凭一个非空 prefs key 或 native nonce 推导身份。
4. 当前 device locale 与 presentation revision 已确定。
5. full publish 另等所需 providers hydration 完成，并重新核验同一 context。

_stableAccountIdentity 当前是 private helper；可以暴露仅用于本地归属的只读结果，或在成功 hydration 后核验已写入 owner key。若 logged-in 却无法确定稳定 identity，不能把 owner key 缺失解释成 guest，应维持 widget blocked。

| native read 状态/当前已验证 workspace | 允许行为 |
| --- | --- |
| authoritative envelope 不存在 | initialize 新 epoch、binding、lease及干净 cleared doc；忽略 legacy widget data；随后从已验证 models fresh publish。 |
| active、健康，binding 精确匹配，epoch/document/floor 一致 | resume；保留 document/epoch，发新 writer lease、增加 storeRevision。 |
| active binding 不同，或同身份但本轮已触发 reset | 先 explicit invalidate；不能以 matching stable identity 绕过 reset 或自动接管。 |
| sealed/cleared、cleanup 成功、当前 workspace 已验证 | open 新 epoch/binding；不复用旧 lease 或 relabel 旧 document。 |
| guest marker 缺失/不匹配 | 新 guest binding + cleared doc，合法 guest models 后续重建 publication。既有 guest import许可不授权导入旧 widget mirror。 |
| corrupt、unknown envelope schema、uncertain durability | 不 initialize 覆盖它、不 fallback mirror；返回 blocked/unsupported，走显式恢复。 |
| auth validation/cleanup 失败或 generation 变化 | 不 open，不旋转为“当前”，维持 blocked。 |

bootstrap 只重建 widget snapshot，不变更用户 models，不触发网络。早期 widgets/restore 可依据最近 native durably verified envelope 渲染；它不是本次 auth hydration 已完成的证明。所有 owner 改变必须先使该 envelope 失效，host bootstrap 再校验本地 owner。对无法证明 binding 的导入/restore，禁止自动认领。

## 6. 最小 wire API

所有 mutation 请求有 protocolVersion=1、operationId（唯一）、expectedStoreRevision、expectedOwnerEpoch；null 只用于明确 absent 的初始化。native 单一队列/锁负责 parse、CAS、提交和 receipt。read 不授予当前 writer lease。

### readWidgetStore

无副作用。返回 absent/ready/sealed/corrupt/unsupported/durabilityUnknown，以及已确认的 storeRevision、epoch、private binding、desired floor、document；不创建 epoch、不补 defaults、不返回 writer token给旧 publisher使用。

### openWidgetWorkspace

请求附加 mode=initialize|resume、validated binding、coherent cleared presentation、当前 device presentation revision/locale。

- initialize 只接受 absent 或预期的 sealed 状态；active foreign binding 返回 ownerMismatch。
- resume 只接受 matching active binding、完整健康 document；native 发新 lease、增加 storeRevision，保留 epoch/document。
- initialize 的 epoch/lease 由 native 生成；native 构造/验证干净 document。Dart 不能通过 document.ownerEpoch 自行授予权限。
- locale floor 与 device 记录不一致时，以已验证 device locale 建立高于当前 floor 的新 presentation 版本；不能把较低 revision 写回，或盲从 native 旧 locale 改用户偏好。

### invalidateWidgetWorkspace

附加 coherent cleared presentation 与最新 device presentation context。native 精确 CAS 后：

- 轮换 epoch，撤销 lease/binding，leaseState=sealed；
- 原子写入67业务值归零/空的 tombstone，保留22 coherent presentation；
- 提升 storeRevision并记录 receipt。

main 在 transition 开始即同步暂停 widget capture，再 await 此 durable barrier；**barrier 成功之前不开始删除/改写 local owner 和账号 models**。成功以后旧 publisher 永远不能用旧 epoch/lease提交；cleanup 失败时保持 sealed。新 workspace 完成 validation 后才 open。

### advanceDesiredWidgetPresentation

附加当前 writerLeaseId、desiredRevision、locale。该版本代表**完整 presentation**：locale、brand、theme 任一变化均增加；doc 字段暂名 localeRevision。

native 拒绝降低 floor或同 revision 换 locale；成功则原子提升 floor/storeRevision。输入 theme/brand/strings 必须与 revision 一起在 caller 捕获，不能排队后给旧 theme 标上最新 revision。

此 command 不伪造已完成 publication；read/ack 要区分 desired 与 applied。reader 可保留旧完整 publication等待新发布，或显示明确 stale projection，但不能把旧 app copy重新标成最新。不能声称 desired ack 已完成所有 launcher locale/style 更新。

### publishWidgetPublication

附加 writerLeaseId、expectedPublicationRevision、严格 document JSON。

native 必须同时验证：

- active binding/lease、expected epoch/store revision 精确相同；
- document epoch 等于当前 epoch；
- document publicationRevision = 当前 document revision + 1；
- document.localeRevision 等于 desired presentation floor，locale 与 floor 的 locale 一致；
- 10字段/89值、Int32/Long、state清理规则正确；
- published snapshot的capture/day/offset context有效，当前日期边界仍允许该发布。

成功提升 storeRevision并保存 document/receipt；不要求 doc 是今天才能读取历史值，但不允许 controller 把过期 capture 当作一次新的当天发布。theme copy-on-write 也提交完整 document，使用准确 expectedPublicationRevision；不能仅 patch mirror 或跳过 desired fence。

revisionConflict 后只能重新建立仍然有效的业务/presentation context；不把旧 document 换上最新 expected revision重试。

## 7. Ack、failed commit、ack loss

mutation ack 必含 operationId、status、committedStoreRevision、ownerEpoch、publicationRevision、desired/applied presentation revisions、document state。open 成功另返回新 writerLeaseId。

状态至少：applied、alreadyApplied、ownerMismatch、revisionConflict、supersededPresentation、invalid、sealed、unsupported、durabilityUnknown。

- operationId + 相同 requestDigest 命中已持久化 receipt：返回原提交的 alreadyApplied，不再次加 revision/轮换 epoch；同 ID 不同请求拒绝。
- ack 丢失/timeout 不证明失败。Dart 不推进 cache，也不 blind retry with newer expectations；以原 ID/原请求重试，或 read 已确认状态后在当前 context 下恢复。
- 只有当前最后 receipt 的最小实现也可行；若已被其他操作覆盖，旧 retry 返回 conflict/unknown，不能重放旧 mutation。无需无限 receipt 历史。
- 异步 ack 返回后，Dart再次核验 account generation、lease及 desired presentation。过期的 open/clear/publish ack 不能把新 epoch/旧 locale写入当前内存。

Android SharedPreferences.Editor.commit=false **可能已经改变进程内 prefs**。不能把随后 prefs.all 的新值当作 durable receipt，也不能假定旧 envelope自动回滚。此时 native 进入 durabilityUnknown，撤销当前进程可写能力/返回未确认，拒绝 resume/publish；需要能证明落盘的恢复或选择有明确事务/原子文件确认的 store。

简单重复写同值也不能未经依据宣称强制重新落盘。必要时用原子文件/事务 store，或明确实现 commit失败恢复和durable readback。只有 durable barrier成功才能让 main 宣称 widget account clear完成。

iOS UserDefaults setter 返回 true 也不等同durability ack。采用单 envelope value时需要证明持久化及 app-group read；若没有足够保证，使用受协调文件/事务store。legacy mirrors不是确认来源。

store/envelope提交、mirror提交、已请求widget刷新、OS实际展示是不同阶段。applied表示durable canonical提交；refresh另报告。frame不能混用新canonical与旧mirror，unknown canonical不能回退legacy。

## 8. 最小接线顺序与未来 fixture

生产职责：

1. root 修 DTO 范围/年份/67项非 published卫生，并固定 localeRevision 的完整 presentation语义。
2. native store/decoder/bridge实现上述 envelope、typed flat projection、CAS/receipt、读状态。
3. Dart controller接 auth-success bootstrap、transition最早barrier、guest marker、desired presentation fence。
4. HomeWidgetService所有data/theme/clear路径使用该controller；frozen frame与iOS reader消费已验证document。instance styles/options保留原路径。

必须增加但本次未执行的fixture：

- 十字段/89值完整/未知/缺失、literal code-unit保真及 map修改不影响原对象；
- 每个Int32 key的两端/越界、epoch millis/revision的精确Long两端、offset投影为Int；Swift排除Boolean-as-number；
- year0000拒绝、合法闰日/历史day保留，published capture边界；
- 非published67项每项逐一篡改都拒绝，22项presentation保持，timer session不复活；
- absent与invalid区分，不从mirror认领；authenticated identity缺失不降级guest；
- matchingrestart/resume新lease、guestrestart、guestimport、同账号relogin轮换epoch、foreignbinding拒绝；
- invalidate在旧publish await中、旧lease/epoch/storeRev晚到、owner切换后旧ack返回；
- zh→en→zh及theme T0→T1→T2反向完成；旧完整theme不能覆盖新presentation；
- commitfalse后memory变更、acklost/idempotentreceipt、receipt被覆盖、不推进错误cache、不伪造durability；
- Android typedfrozenprojection、iOS host/extension read、coldstart/restore绑定及未知数据failclosed。

本稿没有wired/tested/committed的实现证明。完成DTO只解除schema基础阻塞；真正cross-platform owner publication和full widgets/global locale目标仍需后续接线及平台证据。
