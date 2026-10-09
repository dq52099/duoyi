# Flutter publication 接入边界审阅

2026-10-09。只读检查指定 Flutter 文件及两份批准的契约文档；未修改源码、添加/执行测试、运行构建/SDK/Git/网络。未重审 SQLite。main.dart 的启动/回调注册顺序仅沿用 wire audit 的引用，本轮未读取其实际回调主体。

## 现状与实际接入点

`widget_publication.dart` 已具备严格十字段/89值 DTO、完整 presentation 版本语义、合法年份与67项清理规则；它仍只是 descriptor。`home_widget_service.dart` 没有引用 DTO/新通道，也没有 native lease、store/publication revision、desired floor 或 guest marker；当前实际 writer 仍是 HomeWidget 的逐项 prefs。

| 目标 | 已读源码中的实际位置 | 接线要求 |
| --- | --- | --- |
| 已验证启动 workspace | AuthProvider `loadFromStorage:241`、`_loadFromStorageNow:262–290` | 等这次 hydration 成功、blocked=false、transition=false、owner 与当前 AuthState 一致，再按已捕获 cleaner generation 打开 workspace；不能由 HomeWidgetService.init 授权。 |
| 登录/注册/再次登录 | `_applyAuthenticatedResponse:407–437`，注册/login/email 共用该路径 | 在 transition claim 时同步关闭 widget capture；在 `_state=nextState:430` 或任何模型/owner 清理前完成 canonical invalidate。新 state/model validation 完成后才 open。 |
| 显式 logout | `logout:635–669`，`_notifyBeforeAccountLogout:649` 在 transition claim 前 | 在第一个 await 前停止 widget capture；durable barrier 必须先于 `onAccountLoggedOut:677` 的模型删除及 `_resetLocalSession:750` 的 owner/auth 删除。保留现有需要有效 auth 的 preflight/flush 顺序。 |
| guest reset、session expired、改密码登出 | `_clearLocalSession:712`；调用点 `639/1045/1247` | 这些路径跳过 onBeforeAccountLogout，必须在共用 local-session transition/cleanup 边界覆盖同样的 barrier。 |
| 启动 owner mismatch/residual | `_clearStoredAccountDataIfOwnerMismatched:783`、`_clearResidualAccountDataIfSignedOut:826` | 回调及 callback=null 的 direct prefs cleanup 都不得越过未确认 barrier；失败保持 publication blocked。 |
| full data publication | HomeWidgetService `push:379–704` | 保留业务组装职责；在首次 await 前捕获完整 immutable values、locale/brand/theme、capture/day/offset、generation 和 lease/floor。使用完整 native publish 替换 per-key 发布。 |
| presentation 变化 | `updateTheme:252`、`HomeWidgetThemePayload.payloadValues:977` | theme/brand/locale 任一变化先提升同一 desired floor，再提交匹配版本的完整 document。theme-only patch 不能作为 canonical publication。 |
| 清理 | `resetAccountCache:281`、`clearAccountWidgetData:301` | 同步撤销 controller 当前 capability/capture；await canonical sealed/tombstone receipt 后才报告 clear barrier 成功。legacy payload 或 refresh 成功均不是此确认。 |
| action 校验 | `_ensureActionNonce:171`、`isCurrentWidgetAction:198` | 改用已验证当前 native epoch 与 auth/generation/day/offset；不再从 widget prefs nonce 获得归属，也不把 writer lease 放进 URL。 |

## 必须先修的风险

1. **不能只按 Auth 两个 flag 判 ready。** 构造时 `_accountTransitionInProgress=false`、`_localAccountDataBlocked=false`（139–140），尚未发生 hydration。publication controller 必须初始 blocked，并记录本次成功 hydration/validated workspace context；timeout、异常或 dispose 不算成功。`_stableAccountIdentity:1804` 已定义 id→username→email 的既有规则，可暴露窄只读结果，不能自行用 nonce/token 或另一个规则拼 binding。logged-in identity 缺失维持 blocked，不能转为 guest。

2. **barrier 不能仅挂在当前“需要清模型”的回调。** `_shouldClearLocalAccountDataBeforeApplying:1790–1793` 明确保留 guest import，故 guest→login 会跳过 onAccountIdentityChanging。widget 的 owner/epoch 边界仍必须 invalidate；它不要求删除合法导入模型。onBeforeAccountLogout 又不覆盖 signed-out logout、session expiry 或改密码路径。所有这些入口需共用 widget transition gate，并在 owner/model 写入或删除之前 await barrier。

3. **失败必须阻止现有 fallback 删除。** `_logoutAfterCleanup:679–685`、`_clearLocalSessionAfterCleanup:735–741`、residual cleanup `844–848` 只对 `AccountLocalDataCleanupBlockedException` 中止；普通 PlatformException/StateError 会进入 prefs fallback，随后可能 reset auth/owner。每个未确认 native barrier 结果应转换成已有 blocked-cleanup 异常，让这些路径不删除账号数据。Auth finally 会解除 transition flag，controller 的 blocked/未确认状态不能随之自动解除。

