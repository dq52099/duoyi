# 多仪 v2 升级任务清单

> 共 52 项任务，按里程碑分组。每项标注文件、依赖、验收标准。

---

## M0: P0 代码缺口修复

- [x] **T-01** Holiday Calendar 补充 2026 年中国法定节假日数据
  - 文件: `lib/services/holiday_calendar.dart`
  - 添加 2026 年元旦、春节、清明、劳动节、端午、中秋、国庆数据
  - 添加 2026 调休上班日数据
  - 验收: `HolidayCalendar.isHoliday(DateTime(2026, 1, 1)) == true`

- [x] **T-02** ReminderScheduler.syncTodos 直连替换 dynamic 兜底
  - 文件: `lib/providers/todo_provider.dart:530`
  - 将 dynamic 调用改为直接调用 `scheduler.syncTodos()`
  - 移除 `TODO(task-14)` 注释
  - 验收: postponeOverdue 后提醒重新调度

- [x] **T-03** ReminderScheduler.syncGoals 直连替换 dynamic 兜底
  - 文件: `lib/providers/goal_provider.dart:225`
  - 将 dynamic 调用改为直接调用 `scheduler.syncGoals()`
  - 移除 `TODO(task-14.1)` 注释
  - 验收: 目标变更后提醒重新调度

- [x] **T-04** Goal 编辑页集成 RecurrenceEngine.nextOccurrence
  - 文件: `lib/screens/goal_edit_screen.dart:528`
  - 依赖: T-01（节假日数据就绪）
  - 替换 `RecurrenceRule.nextAfter()` 为 `RecurrenceEngine.nextOccurrence()`
  - 验收: 带节假日跳过的目标显示正确下次派发日

- [x] **T-05** 纪念日提醒支持 alarm kind
  - 文件: `lib/providers/notification_service.dart:304`
  - 依赖: T-30（Anniversary 模型增加 reminderKind 字段）
  - 当 `kind=alarm` 时调用 `AlarmService.scheduleFullScreen`
  - 验收: 纪念日强提醒可全屏弹出

- [x] **T-06** 清理 AudioService 废弃引用
  - 文件: `lib/services/audio_service.dart`
  - 确认无残留引用，清理或标记
  - 验收: `grep AudioService` 无非注释引用

---

## M1: 日历枢纽强化

- [x] **T-07** 日历事件统一详情底部弹层
  - 新增/扩展 `CalendarEventActionSheet` widget
  - 显示: 标题、时间、来源模块标签
  - 操作: 完成/打卡/开始专注/改期/编辑/跳转详情/删除
  - 验收: 点击日历任意事件弹出统一操作面板

- [x] **T-08** CalendarActionRouter 跨模块操作分发
  - 新增 `CalendarActionRouter` 类
  - 依赖: T-07（操作面板就绪）
  - 完成操作写回 `TodoProvider`/`HabitProvider`/`GoalProvider`
  - 改期写回原模块
  - 验收: 在日历中完成待办后，待办列表同步更新

- [x] **T-09** 日历页按类型筛选
  - `CalendarScreen` 顶部增加类型筛选 chips
  - 支持多选/全选
  - 验收: 选中"习惯"后只显示习惯事件

- [x] **T-10** 日历冲突提示增强
  - `CalendarAggregator._markConflicts` 增加视觉标记
  - 详情面板显示冲突列表
  - 依赖: T-07（详情面板就绪）
  - 验收: 同时段课程+待办显示冲突标记

- [x] **T-11** 今日页与日历页共享排序规则
  - 抽取排序逻辑到 `CalendarAggregator`
  - `TodayScreen` 使用相同排序
  - 验收: 两个页面事件顺序一致

---

## M2: 多次提醒完善

- [x] **T-12** 稍后提醒 (Snooze) 功能
  - 通知 action 按钮: 5分钟后/10分钟后/30分钟后
  - 点击后重新调度一次性提醒
  - 验收: 点击"5分钟后"按钮，5分钟后再次收到通知

- [x] **T-13** 通知点击深链到具体详情
  - 确认所有通知 payload 格式统一为 `duoyi://type/id`
  - 验证 `TodayDetailRouter` 处理所有类型
  - 验收: 点击待办通知直接打开该待办详情页

- [x] **T-14** 单条提醒失败不中断整轮调度
  - `ReminderScheduler` dispatch 中已有 try-catch
  - 确认 `resyncAll` 中每个 sync 独立 try-catch
  - 输出 `ReminderHealthReport`
  - 验收: 模拟一条提醒注册失败，其余提醒正常下发

---

## M3: 通知健康检查完善

- [x] **T-15** MIUI/HyperOS 设备检测与清单
  - `PermissionHealthService` 增加 MIUI/HyperOS 品牌检测
  - 输出自启动、后台限制、锁屏通知的检查项
  - 验收: 小米设备显示专门配置清单

