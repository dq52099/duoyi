# CloudSync v2 契约（Task 23 / Requirements 12）

对齐 `.kiro/specs/app-alignment-overhaul/design.md §2.6`：客户端走 Offline-First，本地写入 → Provider 持久化 → CloudSync 排队 → ApiClient push。

## 特性开关

`lib/core/feature_flags.dart` 中 `FeatureFlags.cloudSyncV2`（默认 `false`）。
- 关闭：所有 Goal/Todo/Habit/Anniversary 只落本地 `SharedPreferences`，网络层不发请求；
- 开启：客户端按下述契约推送；失败进入排队 + 指数退避（≤5 次）。

## Goal 请求体（POST /api/v1/goals）

```jsonc
{
  "id": "<uuid v4>",
  "title": "string",
  "category": "recommend|health|study|sport|emotion|custom",
  "icon": "string",                        // MaterialIcons name
  "colorValue": 4294952960,
  "recurrence": {
    "frequency": "none|daily|weekly|monthly|yearly",
    "interval": 1,
    "byWeekdays": [0, 2, 4],               // 0=周一
    "byMonthDay": null,
    "endDate": null,                       // ISO local; 服务端存 UTC
    "maxOccurrences": null
  },
  "scheduling": {
    "mode": "fixed|random",
    "fixedWeekdays": [0, 2, 4],
    "fixedMonthDays": null,
    "randomMinGapDays": null,
    "randomMaxPerWeek": null,
    "randomMaxPerMonth": null
  },
  "skipHolidays": true,
  "focus": {
    "enabled": true,
    "presetId": "pomodoro-25",
    "focusSeconds": 1500,
    "whiteNoise": "rain"
  },
  "reminder": {
    "enabled": true,
    "kind": "push|alarm",
    "hour": 20,
    "minute": 0,
    "daysBefore": 0,
    "vibrate": true,
    "fullScreen": true
  },
  "timeTargetSeconds": 1800,
  "dailyTargetCount": 1,
  "tz": "Asia/Shanghai",                   // IANA 名
  "updatedAt": "2025-01-15T10:30:00+08:00"  // 本地 ISO with offset
}
```

## Todo 请求体（POST /api/v1/todos）

追加字段（相对旧版）：`reminder / focusLink / timeTargetSeconds / postponeHistory / autoToggleByChildren / isArchivedAfterRollover`。schema 与 `lib/models/todo.dart.toJson()` 的输出 1:1。

## 时间规范

- 请求体的所有 `DateTime` 字段使用 **客户端本地 ISO** 并附 `tz`；
- 服务端只存 **UTC + tz 名** 两列；
- 响应时返回 UTC，客户端用 `LocalTimezoneResolver.currentIana` 转回本地展示。

## 离线队列与重试

- 断网写入先持久化到 `SharedPreferences` 下的 `cloud_sync_queue`；
- 联网后按 `exponential backoff` 重放：`base=1s, factor=2, maxAttempts=5`；
- 每次尝试后持久化"最后状态"（`pending / syncing / failed / synced`）；
- UI 侧在有 `pending` 时显示红点角标（建议挂在 `MineScreen` 头像或侧栏）。

## 客户端待改点（Task 23 的剩余子任务）

| 子任务 | 文件 | 说明 |
|--------|------|------|
| 23.2 | `lib/services/cloud_sync_provider.dart` / `lib/services/api_client.dart` | 调用点判读 `FeatureFlags.cloudSyncV2`；请求体按本文档 schema 构造；队列 + 指数退避。 |
| 23.3 | `backend/main.py` | 已验证：当前存储为 opaque JSON TEXT + `_merge_by_timestamp` on list items，新 Goal/Todo 字段自动直通，无需服务端 schema 变更。未来若要按字段级索引查询（如"按 kind=alarm 过滤"），再单独加列。 |
| 23.4 | `lib/screens/mine_screen.dart` / `lib/widgets/...` | "有未同步改动"角标（命中 cloud sync 队列非空时显示）。 |

> 这三条属于**与后端联动**的工作；在没有 staging 可用的前提下，先冻结契约文档，等用户或 DevOps 放行再统一推流到后端与前端 ApiClient。CloudSync 队列的指数退避已有 `CloudSyncProvider` 雏形，`FeatureFlags.cloudSyncV2 = false` 时不触发任何网络行为，保障离线纯本地可用。
