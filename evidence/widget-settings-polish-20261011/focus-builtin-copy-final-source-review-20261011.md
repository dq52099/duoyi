# FocusRoom builtin copy 最终源码审查 — 2026-10-11

## 结论与范围

**这三个文件的 bounded source review 通过，未发现需要修正的生产 blocker。** 实施形成了 app-generated defaults → 显式持久化 marker → storage 恢复 → 纯 locale 显示 → 服务/用户覆盖后失效的闭环。legacy 无来源记录保留 literal，不按 ID/text 推断。

仅只读当前 main 的：

- `lib/models/focus_room.dart`
- `lib/providers/focus_room_provider.dart`
- `test/providers/focus_room_builtin_copy_test.dart`

未读取 AGY live screen/helper/log/job，未读取或等待 root runner，未改 source/test，未运行任何 tests/build/analyze/validation。本报告是本次唯一写入；**没有新运行通过结论**。

| 文件 | 审查时 SHA-256 |
| --- | --- |
| model | `73a04f97d627bd94745e431acaf2fcf383148fbb47bb34204d5341d2d75ee235` |
| provider | `43e017dd406f09decbc7dc040fc5429aeca3da7593c08b4d0fb934fcfa451525` |
| 新测试 | `81eb3a450ef4d8f541a06721112d280fc4b82ecd69810cbbed3f7cb0c3cfea89` |

## 真实生产边界核对

| 边界 | 当前源码证据 | 判断 |
| --- | --- | --- |
| 显式 app 生成来源 | `_defaultRooms` 三个对象分别赋 deepWork/examSprint/reading kind；createRoom 没有赋 kind | 符合生成源契约 |
| 有效 kind 与纯显示 | model 的 `_builtinKind` 为 final；公开 getter 以 `matchesContent(this)` 验证 ID/raw name/raw description；nameFor/descriptionFor 只读取有效 kind 或返回 raw | 错误继承 marker 也不能藏改名内容；不修改 I18n/状态 |
| canonical raw guard | matchesContent 使用固定 roomId 与 explicit zh catalog copy，精确比较，无 trim/内容猜测补来源 | 只有先有 marker 才能生效；文字相同本身不授予来源 |
| raw JSON | FocusRoom/seed 的 toJson 保持原字段和值；fromJson 不接收 room 内任何 display-looking marker | 原 room/seed 协议不变；单独 room JSON roundtrip 保守 literal |
| 精确版本 | load 要求 metadata 是 Map、version `is int && == 1`、rooms 是 Map | `1.0`、`'1'`、其他版本/错误 shape 都不能恢复来源 |
| code/ID/raw 恢复 | 每个 decoded room 用稳定 storageCode 查 kind，再 matchesContent 后才 withBuiltinKind | JSON 非 String code 不会等于已知 String code；wrong pair/unknown/missing 都失败 |
| legacy 覆盖 | decoded unmarked room 保持 kind=null；merge 仍 stored 后写覆盖 defaults | canonical 同 ID/text 的 legacy 也不从 defaults 借 marker |
| duplicate stored 同 ID | 对每个实际 decoded 对象独立验证；merge 最后一项覆盖 | 最后改名对象无 kind，不借前项 marker |
| durable save | `_save` 保留原 rooms/joinedRoomIds/activeRoomId，额外从当前有效 builtinKind 生成 builtinRoomCopy version/map | 不维护容易过期的第二份 registry；无有效项省略整个新增 key |
| public 操作保存 | joinRoom 先更新真实 active/joined 状态，再 await _save；create/accept 继续原路径 | 新明确来源通过正常业务操作进入存储，无 locale-driven save |
| remote 同 ID 覆盖 | acceptInviteCode 取得真实 API DTO，_upsert 对既有对象重新构造 raw fields，不携 kind；members/createdAt 沿用原规则 | 无论远端 copy 与 catalog 相同或不同，都丢本地显示来源 |
| remote 首次新增 | _upsert idx<0 直接加入 remote DTO room；此前已核对 converter 的构造默认 kind=null，新增测试也走 actual DTO 检查 | 当前实际调用路径不赋来源；未扩展新的来源推断 |

