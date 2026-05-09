# Implementation Plan: App Alignment Overhaul锛堟寚灏栨椂鍏夊榻愭墦纾級

## Overview

鏈鍒掓寜 DAG 绮掑害鎷嗗垎瀹炵幇浠诲姟锛屾瘡涓换鍔?鈮?4 灏忔椂鍙畬鎴愩€備换鍔?1 涓哄湴鍩猴紙渚濊禆銆佹潈闄愩€佹椂鍖哄垵濮嬪寲銆丏esignTokens銆丄syncState锛夈€傚悗缁寜妯″潡涓茶/骞惰鎺ㄨ繘锛欸oal 鈫?鎺ㄨ崘鐩爣 鈫?Goal UI 鈫?Todo 妯″瀷/浜や簰 鈫?瀹屾垚鎬佷笌 DailyRollover 鈫?閫氱煡/闂归挓鍒嗗眰 鈫?ReminderScheduler 鈫?鐧藉櫔闊?鈫?鐣寗閽熸帴鍏?鈫?Today 璺敱 鈫?鏃ュ巻 鈫?绌烘灦瀛愭壂鎻?鈫?瑙嗚鎵撶（ 鈫?RecurrenceEngine + HolidayCalendar 鈫?鍚庣濂戠害 鈫?闆嗘垚娴嬭瘯銆?

**绾﹀畾**锛?
- `Requirements: X.Y` 寮曠敤 `requirements.md` 涓殑闇€姹傛潯鐩紱
- `PBT: Pn`锛堣嫢鍑虹幇锛夊紩鐢?`design.md` 绗?4 绔犵殑 Correctness Property锛岄渶瑕佸湪璇ヤ换鍔′腑浠ュ睘鎬ф祴璇曢獙璇侊紱
- 瀛愭楠ょ敤 `- step` 褰㈠紡鍒楀嚭锛屼綋鐜板彲鎵ц缁嗚妭銆?

## Tasks

- [x] 1. Foundation锛氫緷璧栥€佹潈闄愩€佹椂鍖恒€丏esignTokens銆丄syncState
  - 鍦?`pubspec.yaml` 涓柊澧?`audioplayers: ^6.x` 涓?`flutter_timezone: ^3.x`锛屽苟鎶?`assets/sounds/white_noise/` 鐩綍鎸傚埌 `flutter.assets`
  - 鍦?`android/app/src/main/AndroidManifest.xml` 澹版槑 `SCHEDULE_EXACT_ALARM`銆乣USE_FULL_SCREEN_INTENT`銆乣FOREGROUND_SERVICE` 鏉冮檺
  - 鍦?`AndroidManifest.xml` 澧炲姞 `<service android:foregroundServiceType="mediaPlayback"/>` 鍗犱綅锛堝悗缁櫧鍣煶鎺ュ叆鏃跺啀缁戝畾鍏蜂綋 service 鍚嶏級
  - 鏂板缓 `lib/core/local_timezone_resolver.dart`锛屾寜 `flutter_timezone 鈫?DateTime.now().timeZoneName 鈫?Asia/Shanghai` 椤哄簭鍥為€€锛屾毚闇?`init()` 涓?`currentIana`
  - 鍦?`main.dart` 棣栧抚涔嬪墠 `await LocalTimezoneResolver.init()`
  - 鏂板缓 `lib/core/design_tokens.dart`锛岄泦涓鑹层€佸渾瑙掋€侀棿璺濄€佸瓧闃躲€侀槾褰?token
  - 鏂板缓 `lib/core/async_state.dart`锛屽畾涔?`sealed class AsyncState<T>` 涓?`AsyncLoading/AsyncData/AsyncError`
  - Requirements: 1.1, 4.3, 8.1, 8.2, 8.3, 10.1, 10.3

