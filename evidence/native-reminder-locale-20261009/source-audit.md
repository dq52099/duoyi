# Native locale foundation — 只读审阅（2026-10-09）

工作树：`/home/ubuntu/duoyi-worktrees/native-locale-20261009`。

结论：本批生产实现未发现阻挡提交的问题，可以作为原生 locale 基础链路提交。此结论来自 diff 与 source 阅读；未运行 tests、analyze、build、设备验收或 Git mutations，也未改动仓库。现有静态回归断言正在由独立代理同步，最终结果仍由根代理统一验收，不能据本报告声称测试通过。

## 已核对的传递链

| 链路 | 源码证据 | 结论 |
| --- | --- | --- |
| Dart bridge show / once / daily | `lib/services/native_reminder_ringtone.dart:48,60,74,87,104,120` | 三个入口接受 `AppLocale?`，缺省取 `I18n.current`，编码为 `zh` / `en`。其余 id、title、body、payload、trigger、timezone、option 字段保持原值。 |
| AlarmService 异步流程 | `lib/services/alarm_service.dart:647,943,1034`；调用处 `682,778,840,961,1002,1063,1142,1194` | 三个入口在首次 await 前保存 `nativeLocale`。全部八个 native 调用（包括后续分支及非精准回退）使用同一快照。 |
| Native channel 边界 | `MainActivity.kt:233` | showNow / scheduleOnce / scheduleDaily 显式传入非 `zh` / `en` 的 locale（含 null 或非字符串）返回 `invalid_locale`；未带 locale 的旧 native 调用继续使用 `zh`。英文缺 title / body 时使用英文默认文案。 |
| showNow / scheduleOnce / scheduleDaily / follow-up | `ReminderRingtoneScheduler.kt:47,93,130,211,652` | locale 进入服务或 receiver Intent，`baseIntent` 使用 helper 归一化并写入 extra。showNow 服务失败的通知 fallback 同样传递 locale。 |
| JSON 编码及恢复 | `ReminderRingtoneScheduler.kt:796,898` | JSON 持久化 locale；缺失旧 JSON locale 使用 `zh`。恢复 daily、未来 once、未来 follow-up、过期立即交付及过期 fallback 都传递 locale。英文 JSON 缺 title / body 使用英文默认值。 |
| daily successor | `ReminderRingtoneScheduler.kt:255` | receiver 的 locale 用于下一次 scheduleDaily；缺标题和内容也按该 locale fallback。 |
| receiver service / fallback / fullscreen | `ReminderRingtoneReceiver.kt:19,54,78,79,117` | receiver 获取并归一化 locale，在启动服务、兜底通知和兜底全屏 Activity 中均传递。 |
| service notification / fullscreen | `ReminderRingtoneService.kt:46,93,99,123,334,412` | 入口按 locale fallback 内容，正常通知与异常 fallback 使用同一 locale；通知的全屏 Intent 及直接启动 Activity 均携带 locale。 |
| snooze / auto-repeat | `ReminderRingtoneService.kt:57,69,369,385,129,434,459` | snooze PendingIntent 携带 locale，重建 follow-up 时继续传递；30 秒后的 auto-repeat 闭包使用本次服务入口快照，后继也携带该 locale。 |
| fullscreen 复用与日期 | `ReminderFullScreenActivity.kt:47,93,264` | `onNewIntent` 先更新 Activity Intent，再 render；每次 render 从显式 locale 重建时钟和日期格式器。日期不依赖设备默认 Locale，旧 intent 缺 locale 使用中文。 |

`ReminderNativeCopy.kt` 集中提供中英文提示、停止、打开详情、内容标签、稍后提醒文案及日期 pattern。`displayBody` 保留非空白标题和内容的字符，只增加对应语言的分隔符；相同标题/内容不重复展示。空白输入的 fallback 行为与原展示约定一致。

## 行为与边界

通过完整 diff 核对，动作字符串、提醒 id、rootId、follow-up id 算法、PendingIntent request codes、notification ids、渠道 ids、触发时间计算、daily weekdays/timezone、铃声、振动、snooze/repeatCount 选项及其范围限制均未改变。标题、正文和 payload 未被翻译或改写。JSON 额外写入 `repeatRemaining`，当前 restore 仍按既有 `repeatCount` 逻辑恢复，未改变重复行为。

审阅中曾发现 `encodeEntry` 的缺标题/正文保护分支仍有中文字面量。根代理随后修改为先取得 `ReminderNativeCopy`，title/body 默认值与 locale 共用该对象；已重新读取当前 `ReminderRingtoneScheduler.kt:898` 确认修正。此项已关闭。

初次读取现有 `test/services/native_reminder_ringtone_static_test.dart` 时，若干断言仍要求无 locale 的旧调用签名和中文按钮字面量（例如原 L406/L411/L417/L435/L480/L695/L860）。根代理说明独立代理正在更新；本审阅不将更新中的静态断言视为生产缺陷，也没有运行或宣称其最终通过。

## 保持 open 的后续工作

- 切换应用语言后的 pending-copy-refresh。本批保存的是注册时的 locale；不自动刷新已排程提醒的标题、正文或 locale。
- `currentOwnerEpoch` 与 registration nonce 的所有权及旧请求隔离。本批未实现这些机制；既有 deliveryToken 和去重行为没有升级。
- 诊断、权限错误、渠道名称/说明以及默认测试标题/正文等应用生成文案的完整语言覆盖。本批原生展示 chrome 可按 locale 切换，但不能因此声称英文提醒流程及系统设置页已全部英文化。
- 设备上真实 notification / fullscreen / reboot restore / snooze / auto-repeat 的验收，以及独立代理测试变更的最终检查，交由根代理完成。

审阅已完成；STOP。