此轮没有 API 实现变更。model 原 `.name/.description` 仍为 raw final 字段；之前核对的 createInvite 继续消费 raw 字段。本次新测试通过实际 HTTP body 捕获验证这一调用契约，未用本地 nameFor 结果代替发送值。

## 新测试是否经过真实路径

**正向保存/恢复没有靠测试 helper 授予来源：** setUp 从真实 FocusRoomProvider.rooms 取得 app-created defaults；正向 test 自建 provider，调用公共 `joinRoom('reading_room')` 触发真实 _save，检查 SharedPreferences 里的完整 envelope，再新建 provider 并调用公共 loadFromStorage。会检查 raw room JSON、V1 map、active/joined 值、恢复后 kind/英译与 raw JSON，以及 locale 切换时 preferences/本地变化/通知计数不变。

`_metadata` 与 `_envelope` helper 只用于构造 explicit/invalid/stale/legacy 数据输入；它们没有用于伪造上述正向保存路径。直接 withBuiltinKind 只出现在错误 raw identity 失效测试。

覆盖实际行为包括：

- 三个真实 defaults 的 explicit-locale 标题/说明、raw JSON 不变，room JSON 注入 marker 也不能 fromJson 授权。
- wrong ID、changed raw name、changed raw description 都令显式 marker 失效。
- legacy canonical rooms 无 marker，实际 join/save 后仍无 marker，空 key 被省略。
- 用户 createRoom 使用恰好等于默认标题/说明仍 literal，真实保存/load 保留原值和目标。
- unknown/string/double version、non-Map metadata/rooms、unknown/non-String code、wrong code/ID、缺失目标 marker 均保留 membership 和 literal；mixed case 只恢复合法 entry。
- stale marker 在 load 时失效，实际 join/save 移除该 ID marker，后续新 provider load 仍保留修改 raw。
- remote case 先检查实际 InviteAcceptResult DTO，再调用 **公共 acceptInviteCode + MockClient**，检查真实请求 path、同 ID canonical/authored 覆盖、原 members/createdAt、marker 从持久化 map 消失与后续 reload。
- payload case 调用 **实际 FocusRoomApi.createInvite**，捕获 zh/en HTTP bodies 并比较一致，检查 raw name aliases、description、目标/颜色，以及无本地 metadata。

测试断言中的 display-kind 对比有部分共享实现 oracle，但 source review 已直接核对实际英文/中文 catalog 文本；`isNot(raw name)`、raw 保留及 legacy/remote 对照同时限制了误授权。它没有把所有名字作为翻译文本。

## 证据限制与有限后续

- 正向保存/恢复测试在旧 provider 尚未 dispose 时构造新 provider；它证明独立新实例读取持久化 envelope，不等于杀进程设备验收。当前 await save 完整、marker 恢复确实经过 fromJson/验证/withBuiltinKind，旧 provider 没有共享可变来源 registry，**这不是源码或验收 blocker**。如 root 希望严格贴合“dispose → 新实例”叙述，可在后续有限测试整理时显式关闭旧实例并调整 teardown。
- duplicate stored 同 ID 最后覆盖与 remote 新 ID 路径尚无单独新 case；逐对象 guard/原 merge 顺序及已核对的 DTO 默认 null 已提供明确源码边界。本审查不要求为了普通 source-pass 扩展新测试批次。
- 自动跑完与 analyzer 结果由 root 的当前串行窗口提供；此处未查询其状态，不能把 tests 源码存在写成“已通过”。
- global UI consumer 接入、open modal/controller lifetime、selector repaint 与 locale 时不触发业务/API 的 mounted 验收仍归 AGY/root 后续。这份 model/provider source-pass 不能替代 screen acceptance。
- 新生成并明确保存的默认来源长期保留；legacy/imported/remote 无来源名字继续 literal。该限制是保留原数据含义，不能为了旧中文显示回溯按 ID/text 归类。

**交付建议：保留本轮三个文件，等待 root 现有执行证据，再接入并验收 AGY 的固定 nameFor/descriptionFor consumers；无需生产修正。**