- [x] 2. Goal 妯″瀷鎵╁睍锛圙oalCategory / Scheduling / Reminder / FocusLink锛?
  - [x] 2.1 鎵╁睍 `lib/models/goal.dart`锛氭柊澧?`GoalCategory`銆乣SchedulingMode`銆乣GoalScheduling`銆乣FocusLink`銆乣ReminderConfig`銆乣ReminderKind`
    - 鍦?`GoalItem` 涓婃柊澧?`category / icon / recurrence / scheduling / skipHolidays / focusLink / reminder / timeTargetSeconds / dailyTargetCount` 瀛楁
    - 瀹炵幇 `toJson / fromJson`锛屽缂哄け瀛楁浣跨敤瀹夊叏榛樿鍊?
    - Requirements: 1.1, 1.2
  - [x] 2.2 缂栧啓 `GoalItem` JSON 鍚戝悗鍏煎鍗曟祴*
    - 鏋勯€犳棫鐗?JSON锛堢己澶辨柊瀛楁锛夛紝鏂█鍙嶅簭鍒楀寲鎴愬姛骞惰ˉ榛樿鍊?
    - 搴忓垪鍖栧悗鍐嶅弽搴忓垪鍖栧緱鍒扮粨鏋勭瓑浠峰璞?
    - Requirements: 1.2
  - [x] 2.3 涓?`GoalEditScreen` 琛ㄥ崟鏍￠獙琛ュ厖杈撳叆鍚堟硶鎬у嚱鏁?
    - 妫€鏌?`randomMinGapDays 鈮?1`銆乣fixedMonthDays 鈯?[1..31]`銆乣fixedWeekdays 鈯?[0..6]`銆乣dailyTargetCount 鈮?0`
    - Requirements: 1.6, 1.7, 1.8, 1.10

