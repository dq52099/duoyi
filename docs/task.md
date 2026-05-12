# 多仪对标实现任务编排

本文档把 `docs/requirement.md` 和 `docs/design.md` 拆成可执行任务。任务按依赖顺序编排，
默认从上到下实施。状态含义：

- `[x]` 已完成
- `[~]` 进行中
- `[ ]` 未开始

## M0 文档与基线

- [x] T0.1 创建需求文档 `docs/requirement.md`
- [x] T0.2 创建设计文档 `docs/design.md`
- [x] T0.3 创建任务编排 `docs/task.md`
- [x] T0.4 建立 `docs/manual-regression-checklist.md` 的通知/小米专项章节
- [x] T0.5 为本轮新增能力创建 feature flag：`multi_reminder_v2`、`time_audit_v1`、`workspace_share_v1`

验收：

- 三份文档在仓库内可追踪。
- 后续每个 PR/task 能对应到 requirement id。

## M1 通知健康检查

依赖：M0

- [x] T1.1 新增 `PermissionHealthService`
  - 输入：NotificationService、AlarmService、PlatformInfo。
  - 输出：`NotificationHealthReport`。
  - 覆盖：通知权限、精准闹钟、渠道、厂商提示。
- [x] T1.2 偏好设置新增「通知健康检查」页面
  - 展示授权状态。
  - 展示测试通知。
  - 展示小米配置清单。
  - 提供系统设置跳转。
- [x] T1.3 提醒编辑器嵌入健康提示
  - 未授权显示橙色提示。
  - 已授权显示绿色状态。
  - alarm 缺精准闹钟时提示修复。
- [x] T1.4 App resumed 时刷新 health report 并触发提醒重排。
- [x] T1.5 增加 widget test 与手工回归清单。

验收：

- Android 未授权时页面显示未授权。
- 授权后返回应用状态刷新。
- 小米设备显示自启动/后台/锁屏/电池优化人工检查项。

## M2 多次提醒模型

依赖：M1

- [x] T2.1 新增 `ReminderRule` / `ReminderPlan` 模型。
- [x] T2.2 为 Todo/Goal 增加 `reminderPlan` 字段并保留 legacy 字段。
- [x] T2.3 实现 `ReminderPlan.fromLegacy(ReminderConfig)`。
- [x] T2.4 实现 JSON 兼容测试。
- [x] T2.5 更新 recommended goals / templates 的提醒配置迁移。
- [x] T2.6 更新导出/备份结构。

验收：

- 老数据能读。
- 新数据保存后仍保留必要 legacy 镜像。
- `flutter test test/models/...` 通过。

## M3 多次提醒调度

依赖：M2

- [x] T3.1 扩展 ReminderScheduler 支持 rule 粒度调度。
- [x] T3.2 设计稳定 id：`objectType:objectId:ruleId`。
- [x] T3.3 删除对象时取消全部 rule。
- [x] T3.4 修改 rule 时只重排该对象的相关规则。
- [x] T3.5 push/alarm 切换时双通道清理。
- [x] T3.6 单条调度失败不阻断整轮 sync。
- [x] T3.7 通知 payload 指向具体详情：`duoyi://todo/{id}`、`duoyi://goal/{id}`。
- [x] T3.8 增加属性测试。

验收：

- 一个对象 3 条提醒产生 3 条 pending。
- 修改/删除后没有残留。
- 时区切换后墙钟时间不变。

## M4 多次提醒 UI

依赖：M3

- [x] T4.1 抽取通用 `ReminderPlanEditor` widget。
- [x] T4.2 TodoDetail 接入新提醒编辑器。
- [x] T4.3 GoalEdit 接入新提醒编辑器。
- [x] T4.4 HabitDetail 接入 push-only plan。
- [x] T4.5 支持添加提前提醒、到期提醒、每日提醒、每周提醒。
- [x] T4.6 支持稍后提醒配置。
- [x] T4.7 增加 widget test。

验收：

- 用户能增删改多条提醒。
- 保存后 provider 持久化新 plan。
- UI 不依赖单个模块私有实现。

## M5 时间足迹模型与 Provider

依赖：M0

- [x] T5.1 新增 `TimeEntry` 模型。
- [x] T5.2 新增 `TimeAuditProvider`。
- [x] T5.3 SharedPreferences 持久化。
- [x] T5.4 增删改查 API。
- [x] T5.5 日/周/月聚合 API。
- [x] T5.6 JSON 兼容测试。
- [x] T5.7 接入导出/备份和云同步 payload。

验收：

- 新增一条时间记录后重启仍存在。
- 删除后统计同步变化。

## M6 时间足迹自动记录

依赖：M5

- [x] T6.1 PomodoroProvider 完成专注后写 TimeEntry。
- [x] T6.2 Todo 完成时提供记录耗时入口。
- [x] T6.3 Habit 打卡时支持补记时间。
- [x] T6.4 Goal 里程碑完成时可记录时间。
- [x] T6.5 防重复策略：同一 session 只能自动写一次。
- [x] T6.6 增加 provider 测试。

验收：

- 完成番茄自动产生时间记录。
- 同一次番茄不会重复写入。

## M7 时间足迹 UI 与统计

依赖：M6

- [x] T7.1 新增 `TimeAuditScreen`。
- [x] T7.2 我的页增加入口。
- [x] T7.3 统计页增加时间分布卡片。
- [x] T7.4 日历页显示 TimeEntry。
- [x] T7.5 支持手动补记弹层。
- [x] T7.6 支持编辑和删除记录。
- [x] T7.7 增加 widget test。

