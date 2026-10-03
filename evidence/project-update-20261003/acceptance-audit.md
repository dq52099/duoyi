# 项目更新验收交叉审查（2026-10-03）

## 审查范围与结论

本报告基于当前共享工作树做静态交叉审查，并检查本机架构、工具与现有设备证据目录。此轮没有运行测试、分析器、构建或验收 gates，也没有修改源码。当前工作树仍有未提交改动，因此下列结论对应本次检查时的代码快照。

- Android 与 iOS 的真机验收仍未完成；当前没有 readiness 报告或设备回归证据。
- 当前启动清理路径已 fail closed：清理未完成时会阻止显示主界面和加载账户数据。
- `refreshMe` 收到延迟的 A 账号 401、且该响应在 B 登录完成后才进入错误分支时，当前 stale-request 检查会丢弃响应。另有一个更窄的异步写回窗口仍需处理和覆盖。
- workspace 墓碑的客户端与服务端数据形状兼容；当前 todo、goal、calendar 删除路径均带 workspace ID。服务端 `/api/sync/delta` 对嵌套 workspace 墓碑的直接契约覆盖仍不足。

## 环境与设备验收

- 主机架构为 `aarch64`；本机 Flutter 3.41.9、Dart 3.11.5，Java 17。CI 配置使用 Flutter 3.44.1 与 Java 17（`.github/workflows/build-apk.yml:24-26`）。
- `/dev/kvm` 不存在；当前 shell 的 `PATH` 找不到 `adb` 或 `emulator`。仓库中也没有 `build/device-readiness/latest`、`build/device-regression/android` 或 `build/device-regression/ios`。
- `docs/notification-p0-restart-plan.md:41-49` 记录没有连接的 Android 设备或可用模拟器，但同一段把模拟器宿主写成 `x86_64`，与本次实测的 `aarch64` 不符。`docs/device-regression-evidence.md:39-42` 的 ARM64 说明更符合当前主机情况。
- `docs/goal-requirement-matrix.md:3,14-22` 规定通知、Widget 与设备要求需要 Android 和 iOS 实机证据；仅静态测试或 APK 构建不能关闭这些要求。当前两平台证据目录均缺失，故设备验收保持 open。此主机也不能采集要求的 macOS/Xcode iOS 证据。

## AuthProvider 边界

### 启动清理失败时的保护

`AuthProvider.loadFromStorage()` 在读取和清理之前置 `_localAccountDataBlocked = true`，只有完成 owner 检查、必要清理及状态持久化后才解除阻止（`lib/providers/auth_provider.dart:169-199`）。如果签出状态遗留了 owner key 和账户数据，清理会调用账户切换前的 pending flush；pending 改动无法上传时会抛出 `AccountLocalDataCleanupBlockedException`（`lib/main.dart:632-644`）。

启动 guard 会记录阶段失败，但账户阻止标记仍保持；reminder/deferred storage 启动函数会在 blocked 时返回，应用也会显示 `LoginScreen` 而非 `MainShell`（`lib/main.dart:126-138,978-1026,4893-4918`）。因此旧 owner 数据不会因该清理异常而作为已签出的访客内容展示。没有 owner key 的访客数据仍按注释保留，这是有意行为（`lib/providers/auth_provider.dart:572-581`）。

### Logout 与 refresh 并发

指定的“旧 A refresh 在 B 登录后才返回 401 并清掉 B”场景，在当前代码中不会通过静态路径发生：logout 在本地清理前建立 transition 并递增 mutation serial；`refreshMe` 的 API 错误分支会同时核对 transition、登录态、captured token、mutation serial 和 request ID，只有仍属于当前会话的 401/403 才清理会话（`lib/providers/auth_provider.dart:458-466,808-820`）。因此 A 的错误响应若在 B 登录提交后才到达，会因 token/serial 不匹配而被忽略。