- [x] 3. RecommendedGoalsLibrary锛堟帹鑽愮洰鏍囧簱锛?
  - [x] 3.1 鏂板缓 `lib/core/recommended_goals.dart`
    - 瀹氫箟 `RecommendedGoal` 涓?`RecommendedGoalsLibrary`
    - 鍦?`all()` 涓寜 `health / study / sport / emotion / recommend` 浜旂被鍐呯疆鑷冲皯 25 鏉℃潯鐩紙姣忕被 鈮?5锛?
    - 瀹炵幇 `byCategory(c)` 涓?`instantiate(r) 鈫?GoalItem`锛坄id` 涓烘柊 UUID锛?
    - Requirements: 1.3, 1.4
  - [x] 3.2 RecommendedGoalsLibrary 鍗曟祴*
    - 鏂█ `all().length 鈮?25` 涓旀瘡绫?`鈮?5`
    - 鏂█ `instantiate(r)` 鐢熸垚鐨?`GoalItem.id` 涓庡叾浠栭」涓嶅啿绐?
    - Requirements: 1.3, 1.4

- [x] 4. Goal UI锛歊ecommendedGoalsPicker + GoalEditScreen 鍒嗘ā鍧楃紪杈?
  - [x] 4.1 鏂板缓 `lib/screens/recommended_goals_picker.dart`
    - 椤堕儴绫诲埆鍒嗘鎺т欢锛屼笅鏂圭綉鏍?鍒楄〃灞曠ず鎺ㄨ崘椤?
    - 鐐瑰嚮鍚庤皟鐢?`GoalProvider.applyRecommended(r)` 鍐欏叆鏈湴
    - Requirements: 1.3, 1.4
  - [x] 4.2 鏂板缓/閲嶆瀯 `lib/screens/goal_edit_screen.dart`
    - 鍒嗘ā鍧楁姌鍙狅細鍩虹淇℃伅 / 閲嶅瑙勫垯 / 璋冨害妯″紡 / 璺宠繃鑺傚亣鏃?/ 涓撴敞鑱斿姩 / 鎻愰啋 / 鐩爣鏃堕暱 / 姣忔棩娆℃暟
    - 姣忎釜妯″潡鐙珛淇濆瓨鎸夐挳锛岃蛋 `GoalProvider.update`
    - 灞曠ず"涓嬩竴娆℃淳鍙戞棩"锛堣皟鐢?`RecurrenceEngine.nextOccurrence`锛?
    - Requirements: 1.5, 1.9
  - [x] 4.3 `GoalProvider.applyRecommended / update / onTimezoneChanged`
    - 鍦?`lib/providers/goal_provider.dart` 瀹炵幇鎴栬ˉ榻愯繖浜涙柟娉?
    - `onTimezoneChanged` 鍐呴儴璋冪敤 `ReminderScheduler.syncGoals`
    - Requirements: 1.4, 8.6

- [x] 5. Todo 妯″瀷鎵╁睍锛圧eminderConfig / FocusLink / PostponeHistory / timeTargetSeconds锛?
  - [x] 5.1 鎵╁睍 `lib/models/todo.dart`
    - 鏂板 `focusLink / reminder / timeTargetSeconds / postponeHistory` 瀛楁
    - 瀹氫箟 `PostponeRecord {from, to, reason, at}`
    - `toJson / fromJson` 瀵圭己澶卞瓧娈靛～鍏呭畨鍏ㄩ粯璁?
    - Requirements: 2.1, 2.2
  - [x] 5.2 Todo JSON 鍚戝悗鍏煎鍗曟祴*
    - 鏃х増 JSON 鍙嶅簭鍒楀寲琛ラ粯璁ゅ€?
    - Requirements: 2.2

- [x] 6. Todo 浜や簰锛氬瓙浠诲姟鑱氬悎 + autoToggleByChildren
  - [x] 6.1 鍦?`TodoProvider` 鏂板 `toggleSubtask(todoId, subId)` 涓?`recomputeParent(todoId)`
    - 鎸?`done/total` 璁＄畻 `subtaskProgress`
    - 鎸?`autoToggleByChildren` 鍙屽悜鑱斿姩鐖朵换鍔?`isCompleted` 涓?`completedAt`
    - Requirements: 2.6, 2.7, 2.8, 2.9, 3.6
  - [x] 6.2 瀛愪换鍔¤仛鍚?PBT*
    - 闅忔満鐢熸垚甯﹁嫢骞插瓙浠诲姟鐨?`TodoItem`锛屽嬀閫夊叏閮ㄥ悗鏂█ `subtaskProgress = 1.0`
    - 鍦?`autoToggleByChildren = true` 涓嬫柇瑷€鐖跺瓙鐘舵€佸弻鍚戜竴鑷?
    - PBT: P6, P7
    - Requirements: 2.6, 2.7, 2.8, 2.9

- [x] 7. Todo 浜や簰锛氭爣绛?/ 浼樺厛绾?/ 鐩爣鏃堕暱 / 鎻愰啋璁剧疆 UI
  - 鍦?`TodoDetailScreen` 鎺ュ叆 TagChips銆佷紭鍏堢骇鍒嗘鎺т欢銆佺洰鏍囨椂闀块€夋嫨鍣ㄣ€佹彁閱掑紑鍏筹紙push / alarm 鍒囨崲锛?
  - 鍦ㄥ垪琛ㄩ」灞曠ず鏍囩鑳跺泭銆佷紭鍏堢骇鑹叉爣銆佺洰鏍囨椂闀垮墿浣欍€佷笅涓€娆℃彁閱?
  - Requirements: 2.1, 2.12

- [x] 8. Todo 浜や簰锛氶『寤剁畻娉?postponeOverdue
  - [x] 8.1 鍦?`TodoProvider` 瀹炵幇 `postponeOverdue(today)`
    - 閬嶅巻 todos锛屽 `!isCompleted 鈭?dueDate < today 00:00` 鐨勯」鎶?`dueDate` 椤哄欢鍒颁粖鏃ュ悓鏃跺埢
    - 杩藉姞 `PostponeRecord(reason="auto_daily_rollover")`
    - 瀵瑰紑鍚簡 reminder 鐨?todo 閫氱煡 `ReminderScheduler` 閲嶅悓姝?
    - Requirements: 2.10
  - [x] 8.2 postponeOverdue 骞傜瓑 PBT*
    - 闅忔満鏋勯€?overdue todos锛岃繛缁皟鐢ㄤ袱娆?`postponeOverdue`锛屾柇瑷€闄?`postponeHistory` 澧炲姞涓€鏉″ `dueDate` 涓嶅彉
    - 鏂█椤哄欢鍚?`dueDate 鈮?today 00:00` 涓?`hour/minute` 涓庡師 dueDate 涓€鑷?
    - PBT: P12, P13
    - Requirements: 2.10, 2.11

- [x] 9. TodoDetailScreen "淇濆瓨涓嶈繑鍥? 鐘舵€佹満
  - 鍦?`TodoDetailScreen` 寮曞叆鐘舵€?`{Clean, Editing, Saving, ConfirmDiscard}`
  - AppBar check 鎸夐挳鍙寔涔呭寲涓?pop锛屼繚瀛樺悗 inline banner 鏄剧ず"宸蹭繚瀛?
  - 杩斿洖閿湪 `Editing` 涓嬪脊鍑?鏀惧純淇敼"瀵硅瘽妗?
  - 淇濆瓨澶辫触鍥炲埌 `Editing`锛宻nackbar 鎻愮ず
  - 缂栧啓璺敱蹇収鍗曟祴*锛氫繚瀛樺墠鍚?`ModalRoute.of(context).isCurrent` 淇濇寔 true
  - PBT: P18
  - Requirements: 2.3, 2.4, 2.5

- [x] 10. 瀹屾垚鎬佷繚鐣欑瓥鐣ワ紙CompletionVisibilityPolicy锛?
  - [x] 10.1 鏂板缓 `lib/core/completion_visibility_policy.dart`
    - 瀹炵幇 `shouldShowInToday(t, now)` / `visualState(t) 鈫?TodoVisualState`
    - 瀹氫箟 `enum TodoVisualState { normal, dueSoon, overdue, completed, archived }`
    - 灏嗗彲瑙嗙姸鎬佺粦瀹氬埌 `DesignTokens` 棰滆壊
    - Requirements: 3.1, 3.2
  - [x] 10.2 鍦?Todo 鍒楄〃 Widget 搴旂敤 `visualState`
    - `completed` 鈫?鍒犻櫎绾?+ 鐏板害 + 缁胯壊寰界珷
    - `dueSoon` 鈫?姗欒壊 + alarm icon 闂儊
    - `overdue` 鈫?绾㈣壊 + "杩囨湡"寰芥爣
    - `archived` 鈫?浠婃棩鍒楄〃涓嶆樉绀?
    - Requirements: 3.1, 3.2
  - [x] 10.3 "褰撴棩瀹屾垚涓嶉攢姣? PBT*
    - 闅忔満鏋勯€犱粖鏃?todos锛屽闅忔満涓€鏉?toggle 涓哄畬鎴?
    - 鏂█ toggle 鍚?`t 鈭?provider.todos 鈭?shouldShowInToday(t, now) = true 鈭?visualState = completed`
    - PBT: P4
    - Requirements: 3.1

- [x] 11. DailyRollover锛氬綊妗ｆ槰鏃ュ畬鎴?+ 椤哄欢 + 娲惧彂
  - [x] 11.1 瀹炵幇 `CompletionVisibilityPolicy.runDailyRollover(provider, now)`
    - 褰掓。鏄ㄦ棩 `isCompleted` 鐨?todos锛歚isArchivedAfterRollover = true`
    - 璋冪敤 `TodoProvider.postponeOverdue(today)`
    - 璋冪敤 `materializeTodayFromRecurring(today)`锛堣浠诲姟 22锛?
    - Requirements: 3.3, 3.4, 3.5, 3.6
  - [x] 11.2 鎺ュ叆瑙﹀彂鐐?
    - `main.dart` 鍐峰惎鍔ㄨ皟鐢ㄤ竴娆?
    - 鍦?`AppLifecycleState.resumed` 涓旀棩鏈熻法澶╂椂璋冪敤
    - Requirements: 3.3
  - [x] 11.3 Rollover 涓嶅彉寮?PBT*
    - 闅忔満鏋勯€?todos锛堝惈璺ㄦ棩銆佸惈瀹屾垚/鏈畬鎴愶級锛岃繍琛?`runDailyRollover(now)`
    - 鏂█ `{t | t.isArchivedAfterRollover} = {t | t.isCompleted 鈭?dateOnly(completedAt) < today}`
    - 鏂█ `isArchivedAfterRollover 鉄?isCompleted`銆乣isCompleted 鉄?completedAt 鈮?null`
    - PBT: P5, P19, P20
    - Requirements: 3.4, 3.5, 3.6

- [x] 12. NotificationService锛坧ush 閫氶亾锛屼粎 push锛?
  - 鎶界 `lib/services/notification_service.dart`锛屼粎璐熻矗 `duoyi_general` 閫氶亾
  - 鏆撮湶 `scheduleOnce(id, title, body, when, payload)` / `scheduleDaily(...)` / `cancel(id)` / `cancelAll()`
  - 鍒濆鍖?Android/iOS 閫氶亾锛岃缃?`Importance.high`
  - Requirements: 4.1, 4.2

- [x] 13. AlarmService锛坅larm 閫氶亾锛屽叏灞?+ 绮惧噯闂归挓锛?
  - [x] 13.1 鏂板缓 `lib/services/alarm_service.dart`
    - 鍗曚緥 `AlarmService.instance`锛屾毚闇?`init / scheduleFullScreen / cancel / cancelAll / requestExactAlarmPermission`
    - Android 浣跨敤 `duoyi_alarm` 閫氶亾锛宍Importance.max`锛宍fullScreenIntent=true`锛宍vibrationPattern=[0,500,500,500]`锛宍category=alarm`
    - iOS 浣跨敤 `interruptionLevel=.timeSensitive`
    - `scheduleFullScreen` 鍐呴儴璧?`flutter_local_notifications.zonedSchedule`锛宍tz.TZDateTime.from(when, tz.local)`
    - Requirements: 4.1, 4.2, 4.3, 4.5
  - [x] 13.2 Android 12+ 绮惧噯闂归挓鏉冮檺鍥為€€
    - `requestExactAlarmPermission()` 杩斿洖 bool锛屽け璐ョ粰鍑哄紩瀵?
    - Requirements: 4.9

