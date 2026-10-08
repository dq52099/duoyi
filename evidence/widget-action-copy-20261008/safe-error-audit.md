# Cloud sync 安全错误显示与 legacy runtime 断言审计 — 2026-10-08

## 结论

两条 legacy `lastError` 文案断言与当前明确的安全显示契约冲突，源/历史根因已定位。它们于 2026-10-03 加入，安全 helper 于 2026-10-06 改为屏蔽非 ApiException 原文与 HTTP 5xx 详情，却未同步这两条断言。本批 widget typed copy 没有更改 CloudSyncProvider 或 ApiClient。不能为满足旧断言恢复原始异常显示，也不能只删除失败断言而弱化 pending、持久化、无错误确认写回的保护。

用户应知道“本机内容保留、上传未完成”。当前已有独立状态字段及展示包装提供这个信息，不要求 `lastError` 含有 StateError 原文或服务端 500 detail。源级结论允许把这两条错误文案断言迁移为安全提示断言，同时保留并加强状态和展示验证。准确 baseline runtime 重跑由根 agent 负责，本 agent 未运行测试。

## 范围与位置

仓库没有独立 `api_error_message.dart` 文件；实际 helper 是 [api_client.dart 的 userVisibleApiError](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/api_client.dart:520)。本审计只读当前 helper、provider、两条相关 legacy tests、已有安全错误测试、相关展示和本地 Git 历史。未改 source/tests，未运行测试、分析、构建或网络调用。

## 历史因果

| 日期 / commit | 变更 | 与失败的关系 |
| --- | --- | --- |
| 2026-10-03 / `7525c190dc3b4b57f725284e36643147c47a9d01` | 加入本地 pending 上传失败/缺确认字段的两条 runtime cases、pending retry 分层和 acknowledgement 校验 | tests 当时期待 raw HTTP detail 与 StateError 文案 |
| 2026-10-06 / `3de47bbe63aa833237a151852813f78bd85eddce` | userVisibleApiError 新增非 ApiException fallback、HTTP 5xx fallback、HTML/JSON/传输诊断过滤；同时新增安全正负 unit cases | helper 语义变化，CloudSyncProvider 和旧 runtime cases 的这两条断言未更新 |
| 当前 base `0320cd6e4475ade690e4d4e5ba7f244105809819` | 包含上述安全 helper；CloudSyncProvider SHA-256 与工作树相同 | 本批 typed widget 文案无法解释这两个新增被覆盖到的 legacy 文案失败 |

`git blame` 把测试 405/444/445 行定位到 `7525c19`，把 helper 的安全分支定位到 `3de47bb`。`3de47bb` 的 diff 明确从 `error.toString()` 转为仅接受 ApiException presentation 文案，且把 HTTP 5xx 换成 caller fallback。ApiClient 和 provider 相对当前 base 无 diff。

## 两个 actual 的确定来源

### HTTP 500 上传失败

ApiClient 从 JSON detail 取到 `local upload failed`，`_buildHttpErrorMessage` 组成 `500: local upload failed`，封装为 ApiException。userVisibleApiError 识别开头 HTTP code >=500，返回 caller fallback。CloudSyncProvider 的 fallback 为 `云同步暂不可用，请稍后重试或联系管理员`。

这条详情由服务器产生，不能当作本地持久化事实或必须显示给用户的安全文案。测试应确认 safe fallback 和不透传 raw detail，而不是恢复 `contains('local upload failed')`。

### HTTP 200 缺少 acknowledgement 字段

[ack validator](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/cloud_sync_provider.dart:2490) 检查 server_updated_at、server_version、collection_hashes 和所需集合 hash。缺项抛 StateError，其中包含诊断键和“本机改动已保留”。[调用顺序](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/cloud_sync_provider.dart:1501) 在 `_applySyncResponse` 之前校验，因此校验不通过不会应用响应、推进 revision、标记同步成功或清 pending。userVisibleApiError 对所有非 ApiException 使用 fallback，所以这条 StateError 不显示原文。

安全 helper 不应通过异常中文匹配恢复“本机改动已保留”子串，也不应把任意 StateError 包成 ApiException 透传。若未来需要“服务器未确认上传”的特定安全原因，应使用有类型的内部 reason code 或受控常量，在同步事实层生成；本批不需要扩大生产改动。

## 本机保留信息的现有独立证据

1. [provider failure catch](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/cloud_sync_provider.dart:1559)：真实本地待上传失败设置安全 lastError、清 baseline retry marker、保留 `_hasPendingChanges=true`，并持久化 `sync_pending_local_changes=true`。随后按现有自动同步条件调度 retry。
2. [sync conflict status](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/screens/sync_conflict_log_screen.dart:300)：依据 `hasPendingChanges` 显示“本机改动同步未完成”，并在安全 error 后追加“本机改动已保留，稍后会自动重试”，pending label 为“待上传”。这些安全事实并不来自异常字符串。
3. [TodoScreen banner](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/screens/todo_screen.dart:1516)：error notice 包装为“本机待办已保存，但服务器同步失败”。[main mirror](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:1371) 传入 provider 的安全 error。
4. [provider local-save helper](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/cloud_sync_provider.dart:212) 和新 typed widget descriptor 都先声明本机保存，再描述失败/待重试，不声称服务器已确认上传。
5. 已有 [TodoScreen widget fixture](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/test/screens/todo_kanban_view_test.dart:100) 保留本机保存 + 同步失败包装；本 agent 仅读源码，未执行该 fixture。