仍有一个“请求已通过首轮校验，之后才发生 logout”的窗口：成功分支通过响应校验后先设置 `_state`，再跨越 `_persistState()` 和 payload/profile callbacks；这些 await 之后没有再次检查 request ID、token、mutation serial 或 `_accountTransitionInProgress`（`lib/providers/auth_provider.dart:773-807`）。账户清理包含多轮异步 SharedPreferences 清理（`lib/main.dart:753-825`，随后 `_notifyAccountLoggedOut()` 还有一次清理，见 `lib/providers/auth_provider.dart:1462-1475`）。如果已通过首轮校验的 refresh 在这些步骤之间恢复，payload/profile callback 可能在清理后重新写入旧账户缓存；profile callback 的落盘路径见 `lib/main.dart:881-905`、`lib/providers/user_provider.dart:127-146,149-207`。这是由异步边界推导出的竞态，当前没有运行时复现证据。

最小修复方向：让 refresh 持有的会话 generation 在 logout/自动失效清理开始时立即失效；refresh 每次 await 返回后、持久化状态及调用账户 payload/profile callbacks 前重验该 generation。若 generation 已变化，则跳过后续账户写回。给 generation 与检查共用的状态写入路径传入请求开始时捕获的身份，避免清理期间读取可变的 `_state`。

当前测试覆盖了在首轮校验前发生 mutation 的 stale 成功响应，以及即时 401/403（`test/providers/auth_provider_profile_test.dart:1464-1591`）；没有找到验证“成功响应已通过校验后再开始 logout”的测试，也没有找到 A 401 延迟跨越 A logout 与 B 登录的回归测试。建议用可控 `Completer` 覆盖上述两个边界。

## Workspace 墓碑同步

客户端在 `workspace_payloads` 改变时走 `/api/sync/delta`，避免将嵌套墓碑发给只接受根级 item tombstones 的 `/api/sync/item-delta`（`lib/providers/cloud_sync_provider.dart:1468-1479`）。后端 `SyncDeltaRequest.collections` 可接收任意集合；`sync_delta()` 把已知集合覆盖到完整 payload，再调用常规 merge；workspace 合并路径会按成员权限合并并应用墓碑（`backend/main.py:3219-3222,9219-9245,8776-8814`）。

当前 todo、goal 与 calendar 删除生产者都向 `recordDeletedItem(s)` 传递模型中的 `workspaceId`（`lib/providers/todo_provider.dart:908-921`、`lib/providers/goal_provider.dart:175-198`、`lib/providers/calendar_provider.dart:112-127`）；此前“这些调用遗漏 workspace ID”的发现已不适用于当前工作树。Course 与 time audit 模型目前没有 `workspaceId`，对应删除仍使用账户级墓碑（`lib/providers/course_provider.dart:118-133`、`lib/providers/time_audit_provider.dart:148-188`）。

覆盖缺口：后端有 full-sync workspace 墓碑测试（`backend/test_workspaces.py:4220-4259`），也有普通根集合 delta 测试（`backend/test_workspaces.py:5239-5287`），但未找到通过 `sync_delta()` 发送 `workspace_payloads[workspace].deleted_items` 的直接契约测试。Flutter 测试会静态检查 workspace payload 改变时避开 item-delta（`test/services/cloud_sync_provider_test.dart:1298-1302`），未见该 fallback 请求形状的运行时断言。建议补一条后端嵌套墓碑 delta 测试和一条客户端 fallback body 测试。

## 验证证据状态

之前 worker 报告过 64 个 auth、129 个 reminder、43 个 cloud focused tests 通过；这些是隔离工作目录中的 worker 结果，不能视为当前共享工作树集成后的通过证据。本次没有重跑测试或 gates，也没有在此验收 lane 验证集成后的 analyzer、build 或总 gates。设备回归仍需在满足条件的 Android 与 iOS 设备上生成真实证据并通过对应 validator。

## 复审记录（2026-10-03 06:27 UTC）