- [x] **T-16** 测试通知结果记录
  - 发送测试通知后记录时间和结果
  - 在通知健康页展示最近测试记录
  - 验收: 点击测试通知后列表新增一条记录

- [x] **T-17** 返回前台自动刷新权限
  - `WidgetsBindingObserver.didChangeAppLifecycleState` 中刷新权限
  - 权限变化后重新调度提醒
  - 验收: 从系统设置授权通知后返回应用，状态自动更新

---

## M4: 时间足迹集成

- [x] **T-18** 番茄完成自动生成 TimeEntry
  - `PomodoroProvider` 完成时发布 `DomainEvent`
  - `TimeAuditProvider` 订阅事件自动创建 `TimeEntry`
  - 验收: 完成25分钟番茄后时间足迹新增一条记录

- [x] **T-19** 待办完成时可选记录耗时
  - `TodoProvider.completeTodo` 后弹出可选耗时记录对话框
  - 依赖: T-18（TimeEntry 模型就绪）
  - 用户可跳过或输入耗时
  - 验收: 完成待办后弹出对话框，记录后时间足迹可见

- [x] **T-20** 统计页时间分布图表
  - `StatisticsScreen` 增加时间分布 section
  - 按模块/标签的饼图和趋势折线图
  - 使用 `fl_chart`
  - 依赖: T-18、T-19（有足够数据来源）
  - 验收: 统计页显示本周时间分布

- [x] **T-21** 日历页添加时间段入口
  - 日历详情面板增加"添加时间记录"操作
  - 依赖: T-07（详情面板就绪）、T-18（TimeEntry 模型就绪）
  - 验收: 从日历可直接创建时间记录

---

## M5: 共享协作 MVP

- [x] **T-22** 验证后端 workspace API 完整可用
  - 测试 `POST/GET /api/workspaces`, invites, members
  - 修复缺失字段或接口
  - 验收: curl 测试所有 workspace 接口返回正确

- [x] **T-23** 邀请码创建与加入流程
  - `ShareScreen` 增加创建邀请码 UI
  - 依赖: T-22（后端接口就绪）
  - 输入邀请码加入工作空间
  - 验收: A 创建邀请码，B 输入后加入空间

- [x] **T-24** 共享标识在列表展示
  - 待办/目标列表中共享项目显示共享图标
  - 依赖: T-22（workspace 数据可用）
  - 验收: 共享待办条目有明显的共享标记

- [x] **T-25** Viewer 权限限制
  - viewer 角色禁止编辑/删除/完成操作
  - 依赖: T-22（权限模型就绪）
  - UI 禁用相关按钮
  - 验收: viewer 无法编辑共享清单

---

## M6: 成就事件管线

- [x] **T-26** DomainEventBus 接入 AchievementEngine
  - `AchievementProvider` 订阅 `DomainEventBus.events`
  - 匹配成就规则触发解锁
  - 验收: 完成10个待办后自动解锁对应成就

- [x] **T-27** 解锁成就弹层反馈
  - 成就解锁时显示轻量 SnackBar 或 Overlay
  - 依赖: T-26（解锁逻辑就绪）
  - 不打断当前操作流
  - 验收: 解锁成就时底部显示提示

- [x] **T-28** 成就进度云同步
  - `achievement_states` 加入 `CloudSyncProvider` payload
  - 依赖: T-26（成就数据生成）
  - 验收: 登录新设备后成就进度恢复

---

## M7: 课程表/倒数日/纪念日深化

- [x] **T-29** 倒数日提醒集成 ReminderScheduler
  - `syncCountdowns` 已实现，确认完整覆盖
  - 验收: 倒数日到期提醒正常触发

- [x] **T-30** 纪念日 ReminderConfig.kind 概念引入
  - `Anniversary` 模型增加 `reminderKind` 字段
  - `ReminderScheduler.syncAnniversaries` 支持 alarm 路由
  - 验收: 强提醒纪念日全屏弹出

- [x] **T-31** 课程事件从日历深链到课程详情
  - 日历课程事件点击跳转 `CourseScheduleScreen`
  - 依赖: T-07（日历详情面板就绪）
  - 验收: 点击日历中的课程可查看课程详情

---

## M8: 小组件增强

- [x] **T-32** 小组件完成待办操作
  - Android widget 增加完成按钮
  - 通过 `MethodChannel`/`HomeWidget` 回调标记完成
  - 验收: 在桌面直接完成待办

- [x] **T-33** 小组件深链到具体对象
  - 确认 widget URI 正确跳转到详情
  - 依赖: T-13（深链路由就绪）
  - 验收: 点击小组件待办项进入该待办详情