因此不能把“安全 lastError 没有保留原始句子”直接等同于“用户已经失去本机保留状态”。仍应为两个安全 fallback 场景补齐展示层正例，防止未来包装删除。

## 有界修正与必须保留的断言

生产 helper/provider 保持当前安全契约。仅迁移两个 legacy runtime cases 的错误文案期望，并增加事实与负验证。

| case | 必须保留 | 建议新增 |
| --- | --- | --- |
| 本地 pending + HTTP 500 | hasPendingChanges=true；prefs pending=true；lastError 非空；hasSyncRetryPending=false | lastError 等于受控 fallback，且不含 raw detail/token/URL/HTML；isSyncing=false；syncRetryStatus=null；加入 local todos sentinel，检查存储未改变；lastSync/revision/hash 未推进 |
| 本地 pending + HTTP 200 无有效 ack | hasPendingChanges=true；prefs pending=true；server_updated_at/version 未推进 | lastError 等于受控 fallback；hasSyncRetryPending=false、syncRetryStatus=null、isSyncing=false；local todos 未改变；lastSync/collection hashes/item hashes 未推进；onSynced 不调用 |

missing-ack fixture 当前响应 todos 与本机 todos 相同，无法发现错误应用响应。应返回不同的 server todos，同时断言本机原文未变，证明 ack 校验确实先于 writeback。除无字段外，可增加有 revision 但缺所需集合 hash 的 case，避免只测“全部缺失”的简单分支。

保留原有 baseline failure 对照：没有真实 local pending 时，lastError=null、hasPendingChanges=false、durable pending 不置 true、hasSyncRetryPending=true 且阶段提示为“同步基线建立失败”。不能把 baseline retry 与真实本地上传失败合并。

## 新增正负验证建议

- **安全负例**：500 detail 里加入 `token=private`、URL、HTML 等诊断后缀，确认 public lastError 与展示结果都不含这些值，同时 pending 和本机数据仍保留。
- **拒绝确认负例**：200 响应返回不同 todos，但缺 revision/hash ack；不应用 server 内容、不推进 revision/time/hash、不清 pending、不调用 onSynced。public error 使用安全 fallback。
- **成功正例**：同一 provider 的后续合法 response 带 required acknowledgement 字段和所需 hashes，真正成功后才清 pending/lastError并推进 revision/time。可以用显式第二次 syncNow，避免靠等待后台 timer 猜测成功。
- **展示正例**：安全 fallback + pending=true 仍显示“本机保存/保留”和“同步未完成/待上传”；不出现上传已完成 claim。pending=false 的 baseline 失败不伪装存在本地待上传改动。
- **安全 helper 正反对照**：保留现有 StateError/FormatException/5xx/transport/HTML 过滤负例，以及 400 业务反馈 `邮箱已被使用` 保留正例。屏蔽任意错误原文不应吞掉明确可展示的业务反馈。

这些建议是审计方案，本 agent 未新增或执行任何测试。根 agent 的 baseline 重跑与新回归结果应另行记录；此报告不将实际回归失败或 preexisting 的 runtime 身份仅凭源码称为已运行确认。

## 审读指纹

| 文件 | SHA-256 |
| --- | --- |
| lib/services/api_client.dart | e82c211ce8b05870f4a28e077ef5c8c1db657d5f6114163e8dbc30e8b91d1376 |
| lib/providers/cloud_sync_provider.dart | a7b29554dafd02a50ea4c725914fda1ac91f6cc9986f49a282ea4e6f0c7444c9 |
| lib/screens/todo_screen.dart | c297dcadb138a288ba3f3b2a4472d44ffa4730637074374be01df5b56b6c3d5f |
| lib/screens/sync_conflict_log_screen.dart | 9b7ae1aa92ded17a2a62e18778163e983737ffc8570cdddc83d2fb58a7033b45 |
| test/services/api_client_error_test.dart | ebaca4f724ca7188aefcc2cde9a00d4326e416bc5cc193fe6d9dfb1b70172f23 |
| test/services/cloud_sync_provider_test.dart（审读时 typed source assertion 更新后） | b41890e388eb5b82f8e84d552a0dc2a13fbab87605717c2b44b4b467b072118c |
| test/services/sync_conflict_log_static_test.dart | 95aab9145f83f4663b5dcd85b064bacb1ff245b18db1bb3ceea0384448dc1b75 |
