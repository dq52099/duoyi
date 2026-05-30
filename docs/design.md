# 多仪下一阶段架构设计

本文档承接 `docs/requirement.md`，描述为补齐共享协作、多次提醒、时间足迹、
日历枢纽和通知可靠性所需的工程设计。

## 1. 设计原则

- 保持 Flutter + Provider + 本地存储 + FastAPI 后端的现有架构。
- 新能力优先做成独立模型和 provider，再逐步接入 UI。
- 业务规则放在 core/services，页面只负责展示和交互。
- 调度、同步、迁移必须幂等。
- 所有平台插件调用隔离在 service 层，便于单元测试。

## 2. 当前架构摘要

```
lib/
  core/       主题、搜索、成就、模板、日期/完成策略
  models/     Todo/Habit/Goal/Recurrence/Course/Diary 等数据模型
  providers/  Provider 状态管理与 SharedPreferences 持久化
  services/   通知、闹钟、同步、AI、小组件、导出、系统托盘
  screens/    业务页面
  widgets/    统一组件与局部复用 widget
backend/      FastAPI auth/sync/admin/feedback/announcements
```

现有优势：

- 单机能力完整，Provider 边界清楚。
- ReminderScheduler 已经把 push 与 alarm 分开。
- CloudSyncProvider 已有同步入口。
- CalendarProvider 已有聚合方向。
- Surface components 已经提供统一 UI 基础。

主要不足：

- ReminderConfig 仍偏单条提醒。
- 日历事件不是所有模块的唯一操作入口。
- 缺少 TimeEntry 这种真实时间记录模型。
- 同步合同暂不支持 workspace / shared object。
- 成就规则与业务事件耦合不足。

## 3. 目标架构

```
User Action
   |
Provider mutation
   |
Domain event bus --------------> AchievementEngine
   |                                  |
   |                                  v
   +--> TimeAuditProvider        AchievementProvider
   |
   +--> CalendarAggregator
   |
   +--> ReminderScheduler
   |
   +--> CloudSyncProvider
```

核心变化：

- 所有关键业务动作产生轻量 domain event。
- 日历不直接读多个 provider 的 UI 字段，而是读规范化 event。
- 提醒从单 config 升级到 reminder plan。
- 时间足迹由自动事件和手动记录共同写入。
- 共享协作通过 workspaceId 进入所有可共享模型。

## 4. 数据模型设计

### 4.1 ReminderRule 与 ReminderPlan

```dart
enum ReminderRuleType {
  absolute,
  relativeToDue,
  dailyTime,
  weeklyTime,
}

class ReminderRule {
  final String id;
  final bool enabled;
  final ReminderRuleType type;
  final ReminderKind kind;
  final int? hour;
  final int? minute;
  final int? offsetMinutes;
  final List<int> weekdays;
  final bool vibrate;
  final bool fullScreen;
  final int snoozeMinutes;
  final int repeatCount;
}

class ReminderPlan {
  final bool enabled;
  final List<ReminderRule> rules;
}
```

兼容策略：

- 旧 `ReminderConfig` 保留一段时间。
- 新增 `ReminderPlan.fromLegacy(ReminderConfig old)`。
- Todo/Goal 优先读 plan；没有 plan 时从 legacy 迁移。
- Habit 先支持 push plan，后续再扩 alarm。

调度 id 策略：

```
stableId("$objectType:$objectId:$ruleId")
```

这样单条 rule 变更不会影响其它 rule。

### 4.2 TimeEntry

```dart
enum TimeEntryType {
  focus,
  todo,
  habit,
  goal,
  course,
  diary,
  manual,
}

enum TimeEntrySource {
  pomodoro,
  completion,
  calendar,
  manual,
  import,
}

class TimeEntry {
  final String id;
  final TimeEntryType type;
  final TimeEntrySource source;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final String? relatedType;
  final String? relatedId;
  final String title;
  final String? note;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String workspaceId;
}
```

