# Calendar / Reminder fixture repair review

2026-10-09。只读核查根会话说明的有限夹具修复：Calendar水平lazy filter定位、popup关闭和pending-spinner等待；Reminder三处稳定Wrap key与对应选择断言。未改源码/fixture、运行测试/analyze/SDK/Git/网络或新增agent，也未重新审全frontend。

**修复方向及当前控制流通过源审阅，未发现可定位问题；可由根会话/Luna继续执行修复后的既有命令。** 本报告不包含运行通过声明。

## Calendar

同一lazy水平ListView目标未materialize的问题连续出现两次，适合用有限fixture滚动来修复。源码的`calendar_unified_filter_strip`下是水平ListView（calendar_screen.dart:519–525）；fixture用该key下的Scrollable，避免误滚动外层纵向列表或TabBar。

- fixture `350–373`：先用+180滚动找到较右侧的workspace并保留findsOneWidget，再用-180回到alpha后点击。Finder是查询而非旧Element，跨rebuild仍重新解析当前filter strip。alpha selected与两项alpha任务/排除other的业务断言保留。
- `387–397`：切Year后用-180显式找到左侧All projects，点击后仍检查selected和2 events；没有因为找不到目标而跳过断言。
- `410–432`：切3-Day后用+180找到alpha，保留2 items、排除1 item、literal task过滤和回中文日期/2项/0项等断言。正负方向与水平LTR strip的目标顺序一致；scrollUntilVisible仍在无法找到时失败，不把缺失转换成成功。
- `467–491`：先确认open menu在locale rebuild后保持同State、文案及literal内容，再从该menu的Navigator显式pop，settle后才点击底层project控件。该步骤修复fixture对modal阻挡的处理，不替代此前menu/state内容断言。
- pending time-log测试 `1288–1331`：gate尚未complete时只用pump/500ms有界pump，避免spinner使pumpAndSettle永不结束；gate.complete后才pumpAndSettle。仍断言provider只调用一次、nested route没有push、picker没打开、成功draft不残留、entry数量为1和无framework异常。

## Reminder

production的三个Wrap加了互不相同且与locale无关的常量ValueKey：relative offset（636）、snooze（789）、repeat count（819）。它们没有改变children/preset数值、selected表达式、origin检查、onSelected赋值、spacing或label构造；没有新增业务回调。稳定local key只标识已有三个分组，不能被描述为修改reminder行为或模型序列化。

fixture helper `_expectSelectedChoiceChip:916–929` 先在指定组key中匹配Text，再找ChoiceChip祖先，并继续断言恰好一个候选及selected=true。relative规则测试 `140–154` 分别指定offset/snooze/repeat组，消除offset30 min与snooze30 min的同名候选，而不是放宽为first/any。

既有保存断言 `170–180` 仍检查id/type/kind/hour/minute/offset/fullScreen/vibrate/snooze/repeat，locale来回与时间显示断言也保留。根会话说明未新增/删除test case；本轮核对的是当前相关控制流与断言，未运行历史diff或执行测试。

## 实际源指纹

| 文件 | SHA-256 |
| --- | --- |
| calendar `lib/screens/calendar_screen.dart` | `bc35b8ad9f03889144332ef811f3c345f2f8d74a3fac697e8a82b5d3a6c1a244` |
| calendar `test/screens/calendar_content_locale_state_test.dart` | `4a5e219c6ffa0a031c574ac1d242e8b0451988ac76aa6b3bd830a105f9492ea1` |
| reminder `lib/widgets/reminder_plan_editor.dart` | `37d90d6fca3de70289bb8715dbef6cf549ced5c9c678747d17346e184a21ee3b` |
| reminder `test/widgets/reminder_editor_locale_state_test.dart` | `fe6ca3eeb6a1897738b9b1620442a3b8f844b47c4cb6e513f5b22c6df153b964` |
| 两树 `lib/widgets/surface_components.dart` | `9ea733e62913e0f818f8c7c9d7e54bb5d99de3b053ec2973bd800ac4aec2c591` |

根路径：`/home/ubuntu/duoyi-worktrees/calendar-content-locale-20261009`；`/home/ubuntu/duoyi-worktrees/reminder-editor-locale-20261009`。Calendar生产hash与最终guard源审阅一致；Reminder hash因三个key更新，上表替代旧生产指纹。共享surface两树hash一致。