- [x] 14. ReminderScheduler 澧炲己锛堝箓绛?+ kind 璺敱 + resyncAll锛?
  - [x] 14.1 鍦?`lib/services/reminder_scheduler.dart` 澧炲己鐜版湁瀹炵幇
    - 鏆撮湶 `syncTodos / syncHabits / syncAnniversaries / syncGoals / resyncAll`
    - `_dispatch(r, payload)` 鎸?`r.kind` 璺敱鍒?`NotificationService` 鎴?`AlarmService`
    - 骞傜瓑锛氬厛 cancel 鑷繁绠¤繃鐨?id锛屽啀鎸夋渶鏂版暟鎹笅鍙?
    - Requirements: 4.1, 4.4, 4.5, 4.7, 4.8
  - [x] 14.2 鏃跺尯鍙樻洿 resync hook
    - `AppLifecycle.resumed` 鏃跺姣?`LocalTimezoneResolver.currentIana` 涓庣紦瀛樺€硷紝涓嶅悓鏃?`tz.setLocalLocation` 骞?`resyncAll`
    - Requirements: 8.6, 8.8
  - [x] 14.3 閫氶亾璺敱 PBT*
    - 闅忔満鐢熸垚 `ReminderConfig(kind=push|alarm)`锛宮ock NotificationService / AlarmService
    - 鏂█ push 鈫?璋冪敤 NotificationService 涓斾娇鐢?`duoyi_general`锛沘larm 鈫?璋冪敤 AlarmService 涓斾娇鐢?`duoyi_alarm`
    - PBT: P14
    - Requirements: 4.4, 4.5
  - [x] 14.4 绂佹 Toast 鍐掑厖鎻愰啋 闈欐€佹壂鎻忔祴璇?
    - 鎵弿 `lib/` 涓皟鐢?`ScaffoldMessenger.showSnackBar` 鐨勪唬鐮佽矾寰勶紝鏂█涓?`ReminderConfig.enabled=true` 鐨勮Е鍙戣矾寰勪簰涓嶄氦鍙?
    - PBT: P15
    - Requirements: 4.6
  - [x] 14.5 鏃跺尯澹侀挓涓嶅彉 PBT*
    - 闅忔満鏋勯€?`ReminderConfig(kind=alarm, hour=H, minute=M)` 涓?tz1 / tz2
    - 鍏堝湪 tz1 涓?sync锛屽啀鍒囧埌 tz2 resyncAll锛屾柇瑷€鏂拌皟搴︾殑 `tz.TZDateTime` 鍦?tz2 涓嬩粛 `hour=H, minute=M`
    - 鏂█鏈€缁?`tz.TZDateTime.location 鈮?tz.UTC`
    - PBT: P1, P2, P3
    - Requirements: 8.5, 8.7, 8.8