本次按更新后的共享工作树，只读复核 AuthProvider 尾链、云同步回调与 ThemeShop 请求；未运行测试或 gates。以上初审内容保留为当时快照；以下结论适用于本次复审时的更新代码。

- `_accountWritebackTail` 的串行与 transition 顺序未发现具体重入死锁。登录响应、storage hydration 在占用 transition 后入队；logout 与自动 session cleanup 先占 transition、使 generation 失效并等待尾链排空，再启动账户清理（`lib/providers/auth_provider.dart:170-183,260-268,326-356,551-570,613-643`）。此前已入队的 refresh/snapshot 在任务执行时会再次验证 transition/generation；尾链会从失败任务恢复，允许后续清理继续。
- main 的 AuthProvider 回调没有发现会把同一尾链重新入队并等待自身的路径。账户资料及主题/奖励 callbacks 会等待对应 provider 操作完成（`lib/main.dart:882-947`）；dirty suppression 本身只包裹本地 provider 操作。CloudSync 的 `onSynced` 会等待 `refreshMe`（`lib/main.dart:1930-2077`），但账户 transition 已占用时，`refreshMe` 在入队前返回；logout 的 pending flush 则发生在 transition 和尾链 drain 之前，因此该 refresh 可以先完成，不形成“尾链等待 flush、flush 又等待尾链”的环。
- 复核后，前文所记的“已通过首检的 AuthProvider 回调可能跨过清理”不再是当前尾链实现下的具体路径。logout/自动 session cleanup 在等待尾链后才调用 `_notifyAccountLoggedOut`；正在执行的 awaited profile/payload 回调因此先结束，清理随后开始。未完成的 refresh 会在入队前或尾链任务执行时被 transition/generation 检查丢弃；`_persistState` 使用捕获的 `AuthState`，每次异步 prefs 写操作后复验身份与 generation，`_persistAndNotifyAccount` 也会在 payload 与 profile callbacks 之间复验（`lib/providers/auth_provider.dart:270-324,858-941`）。本次没有找到旧账户 payload/profile callback 在上述清理完成后继续落盘的具体路径。
- **ThemeShop 建议仍补 request-origin guard。** `applyThemeShopItem()` 目前在请求前捕获 token/userId，但直接从 `_client` 发请求；响应后调用的 `applyServerAccountSnapshot()` 才捕获 client 和 generation（`lib/providers/auth_provider.dart:943-1014`）。该快照的预期 token/userId 检查会阻止通常的 A→B 登录响应污染 B；但检查依据不是发出请求时的 client/generation。建议在 ThemeShop 请求前同时捕获 `requestClient` 和 `_stateMutationSerial`，用该 client 发请求，并在响应后用 `_guardAccountRequest(requestClient, generation)` 再进入 snapshot 流程。保留 expected token/userId 比较；generation 检查还可阻止同一 client/同一用户期间较旧快照覆盖后续账户状态。

## 最终集成记录（2026-10-03）

以上初审和复审保留为历史快照。ThemeShop request-origin guard、Auth 进入/离开 transition 通知、通知页代次清空与恢复、Theme/Achievement provider 内部 await 后检查均已补齐；最终两 provider 差异已获只读复审接受。具体结论与实际回归见 `final-account-boundary-review.md`。

后端 153 项通过；Flutter 242 个测试文件分两段覆盖、1,617 项通过；随后等价 mounted 检查补写后的主题 21 项通过。最终 analyzer 无问题，调试 APK 构建成功。最终 gate 前七组通过，仅设备组未通过；closure 报告格式、源码时效和需求映射均通过，未闭合问题仅为设备组及 Android/iOS 真机证据缺失。

完整记录以 `summary.md`、`alignment-final-complete/`、`goal-closure-final/` 和 `requirement-status-final/` 为准。通知、Widget 和设备要求仍保持 open；用户已要求列出待验收项，清单为 `pending-device-acceptance.md`。