4. **等待 clear Future 不等于 clear 成功。** `_drainPendingAccountClear:330–338` 忽略 bool 并清除 pending；push/updateTheme 随后仅检查本地 generation/locale。新路径必须显式核实 canonical barrier 确认和当前 capability，clear=false/busy/unknown 时不得继续 publish。`_accountPayloadStorageCleared=true:318` 现在只代表 per-key 写入；不能复用为 native durability 标记。

5. **owner 持久化失败不能被当作已验证归属。** `_persistState:374` 与 `_persistAccountDataOwner:936/938` 忽略 SharedPreferences 返回 bool，而 load 后仍可解除 blocked。bootstrap 的成功条件应拒绝报告失败的 owner/auth 写入，并核验当前稳定 identity 与经验证的 owner；不能把一次 await 或 cached key 作为成功证明。这里需要的是 capability 授予前的验证条件，不扩展 native API。

6. **稳定 key 可能在 profile 更新中精化。** `_applyProfileResponse:449` 可在 legacy session 获取 userId 时把 username/email fallback 改成 id binding，之后 `934` 持久化 owner；它没有经过 identity-changing callback。controller 必须检查实际当前 binding 是否仍匹配，binding 改变时走 invalidate/open 和 fresh snapshot，不能继续沿用原 binding 的 lease或重贴旧 document。

7. **locale 相等不能防止 presentation 倒序。** push 的 guards 仅比较 `locale != I18n.current:441/663/686`，updateTheme 仅比较 account generation；zh→en→zh、T0→T1→T2 可使旧内容重新通过。body 内还有排队后读取 I18n 的位置（519/527/646）。首次 await 前捕获完整22项 presentation，主题和 brand strings 必须属于同一快照；为每次真实变化推进 device revision，禁止给旧 theme 重新标最新 revision。账号切换不能重置此 floor。

8. **需覆盖现有所有 writer。** push、updateTheme、clear 和公开 `HomeWidgetThemePayload.saveOperations:997` 都能写 account/presentation keys；后者直接绕过队列/generation。接线后这些路径统一走 controller。`setDisplayMode:241` 的独立 instance style 保留原路径。canonical values 不包含 nonce/day/offset/locale 的四个 flat 元数据，也不能继承旧 clear placeholders；用 DTO.clearedValuesFrom 构造67项零化的完整 tombstone。

## 有限实施顺序

1. 添加只使用批准四 mutations+read 的 Dart adapter/controller；初始 blocked，持有当前 validated binding、cleaner generation、native epoch/lease、store/publication revision、desired/applied presentation、pending immutable operation。read 不发 lease；只有有效 open ack 可以安装新的 lease。
2. 在上述 auth transition/cleanup 入口先接同步 capture pause 和 durable invalidate barrier，补齐 guest import与session-cleanup入口及失败异常传播，确保 owner/model 删除无法先发生。clear 失败保持 blocked；不通过换 expected revision 重放旧操作。
3. 接成功 hydration bootstrap。创建并确认 app-local `duoyi_guest_workspace_id_v1`：正常 guest restart 保留，真正 guest reset 清除/轮换。缺失或不匹配的 marker 不认领 native guest/legacy nonce；先 sealed，再用新 guest binding+cleared doc打开。合法 guest models 保留后重新发布。read absent 才能首次 initialize；matching active resume；sealed initialize；foreign active先invalidate；corrupt/unsupported/durabilityUnknown 不覆盖或fallback。
4. 接 device presentation snapshot/floor。read 后由 caller 提供不低于 native floor、同版本 locale及22值一致的 presentation；不匹配时创建高于 floor 的当前 device 版本。open/resume 完成后，full publish另等所需 provider hydration，再复核同一 context。pending floor 与 applied doc保持区分。
5. 把 HomeWidgetService data/theme/clear writer 改为完整 DTO publication。成功 ack 才更新 accepted cache；ack 必须匹配 operationId、expected结果及仍当前的 generation/lease/desired context。timeout/丢失回应保留原ID与完整请求，原样重试或read后重新验证context；receipt 被覆盖/CAS conflict 后重新捕获业务，不给旧内容换最新 revision。不要保存 writer lease到 prefs/deep link。
6. 同批接 canonical native readers与最终接受/效果路径，再按 confirmed revision 请求 refresh/reconcile。Android bridge 当前 refreshRequested=false，因此 store成功不能被描述为 legacy reader已更新、屏幕已清除或alarm已取消。mirror若保留只作兼容输出，不能成为 bootstrap/ack/渲染回退的权威来源。

这是接入边界与顺序，不是已落地/运行验证声明。iOS桥接/reader与 Android canonical frame 接入仍须各自完成；本轮没有添加新 native API 或重开存储方案。

## 来源

- `/home/ubuntu/duoyi/lib/services/widget_publication.dart`。
- `/home/ubuntu/duoyi/lib/services/home_widget_service.dart`。
- `/home/ubuntu/duoyi/lib/providers/auth_provider.dart`。
- `/home/ubuntu/duoyi/evidence/widget-publication-descriptor-20261009/wire-schema-audit.md`，尤其第4–7节。
- `/home/ubuntu/duoyi/evidence/widget-publication-descriptor-20261009/native-store-implementation-plan.md`，第3节与效果顺序说明。