写入来源：

- PomodoroProvider：专注完成自动写入。
- TodoProvider：完成待办时可弹出耗时记录。
- HabitProvider：打卡时按配置或手动补记。
- CalendarScreen：直接添加时间段。

### 4.3 Workspace / Share

```dart
enum WorkspaceRole { owner, editor, viewer }

class Workspace {
  final String id;
  final String name;
  final String ownerUserId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class WorkspaceMember {
  final String workspaceId;
  final String userId;
  final WorkspaceRole role;
  final DateTime joinedAt;
}

class ShareInvite {
  final String id;
  final String workspaceId;
  final WorkspaceRole role;
  final String code;
  final DateTime expiresAt;
  final bool revoked;
}
```

可共享对象增加字段：

- `workspaceId`
- `updatedAt`
- `deletedAt`
- `createdBy`
- `updatedBy`

初期可共享对象：

- todo list group
- calendar event
- goal

### 4.4 CalendarEvent 规范化

统一事件只作为视图模型，不替代原始数据。

```dart
class CalendarEventRef {
  final String type; // todo/habit/goal/course/countdown/anniversary/diary/timeEntry
  final String id;
}

class CalendarEvent {
  final CalendarEventRef ref;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final IconData icon;
  final Color color;
  final CalendarEventActionSet actions;
}
```

事件动作由 `CalendarActionRouter` 分发到原模块。

### 4.5 AchievementRule

```dart
class AchievementRule {
  final String id;
  final String title;
  final String description;
  final String eventType;
  final int target;
  final String metric;
}
```

规则可以先写在 `lib/core/achievements.dart`，后续再迁移为 assets JSON。

## 5. Provider 与 Service 设计

### 5.1 ReminderScheduler

扩展方向：

- 新增 `syncReminderPlans`.
- 内部维护 objectId/ruleId 到 channel 的映射。
- `resyncAll` 支持按 rule 粒度取消。
- 捕获单条失败并继续。
- 输出 `ReminderHealthReport` 给 UI。

### 5.2 PermissionHealthService

职责：

- 查询 NotificationService 权限。
- 查询 AlarmService 精准闹钟权限。
- Android 查询通知渠道状态。
- 识别 Xiaomi/MIUI 设备，输出人工检查项。
- 提供 `openAppSettings()` 统一入口。

注意：

- 自启动、后台限制等大多无法通过标准 Flutter API 精确读取，UI 应标记为
  “需要用户确认”，不伪造已授权状态。

### 5.3 TimeAuditProvider

职责：

- 持有 `List<TimeEntry>`。
- SharedPreferences 本地持久化。
- 提供按日/周/月聚合。
- 提供按类型、标签、关联对象过滤。
- 提供 create/update/delete。
- 接收 domain event 自动写入。

### 5.4 CalendarAggregator

职责：

- 从 Todo/Habit/Goal/Course/Countdown/Anniversary/Diary/TimeEntry 生成事件。
- 统一排序与冲突检测。
- 只输出视图模型，不直接持久化。

### 5.5 ShareProvider

职责：

- workspace 列表。
- 成员管理。
- 邀请码创建/加入。
- 权限判断。
- 标记共享对象 dirty，交给 CloudSyncProvider 上传。

### 5.6 DomainEventBus

轻量实现即可，不引入复杂框架。

```dart
class DomainEvent {
  final String type;
  final String objectType;
  final String objectId;
  final DateTime at;
  final Map<String, Object?> data;
}
```

Provider mutation 后 publish：

- todo.completed
- habit.checked
- pomodoro.completed
- goal.milestone.completed
- reminder.failed

## 6. 同步与后端设计

### 6.1 同步 payload 扩展

新增 collections：

- `time_entries`
- `workspaces`
- `workspace_members`
- `share_invites`
- `achievement_states`
- `reminder_plans`

每条记录统一字段：