- [x] **T-34** 数据变更推送小组件更新
  - `TodoProvider`/`HabitProvider` 变更时触发 `HomeWidgetService.pushUpdate`
  - 验收: 完成待办后小组件数量同步更新

---

## M9: 体验优化

- [x] **T-35** 统一 EmptyState/LoadingState/ErrorState 组件
  - `result_states.dart` 实现三件套
  - 替换各页面自定义空状态
  - 验收: 所有空状态视觉一致

- [x] **T-36** Backend cloud_sync_v2 schema 对齐
  - 后端 sync payload 字段与新 Goal/Todo 模型对齐
  - 新模型 `time_entries` 加入同步
  - 依赖: T-18（TimeEntry 模型就绪）
  - 验收: 同步后数据完整无丢失

- [x] **T-37** 全局搜索覆盖新模块
  - `GlobalSearch` 增加 TimeEntry、Workspace 搜索
  - 依赖: T-18（TimeEntry 就绪）、T-22（Workspace 就绪）
  - 验收: 搜索关键词可命中时间记录

- [x] **T-38** 备份导出包含所有新模型
  - `BackupService` 包含 `time_entries`、`achievement_states`
  - 依赖: T-18（TimeEntry 就绪）、T-26（成就数据就绪）
  - 验收: 备份导入后时间足迹完整

---

## M10: 智能化增强

- [x] **T-39** 中文自然语言日期解析
  - 解析"明天下午3点"、"下周一"、"后天"等表达
  - 集成到 `QuickCaptureFab`
  - 验收: 输入"明天下午3点开会"自动填充日期

- [x] **T-40** 看板视图
  - `TodoScreen` 增加看板视图切换
  - 自定义列分组
  - 验收: 可在看板和四象限间切换

---

## M11: 专注与习惯增强

- [x] **T-41** 专注标签分类统计
  - `PomodoroSession` 增加 `tag` 字段
  - 统计页按标签分类专注时间
  - 验收: 不同标签专注时间分别统计

- [x] **T-42** 习惯弹性打卡
  - `Habit` 模型增加 `weeklyTarget` 字段（如 5次/周）
  - UI 显示本周完成进度
  - 验收: 设置5次/周后显示 3/5 进度

---

## M12: 数据可视化

- [x] **T-43** 周报/月报生成
  - 自动汇总一周/一月的完成数据
  - 包括: 待办完成率、习惯坚持率、专注时长、目标进展
  - 依赖: T-18、T-20（时间数据和图表基础就绪）
  - 验收: 我的页面可查看本周报告

---

## M13: 测试与验证

- [x] **T-44** Holiday Calendar 2026 单元测试
  - 依赖: T-01
  - 验收: 覆盖所有法定假日和调休日断言

- [x] **T-45** ReminderScheduler syncTodos/syncGoals 集成测试
  - 依赖: T-02、T-03
  - 验收: 模拟待办/目标变更后验证提醒调度

- [x] **T-46** 日历冲突检测属性测试
  - 依赖: T-10
  - 验收: 随机生成事件组合验证冲突标记

- [x] **T-47** TimeEntry 自动生成测试
  - 依赖: T-18
  - 验收: 番茄完成事件触发 TimeEntry 创建

- [x] **T-48** Workspace 权限判断测试
  - 依赖: T-22、T-25
  - 验收: viewer/editor/owner 权限边界断言

- [x] **T-49** `flutter analyze` 零 error
  - 验收: 退出码为 0，无 error 级别问题

- [x] **T-50** `flutter test --no-pub` 全通过
  - 验收: 所有测试用例通过

- [x] **T-51** `python3 -m unittest discover -s backend` 全通过
  - 验收: 后端所有测试用例通过

- [x] **T-52** 手工回归清单更新
  - 更新 `docs/manual-regression-checklist.md`
  - 覆盖所有新增功能的回归路径
  - 验收: 清单覆盖 M0-M12 全部用户可见功能

---

## 依赖关系速查

```
T-01 ← T-04（节假日数据 → Goal 编辑页）
T-01 ← T-44（节假日数据 → 单元测试）
T-02 ← T-45（syncTodos → 集成测试）
T-03 ← T-45（syncGoals → 集成测试）
T-07 ← T-08, T-10, T-21, T-31（详情面板 → 操作分发/冲突/时间/课程）
T-10 ← T-46（冲突检测 → 属性测试）
T-13 ← T-33（深链路由 → 小组件深链）
T-18 ← T-19, T-20, T-21, T-36, T-37, T-38, T-47（TimeEntry → 下游）
T-22 ← T-23, T-24, T-25, T-37, T-48（Workspace API → 下游）
T-25 ← T-48（权限限制 → 权限测试）
T-26 ← T-27, T-28, T-38（成就引擎 → 下游）
T-30 ← T-05（纪念日模型 → alarm kind 支持）
```