验收：

- 今日时间线可见。
- 分类占比可见。
- 手动补记能反映到统计。

## M8 日历统一详情与跨模块操作

依赖：M2、M5

- [x] T8.1 抽取 `CalendarAggregator`。
- [x] T8.2 标准化 Todo/Habit/Goal/Course/Countdown/Anniversary/Diary/TimeEntry 事件。
- [x] T8.3 实现冲突检测。
- [x] T8.4 新增 `CalendarEventSheet`。
- [x] T8.5 实现动作路由：跳转、完成、改期、删除。
- [x] T8.6 今日页和日历页共用排序。
- [x] T8.7 增加 widget test。

验收：

- 日历事件点击后可以直接处理。
- 改期能写回原模块。
- 冲突事件有明显标识。

## M9 课程表、倒数日、纪念日深化

依赖：M8

- [x] T9.1 课程表补学期、单双周、节次时间。
- [x] T9.2 课程进入 CalendarAggregator。
- [x] T9.3 倒数日支持提醒和分类。
- [x] T9.4 纪念日支持农历/公历提前提醒。
- [x] T9.5 统一详情跳转回原页面。
- [x] T9.6 增加模型测试。

验收：

- 单双周课程显示正确。
- 倒数日提醒由 ReminderScheduler 管理。

## M10 成就事件管线

依赖：M5

- [x] T10.1 新增 `DomainEventBus`。
- [x] T10.2 Provider mutation 发布领域事件。
- [x] T10.3 新增 `AchievementEngine`。
- [x] T10.4 成就规则数据化。
- [x] T10.5 成就页显示未解锁/进度/已解锁。
- [x] T10.6 解锁反馈接入通知历史。
- [x] T10.7 增加单元和 widget 测试。

验收：

- 连续打卡、完成待办、专注分钟触发成就进度。
- 解锁后重启仍保持。

## M11 共享空间后端

依赖：M0

- [x] T11.1 后端新增 workspace 表。
- [x] T11.2 后端新增 workspace member 表。
- [x] T11.3 后端新增 invite 表。
- [x] T11.4 `/api/workspaces` CRUD。
- [x] T11.5 `/api/workspaces/{id}/invites` 创建邀请码。
- [x] T11.6 `/api/invites/{code}/accept` 接受邀请。
- [x] T11.7 同步接口按 workspace 鉴权。
- [x] T11.8 后端测试。

验收：

- owner/editor/viewer 权限生效。
- viewer 不能提交写操作。

## M12 共享空间前端

依赖：M11

- [x] T12.1 新增 Workspace/Member/Invite 模型。
- [x] T12.2 新增 `ShareProvider`。
- [x] T12.3 我的页新增「共享空间」入口。
- [x] T12.4 待办清单支持设为共享。
- [x] T12.5 UI 显示共享标识。
- [x] T12.6 加入邀请码流程。
- [x] T12.7 editor/viewer 权限控制。
- [x] T12.8 同步 payload 接入 workspaceId。
- [x] T12.9 Widget/provider 测试。

验收：

- A 共享清单给 B，B 可见。
- viewer 无法编辑。
- 移除成员后不可继续同步。

## M13 小组件增强与深链

依赖：M3、M8

- [x] T13.1 深链路由支持具体对象。
- [x] T13.2 小组件列表项点击进入详情。
- [x] T13.3 小组件支持完成待办 action。
- [x] T13.4 小组件显示今日事件。
- [x] T13.5 数据变化后刷新摘要。
- [x] T13.6 Android 手工回归。

验收：

- 点击小组件待办直达详情。
- 完成待办后小组件刷新。

## M14 同步、备份、迁移收口

依赖：M2、M5、M11、M12

- [x] T14.1 同步 payload 加入 reminderPlan。
- [x] T14.2 同步 payload 加入 timeEntries。
- [x] T14.3 同步 payload 加入 workspace。
- [x] T14.4 备份导出/导入覆盖新增模型。
- [x] T14.5 老数据启动迁移测试。
- [x] T14.6 云端覆盖本地后重排提醒。
- [x] T14.7 端到端同步回归。

验收：

- 老用户升级不丢数据。
- 多设备同步后提醒/时间记录/共享状态一致。

## M15 发布验收

依赖：M1-M14

- [x] T15.1 `flutter analyze`
- [x] T15.2 `flutter test`
- [~] T15.3 Android release build。
- [ ] T15.4 小米真机通知回归。
- [ ] T15.5 GitHub Actions 构建。
- [ ] T15.6 发布 Release。
- [ ] T15.7 应用内检查更新验证。

验收：

- GitHub Release 包可下载。
- App 内检查更新可识别新版本。
- 核心回归清单通过。

## 推荐执行顺序

1. M1 通知健康检查。
2. M2 + M3 + M4 多次提醒完整闭环。
3. M5 + M6 + M7 时间足迹完整闭环。
4. M8 + M9 日历枢纽与课程/倒数日深化。
5. M10 成就事件管线。
6. M11 + M12 共享空间。
7. M13 小组件增强。
8. M14 同步备份迁移。
9. M15 发布验收。

## 每个任务的完成定义

- 有模型变更：必须有 JSON 兼容测试。
- 有调度变更：必须有 fake sink 测试，不依赖平台插件。
- 有 UI 变更：必须使用现有 surface components 和设计 token。
- 有同步变更：必须更新后端合同和备份导出。
- 有 Android 权限变更：必须更新手工回归清单。
- 任务完成后必须更新本文件状态。