- `id`
- `workspace_id`
- `updated_at`
- `deleted_at`
- `client_id`

### 6.2 后端接口

新增或扩展：

- `POST /api/sync`
- `POST /api/workspaces`
- `GET /api/workspaces`
- `POST /api/workspaces/{id}/invites`
- `POST /api/invites/{code}/accept`
- `PATCH /api/workspaces/{id}/members/{user_id}`
- `DELETE /api/workspaces/{id}/members/{user_id}`

### 6.3 冲突策略

- 普通字段：last-write-wins。
- list 字段：按 id 合并。
- 删除：`deleted_at` 高于普通更新。
- 共享权限：服务端为准。

## 7. UI 设计

### 7.1 通知设置

新增「通知健康检查」卡片：

- 系统通知权限
- 精准闹钟权限
- 通知渠道
- 测试通知
- 小米手机配置清单
- 重新调度提醒按钮

### 7.2 提醒编辑器

替换单条提醒编辑器为 rule list：

- 添加提醒
- 提前提醒
- 到期提醒
- 每日/每周提醒
- push/alarm 切换
- 全屏、震动、稍后提醒

### 7.3 时间足迹

新增入口：

- 我的 -> 时间足迹
- 统计页 -> 时间分布
- 日历详情 -> 添加时间记录

页面：

- 今日时间线
- 周统计
- 分类占比
- 手动补记弹层

### 7.4 共享

入口：

- 我的 -> 共享空间
- 待办清单菜单 -> 共享
- 日历事件详情 -> 共享状态

最小 UI：

- workspace 切换器
- 成员列表
- 邀请码
- 角色修改

### 7.5 日历统一详情

事件详情底部弹层：

- 标题、时间、来源模块
- 完成/打卡/开始专注
- 改期/编辑
- 跳转详情
- 删除

## 8. 迁移设计

### 8.1 Reminder 迁移

- 启动时不批量改写旧数据。
- 读取时 lazy migrate。
- 保存时写新 `reminderPlan`，保留 legacy 字段供旧版本降级。

### 8.2 TimeEntry 首次引入

- 不从历史番茄批量生成，避免误造历史数据。
- 只从上线后新事件开始记录。

### 8.3 Workspace 引入

- 所有旧数据默认 `workspaceId = "private"`.
- 云同步时服务端为每个用户创建 private workspace。

## 9. 测试设计

### 9.1 单元测试

- ReminderPlan JSON 兼容。
- TimeEntry JSON 兼容。
- Workspace 权限判断。
- CalendarAggregator 聚合和冲突检测。

### 9.2 属性测试

- 多提醒调度不重复。
- push/alarm 切换清理旧通道。
- 时区切换保持墙钟时间。
- 删除对象清理所有 rule。

### 9.3 Widget 测试

- 提醒编辑器增删改 rule。
- 时间足迹新增/删除。
- 日历事件详情操作。
- 共享空间 viewer 禁止编辑。

### 9.4 手工回归

- Android 13+ 通知权限。
- Android 12+ 精准闹钟。
- 小米自启动/锁屏/后台限制。
- 小组件深链。
- GitHub Release 更新。

## 10. 风险

- Android 厂商权限不可完全自动探测，需要明确 UI 文案。
- 多提醒引入后 id 管理复杂，必须先写测试。
- 共享协作会触及后端和同步合同，必须分阶段上线。
- 时间足迹可能增加用户输入负担，自动记录要默认安静。
- 日历统一操作会跨 provider 写入，必须保持边界清晰。

## 11. 分阶段交付

- M0：文档和任务编排。
- M1：通知健康 + 多提醒模型。
- M2：多提醒 UI + 调度。
- M3：时间足迹。
- M4：日历统一详情。
- M5：共享空间 MVP。
- M6：成就事件管线。
- M7：小组件和课程表/纪念日深化；倒数日保留可见入口和旧数据兼容。