- [x] 15. FocusSoundService锛堢湡瀹炵櫧鍣煶锛?
  - [x] 15.1 鏂板缓 `lib/services/focus_sound_service.dart`
    - 鍩轰簬 `audioplayers`锛宍ReleaseMode.loop` + `PlayerMode.lowLatency`
    - 鏆撮湶 `play(sound) / stop() / setVolume / fadeIn / fadeOut / bindLifecycle / currentSound / isPlaying / volume`
    - `play('none')` 绛変环 `stop()`
    - Requirements: 5.2, 5.3, 5.4, 5.9
  - [x] 15.2 鍑嗗鐧藉櫔闊宠祫婧?
    - 鍦?`assets/sounds/white_noise/` 鏀剧疆 `rain.mp3 / forest.mp3 / cafe.mp3 / waves.mp3`锛堝崰浣嶇┖闊抽涔熼渶瀛樺湪锛岀敱浜у搧渚ф浛鎹級
    - Requirements: 5.1
  - [x] 15.3 Android ForegroundService for mediaPlayback
    - 鍦?`AndroidManifest.xml` 娣诲姞 media playback service 澹版槑
    - 纭閿佸睆涓嶈绯荤粺 kill
    - Requirements: 5.7
  - [x] 15.4 杩佺Щ鏃?`AudioService`
    - 灏?`lib/services/audio_service.dart` 浣滀负 deprecated shim锛屽唴閮ㄨ浆鍙戝埌 `FocusSoundService`
    - Requirements: 9.2

- [x] 16. PomodoroScreen 鎺ュ叆鐧藉櫔闊?
  - 鍦?`PomodoroProvider.start/pause/reset/complete` 涓┍鍔?`FocusSoundService.play/fadeOut`
  - `break` 闃舵鎸?`config.playSoundInBreak` 鍐冲畾鏄惁缁х画
  - `AppLifecycle.resumed` 鏃舵寜 `isRunning` 鎭㈠
  - Pomodoro 鎺ュ叆 PBT*锛氶殢鏈哄惎鍋滃簭鍒楋紝鏂█ `isRunning = true 鈭?sound 鈮?'none'` 鏃?`FocusSoundService.isPlaying = true`锛屽仠 500ms 鍐?`isPlaying = false`
  - PBT: P16, P17
  - Requirements: 5.5, 5.6, 5.8

- [x] 17. TodayDetailRouter 淇
  - 鏂板缓 `lib/screens/today_detail_router.dart`锛屽畾涔?`TodaySectionKind 鈭?{todos, courses, anniversaries, goals, habits, diary}`
  - 鎶?`today_screen.dart` 涓?section `onMore` 鐨勭洿鎺?`Navigator.push` 鏇挎崲涓?`TodayDetailRouter.open(ctx, kind, id: 鈥?`
  - 鍦ㄨ矾鐢卞唴閮ㄥ绌烘暟鎹蛋 `EmptyState`锛屽紓甯歌蛋 `ErrorState`
  - 缂栧啓 widget 娴嬭瘯锛氬姣忎釜 `kind` 鏋勯€犵┖鏁版嵁鍦烘櫙锛屾柇瑷€涓嶈烦榛戝睆
  - Requirements: 6.1, 6.2, 6.3, 6.4, 6.5

- [x] 18. CalendarMonthGrid 鏀寔鐐瑰嚮 + CalendarScreen 鑱氬悎
  - [x] 18.1 澧炲己 `lib/widgets/calendar_month_grid.dart`
    - 鏂板 `OnDayTap? onDayTap` 涓?`DateTime? selectedDay`
    - 閫変腑鏃ヨ瑙夐珮浜?
    - Requirements: 7.1, 7.2
  - [x] 18.2 閲嶆瀯 `lib/screens/calendar_screen.dart`
    - 璁㈤槄 `selectedDay`锛岃仛鍚堝綋鏃?`TodoItem + Anniversary + Course + GoalOccurrence + HabitOccurrence`
    - 鏃犱簨椤规椂灞曠ず `EmptyState`锛堝惈"鏂板缓"蹇嵎鍏ュ彛锛?
    - 鐐瑰嚮鍙︿竴澶╃珛鍗冲埛鏂?
    - Requirements: 7.3, 7.4, 7.5

- [x] 19. EmptySurfaceAuditor锛氭壂鎻?+ 浜у嚭 backlog
  - [x] 19.1 鏂板缓 `lib/core/empty_surface_auditor.dart`
    - 瀹氫箟 `EmptySurfaceEntry {file, reason, fixTicketId?}` 涓?`EmptySurfaceAuditor`
    - 鍦?`known` 涓缃?`lib/services/audio_service.dart` 涓?`lib/screens/today_screen.dart` 涓ゆ潯
    - 鏆撮湶 `runtimeAudit(BuildContext) 鈫?EmptyAuditReport`
    - Requirements: 9.1, 9.2
  - [x] 19.2 缂栧啓鎵弿鑴氭湰锛堟垨 Makefile / 鏂囨。鍖栧懡浠わ級
    - 鍩轰簬 `grep` 鎼滅储 `TODO / FIXME / Placeholder / 鍋囨暟鎹?/ mock / hardcoded`
    - 鎼滅储浠呰繑鍥?`Container()` / `SizedBox()` 鐨?build 鏂规硶
    - 鎼滅储绔嬪嵆 resolve 鐨?`Future.value()` / 绌?`async {}`
    - 杈撳嚭鍐欏叆 `docs/empty-surface-audit.md`
    - Requirements: 9.3, 9.4
  - [x] 19.3 鎶?backlog 鏉＄洰涓庝换鍔?id 鍙屽悜寮曠敤
    - 淇鍚庡湪 `EmptySurfaceEntry.fixTicketId` 濉叆 tasks.md 涓搴斾换鍔?id
    - Requirements: 9.5

- [x] 20. 瑙嗚鎵撶（锛欵mptyState / LoadingState / ErrorState 涓変欢濂?
  - 鍦?`lib/widgets/result_states.dart` 瀹炵幇涓変欢濂?
    - `EmptyState` 鎺ユ敹 `title / description / icon / action`
    - `LoadingState` 鐢?shimmer
    - `ErrorState` 鎺ユ敹 `error / onRetry`
  - 鍦ㄥ叏閲?Provider/Screen 涓寜 `AsyncState` 鍒嗘敮鏇挎崲鎺夋棫鐨勭櫧灞?Container 绌烘€?
  - 缁熶竴浜屾纭瀵硅瘽妗嗘牱寮忥紙鏀惧純缂栬緫銆佺墿鐞嗗垹闄ゃ€佸彇娑堟彁閱掞級
  - Requirements: 10.2, 10.4, 10.5, 10.6, 10.7

- [x] 21. HolidayCalendar 鏈嶅姟
  - 鏂板缓 `lib/services/holiday_calendar.dart`
  - 鍐呯疆娉曞畾鑺傚亣鏃?JSON锛堣嚦灏戝綋鍓嶅勾 + 娆″勾锛夛紝鏀寔 `isHoliday(day) / isWorkMakeupDay(day)`
  - 鏆撮湶鍚庣画杩滅鍙洿鏂板叆鍙ｏ紙棰勭暀锛?
  - Requirements: 11.2

- [x] 22. RecurrenceEngine锛氬浐瀹?+ 闅忔満 + 璺宠妭鍋囨棩 + 绋冲畾绉嶅瓙
  - [x] 22.1 鏂板缓/閲嶆瀯 `lib/services/recurrence_engine.dart`
    - 瀹炵幇 `nextOccurrence(rule, scheduling, skipHolidays, anchor, {now})`
    - 瀹炵幇 `enumerateOccurrences(rule, scheduling, skipHolidays, start, end)`
    - 闅忔満妯″紡浣跨敤 `stableSeed(goalId, yearWeek(lowerBound))`
    - 璺宠妭鍋囨棩鏃堕亣鍒拌妭鍋囨棩 +1 day锛岀獥鍙ｈ秺鐣屽洖钀藉埌绐楀彛鍐呮渶鍚庝竴涓潪鑺傚亣鏃ユ垨杩斿洖 null
    - Requirements: 11.1, 11.3, 11.4, 11.5, 11.7
  - [x] 22.2 materializeTodayFromRecurring(today)
    - 閬嶅巻 active goals锛宍nextOccurrence == today` 鏃跺垱寤?occurrence 骞惰Е鍙?`ReminderScheduler.scheduleFor`
    - 鎺ュ叆 `DailyRollover`
    - Requirements: 11.8
  - [x] 22.3 RecurrenceEngine PBT*
    - 闅忔満 rule/scheduling/anchor锛屾柇瑷€ `1d 鈮?next-anchor 鈮?7k d`锛坵eekly锛?
    - 瀵?`endDate` 鏂█ `next = null 鈭?next 鈮?endDate`
    - 瀵?`skipHolidays = true` 鏂█ `isHoliday(next) = false`锛堟垨绐楀彛鍐呭叏鑺傚亣鏃ユ椂缁熶竴杩斿洖绛栫暐锛?
    - 鍚?`goalId` 鍚?`yearWeek` 澶氭璋冪敤杩斿洖鐩稿悓缁撴灉
    - PBT: P8, P9, P10, P11
    - Requirements: 11.3, 11.4, 11.6, 11.7

- [x] 23. 鍚庣濂戠害瀵归綈 + CloudSync feature flag
  - [x] 23.1 鍦?`lib/core/feature_flags.dart`锛堟柊寤烘垨娌跨敤锛夊畾涔?`cloud_sync_v2` 寮€鍏?
    - Requirements: 12.6
  - [x] 23.2 鎵╁睍 `lib/core/api_client.dart` / `lib/services/cloud_sync.dart`
    - 瀵归綈 `POST /api/v1/goals` 璇锋眰浣撳瓧娈?
    - 璇锋眰鏃舵惡甯?`tz` 瀛楁锛圛ANA 鍚嶏級涓?`toLocal().toIso8601String()` 鐨?datetime
    - 绂荤嚎鏃舵帓闃燂紝鑱旂綉鍚庢寚鏁伴€€閬块噸璇曪紙鈮?5 娆★級
    - Requirements: 12.1, 12.2, 12.3, 12.5, 12.7
  - [x] 23.3 鏇存柊 `backend/main.py`
    - 浠呭瓨 UTC + tz 鍚?
    - 瀵规柊瀛楁鍋氬悜鍚庡吋瀹硅В鏋?
    - Requirements: 12.4, 12.5
  - [x] 23.4 UI 渚ф湭鍚屾瑙掓爣
    - 鍦ㄥ悎閫備綅缃紙渚ц竟鏍?澶村儚瑙掞級灞曠ず"鏈夋湭鍚屾鏀瑰姩"
    - Requirements: 12.7

- [x] 24. Checkpoint锛氬崟鍏?+ 灞炴€ф祴璇曞叏缁?
  - 杩愯 `flutter test` 鍏ㄩ噺閫氳繃
  - 瀵?P1鈥揚20 瀵瑰簲灞炴€ф祴璇曚换鍔★紙6.2 / 8.2 / 9 / 10.3 / 11.3 / 14.3 / 14.4 / 14.5 / 16 / 22.3锛夐獙璇佸叏缁?
  - 鏈夐棶棰樺嵆灏卞湴淇锛屼笉閬楃暀
  - Requirements: 鍏ㄩ儴

- [x] 25. 闆嗘垚娴嬭瘯 + 鎵嬪姩鍥炲綊
  - 缂栧啓 `integration_test/` 鐢ㄤ緥
    - 浠婃棩椤垫墍鏈?section "鏌ョ湅"鎸夐挳涓嶅啀榛戝睆锛堣鐩栫┖鏁版嵁銆侀敊璇€佹甯镐笁鎬侊級
    - Goal 浠庢帹鑽愬簱涓€閿坊鍔犲苟缂栬緫鍏ㄩ儴妯″潡鍚庝繚瀛?
    - Todo 璇︽儏椤靛娆＄紪杈戜繚瀛樹笉杩斿洖銆佽繑鍥炵‘璁ゅ脊绐?
    - 鐣寗閽熷紑鍚櫧鍣煶锛屽彴鍚庡彴鍒囨崲涓嶆帀绾匡紝瀹屾垚鍚?500ms 鍐呴潤闊?
    - 鏃ュ巻鐐瑰嚮鏃ユ湡鍚庝笅鏂瑰垪琛ㄨ仛鍚堟纭€佺┖鏃ュ睍绀?EmptyState
    - 淇敼绯荤粺鏃跺尯鍚庨噸鏂颁笅鍙戠殑闂归挓澹侀挓鏃堕棿涓嶅彉
  - 鎵嬪姩鍥炲綊鑴氭湰锛氭寜 `docs/empty-surface-audit.md` 閫愭潯鍕鹃€変慨澶?
  - 纭繚 cloud_sync_v2 鍏抽棴鏃跺姛鑳藉畬鍏ㄥ彲鐢?
  - Requirements: 1.5, 2.4, 2.5, 5.5, 5.6, 6.1, 6.3, 6.4, 7.2, 7.5, 8.8, 9.4, 12.6

## Notes

- 浠诲姟鏍?`*` 涓哄彲閫夊瓙浠诲姟锛堝惈鍗曟祴 / PBT / 闈欐€佹壂鎻忔祴璇曪級锛屾寜 MVP 鏉冭　鍙鍓紱鏍稿績瀹炵幇浠诲姟涓嶅甫 `*`锛屽繀椤诲疄鐜般€?
- `PBT: Pn` 瀵瑰簲 `design.md 搂4` 鐨?P1鈥揚20锛涚紪鍐欐椂鍦ㄦ祴璇?tag 涓甫涓?`Feature: app-alignment-overhaul, Property n: <title>`銆?
- 浠诲姟 1 涓哄叾浣欎换鍔＄殑纭墠缃紱浠诲姟 2/5/15/21/22 鍙湪鍦板熀灏辩华鍚庡苟琛屻€?
- 浠诲姟 14锛圧eminderScheduler锛変緷璧?12 / 13锛屼换鍔?16 渚濊禆 15锛屼换鍔?11 渚濊禆 10/8/22銆?
- 姣忓畬鎴愪竴涓ぇ娈碉紙2鈥?銆?鈥?1銆?2鈥?6銆?7鈥?2锛夊缓璁汉宸ヨ蛋鏌ヤ竴娆″榻?`design.md 搂3`銆?

