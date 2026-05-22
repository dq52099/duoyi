# Empty Surface Audit（空架子清单）

对齐 `requirements.md` §9 / `tasks.md` Task 19。本文档由 **`lib/core/empty_surface_auditor.dart`** 中的 `known` 清单与 **`scripts/empty_surface_scan.ps1`** 脚本的粗扫结果共同维护。

## 维护约定

1. **静态白名单**：所有已知占位位点登记在 `EmptySurfaceAuditor.known`；在这里以可读表格的形式同步展示。
2. **修复后填 ticket id**：修一个空架子就把 `fixTicketId` 填上 tasks.md 里的任务 id（例：`17`、`22.1`），不要删条目，便于回溯。
3. **粗扫脚本**：`pwsh scripts/empty_surface_scan.ps1` 会把 `lib/` 下的 `TODO` / `FIXME` / `假数据` / `mock` / 仅 `return Container();` 的 build / 空 `async {}` 等写到 `docs/empty-surface-audit-raw.md`，与本表人工对照。
4. **CI / Flutter 测试**：`test/services/no_toast_reminder_static_test.dart` 限制了提醒派发层不得用 SnackBar 冒充提醒（R4.6 / P15），规则与本表互补。

## 已知占位清单（与 `EmptySurfaceAuditor.known` 同源）

| File | Reason | Ticket |
|------|--------|--------|
| `lib/services/audio_service.dart` | 旧版 AudioService 只切内存标记，不播真实音频 | ✅ **15.4**（改为转发到 `FocusSoundService` 的 deprecated shim） |
| `lib/screens/today_screen.dart` | 今日页 "查看" 原直接 `Navigator.push`，遇空数据会黑屏 | ✅ **17**（统一到 `TodayDetailRouter`） |
| `lib/services/recurrence_engine.dart` | `RecurrenceEngine` 已实现，编辑页"下一派发日"已改用 `RecurrenceEngine.nextOccurrence` | ✅ **22.1** |
| `lib/services/holiday_calendar.dart` | `HolidayCalendar` 已实现，2024-2026 节假日与调休数据已内置 | ✅ **21** |
| `lib/widgets/result_states.dart` | `EmptyState / LoadingState / ErrorState` 三件套已实现并统一导出 | ✅ **20** |
| `backend/main.py` | 后端 `cloud_sync_v2` 接口字段已和新 Goal/Todo 结构对齐，字段可直通 JSON TEXT | ✅ **23.3** |

> ✅ = 已闭环；⏳ = 进行中 / 待实现

## 扫描触发点

- **本地开发**：改了 UI 或 service 后，跑一次 `pwsh scripts/empty_surface_scan.ps1` 看 raw 输出有没有新增 hit。
- **CI**：建议在 `build-apk.yml` 中增加一个 `flutter test test/services/no_toast_reminder_static_test.dart` 步骤（已就位），作为回归闸。
- **发版**：在集成测试（Task 25）阶段逐条复核本表的 Ticket，没 `✅` 的条目不能发稳定版。
