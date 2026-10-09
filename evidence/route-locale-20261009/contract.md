# Route locale and state contract — 2026-10-09

## Decision

Use a public widget marker, `LocaleStatePreservingRoute`, for the five target pages. `BrandRouteSurface` must use a stable subtree key for marked children. Each marked page must refresh its copy through `I18n.localeListenable` while keeping its existing State, controllers, provider fallback, and widget identity mounted.

Retain the Mine job's planned optional `bool remountOnLocaleChange = true` API. Compose it with the marker:

```dart
abstract interface class LocaleStatePreservingRoute {}

// BrandRouteSurface constructor remains const.
final bool remountOnLocaleChange;

// The marker is a state-retention contract and takes precedence over true.
final shouldRemount =
    remountOnLocaleChange && child is! LocaleStatePreservingRoute;

// Keep this wrapper at the same position in both branches.
KeyedSubtree(
  key: shouldRemount ? ValueKey<AppLocale>(locale) : null,
  child: child,
)
```

This is design pseudocode, not an implementation. Document the bool as allowing the legacy locale remount for **unmarked** children; `false` also preserves an unmarked self-refreshing route such as the Mine job's Profile route. A marked target must remain protected even when the argument is omitted or explicitly true. The existing unmarked const stateless route refresh behavior remains available. This decision adds no broader remount behavior and no new widget-type heuristic.

All five **public** widgets implement the marker: `TodoScreen`, `HabitScreen`, `CalendarScreen`, `PomodoroScreen`, and `IntegrationsScreen`. Put the interface beside `BrandRouteSurface` in `brand_background.dart` to keep this change within six production files and avoid screen imports in the shared wrapper. Todo and Integrations need an import of that file; the other three already use it.

## Source basis

The reviewed source is the main checkout `/home/ubuntu/duoyi`; the parent supplied HEAD `75d72d2`. No Git commands were used to establish or inspect that revision. The prior private audit was also read; its worktree links were not followed. The live Mine worktree was not accessed.

- [BrandRouteSurface](/home/ubuntu/duoyi/lib/widgets/brand_background.dart:82) already listens to `I18n.localeListenable` but places the whole child under [a locale-valued KeyedSubtree](/home/ubuntu/duoyi/lib/widgets/brand_background.dart:89). A changed key replaces descendant elements, including any State below a public stateless facade.
- [I18n.setLocale](/home/ubuntu/duoyi/lib/core/i18n.dart:2297) updates the static locale before notifying. [I18n.tr](/home/ubuntu/duoyi/lib/core/i18n.dart:2304) performs a lookup without registering a widget dependency. [AppBrand.strings](/home/ubuntu/duoyi/lib/core/app_brand.dart:50) similarly derives current-locale strings on access; reading an old `BrandStrings` object does not make that object live.
- Todo owns [view mode, filters, collapsed groups, selected IDs, and its scroll controller](/home/ubuntu/duoyi/lib/screens/todo_screen.dart:75), and [disposes the controller](/home/ubuntu/duoyi/lib/screens/todo_screen.dart:253). Habit owns [its TabController and heatmap-built flag](/home/ubuntu/duoyi/lib/screens/habit_screen.dart:38). Calendar owns [selected day, focused month, filters, and its TabController](/home/ubuntu/duoyi/lib/screens/calendar_screen.dart:58); its initial date is applied only in [initState](/home/ubuntu/duoyi/lib/screens/calendar_screen.dart:70).
- [PomodoroScreen](/home/ubuntu/duoyi/lib/screens/pomodoro_screen.dart:330) is a public **StatelessWidget**, but it returns a stateful body and optionally [a stateful provider fallback](/home/ubuntu/duoyi/lib/screens/pomodoro_screen.dart:359). The body owns [a three-tab controller](/home/ubuntu/duoyi/lib/screens/pomodoro_screen.dart:436). The fallback owns and disposes [its Pomodoro and other providers](/home/ubuntu/duoyi/lib/screens/pomodoro_screen.dart:369). With app-owned providers an outer remount resets local UI; with fallback-owned providers it also disposes the timer owner. Thus a claim that locale remounts never affect timers would be too broad.
- [IntegrationsScreen](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:27) is also a public **StatelessWidget**, with [a stateful provider fallback](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:60). Its body already uses [a locale ValueListenableBuilder](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:142), which rebuilds [an unkeyed, fixed-length DefaultTabController](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:149). The outer locale key currently defeats this existing listener.
- The [existing wrapper test](/home/ubuntu/duoyi/test/widgets/brand_route_surface_locale_test.dart:12) covers an unmarked const stateless translation probe. It has no State lifecycle assertion.

## Alternatives

| Approach | Source-informed result | Decision |
| --- | --- | --- |
| Public route marker + page notifier dependency | One declaration on each public route protects every existing direct wrapped call, including the two stateless facades. A page-owned dependency also works when no BrandRouteSurface exists. | Choose. Six production files suffice. |
| Flags at every push | Must cover Today, TodayDetailRouter, Search, main OAuth/location routes, Mine, More Apps, Calendar's Todo push, and Calendar event Focus routing. Generic helpers accept arbitrary `Widget` children, so a missed call silently reintroduces remounts. Direct shell/Calendar preview paths still need page dependencies. | Keep the bool for Mine compatibility and explicit decorated routes; do not use call-site flags as the primary design. |
| Shared inherited locale dependency | An inherited notifier refreshes widgets that explicitly depend on it; wrapping the subtree does not automatically make `I18n.tr` or arbitrary const children depend on it. Removing all route keys would leave the existing plain const stateless probe stale unless it is migrated. Inserting a scope only in BrandRouteSurface also omits direct shell tabs and the widget preview's direct Calendar push. A global scope and widespread dependency migration would exceed this bounded batch. | Defer; it also cannot survive an ancestor that still changes its locale key. |

Reject `child is StatefulWidget` as a safety rule: it misclassifies both Pomodoro and Integrations. Do not traverse `Element` descendants, invoke private rebuild methods, or force every stateful descendant dirty. Do not remove or add keys across the application as a substitute for explicit ownership of the locale dependency.

## Exact production scope and implementation contract

1. `lib/widgets/brand_background.dart`: define the marker, preserve the optional Mine bool, and compose the policy as above. Keep Material → BrandBackground → AppSecondaryControlTheme → KeyedSubtree nesting stable. Retain the existing locale notifier and theme background behavior. Update the current comment that describes every route as intentionally remounted.
2. `lib/screens/todo_screen.dart`: implement the marker on `TodoScreen`; subscribe the existing `_TodoScreenState` to the static notifier in `initState` and remove the same callback in `dispose`. The callback only schedules `setState` on a mounted state. Recompute current copy in build; do not reload kanban preferences or reset any filter/selection/cache/controller in response to locale.
3. `lib/screens/habit_screen.dart`: implement the marker and the same balanced listener in `_HabitScreenState`. Keep `_tabCtrl` and `_heatmapTabBuilt`. Change the [const SliverToBoxAdapter containing HabitWeeklyCard](/home/ubuntu/duoyi/lib/screens/habit_screen.dart:771) to create a fresh adapter/card widget instance during the page rebuild, retaining type/key/position. [HabitWeeklyCard's copy](/home/ubuntu/duoyi/lib/widgets/habit_weekly_card.dart:40) reads the locale but does not listen to it; an identical const child would otherwise be skipped during a raw notifier event. This requires no edit to `habit_weekly_card.dart` for the page contract.
4. `lib/screens/calendar_screen.dart`: implement the marker and the balanced listener in `_CalendarScreenState`. Keep selected/focused dates, all filters, the tab controller, and rebuild scheduling state. A locale event must not reapply `widget.initialDate` or mutate provider inputs. Read date/copy presentation at build time. Preserve existing data identities; any later localization of the cached aggregation belongs at a display boundary rather than rewriting stored titles.
5. `lib/screens/pomodoro_screen.dart`: implement the marker on the public `PomodoroScreen`, not only on `_PomodoroScreenBody`. Add the balanced listener to `_PomodoroScreenState`. Keep public facade/fallback/body nesting and all provider ownership intact. Change [const _FocusRoomTab](/home/ubuntu/duoyi/lib/screens/pomodoro_screen.dart:995) to a fresh unkeyed `_FocusRoomTab()` during the body rebuild, so its copy also rebuilds while [its keep-alive State and scroll key](/home/ubuntu/duoyi/lib/screens/pomodoro_screen.dart:2170) survive. Do not start, stop, recreate, or reload a timer on locale events.
6. `lib/screens/integrations_screen.dart`: implement the marker on the public `IntegrationsScreen`. Reuse the body's existing locale builder; avoid a second listener above the fallback. Change [const _LocationRemindersTab and _LocaleTab](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:178) to fresh unkeyed instances inside that builder. Their translated labels must refresh on `I18n.setLocale` independently of their business providers. Do not replace, key, or move the DefaultTabController or fallback.

A small in-file ValueListenableBuilder around a page's returned view is an acceptable equivalent to the explicit State listener only if controllers and drafts remain outside its builder and the returned subtree retains the same types/keys/positions. Prefer the balanced State listener for the four existing stateful bodies to avoid restructuring their large build methods.

No additional call-site production files are needed for the current source. Evidence:

- Main shell uses [stable page keys](/home/ubuntu/duoyi/lib/main.dart:5861), and widget URI tab destinations [navigate to those tabs](/home/ubuntu/duoyi/lib/main.dart:3855). Main's [OAuth callback push](/home/ubuntu/duoyi/lib/main.dart:3874) and [location push](/home/ubuntu/duoyi/lib/main.dart:3991) directly wrap Integrations. The public marker handles both. Its [generic fallback helper](/home/ubuntu/duoyi/lib/main.dart:4116) also passes its child through unchanged.
- [Today metric pushes](/home/ubuntu/duoyi/lib/screens/today_screen.dart:241) pass the public widgets unchanged through [its generic helper](/home/ubuntu/duoyi/lib/screens/today_screen.dart:607). [TodayDetailRouter's Todo](/home/ubuntu/duoyi/lib/screens/today_detail_router.dart:82) and [Habit](/home/ubuntu/duoyi/lib/screens/today_detail_router.dart:136) pass unchanged through [its generic helper](/home/ubuntu/duoyi/lib/screens/today_detail_router.dart:164).
- Search directly wraps [Habit](/home/ubuntu/duoyi/lib/screens/search_screen.dart:107) and [Calendar with initialDate](/home/ubuntu/duoyi/lib/screens/search_screen.dart:169). More Apps' public route factories are passed straight to [BrandRouteSurface](/home/ubuntu/duoyi/lib/screens/more_apps_screen.dart:428).
- Mine directly wraps [Pomodoro](/home/ubuntu/duoyi/lib/screens/mine_screen.dart:175) and [Integrations](/home/ubuntu/duoyi/lib/screens/mine_screen.dart:340). Calendar directly wraps [Todo](/home/ubuntu/duoyi/lib/screens/calendar_screen.dart:1354), and the event sheet directly wraps [Pomodoro](/home/ubuntu/duoyi/lib/widgets/calendar_event_sheet.dart:691).
- The desktop widget preview pushes [Calendar directly without BrandRouteSurface](/home/ubuntu/duoyi/lib/screens/widget_screen.dart:443). Its page-owned notifier listener covers that route.

The marker is intentionally not recursive. If a future call passes `Padding(child: CalendarScreen())` or another unmarked decorator into BrandRouteSurface, the decorator must implement the contract or that call must set `remountOnLocaleChange: false`. None of the current target call sites wraps the public page that way. An enclosing remounting BrandRouteSurface around a marked page would still dispose it; the actual route boundary must apply the preservation policy. The marker is checked on the public facade specifically so the actual current boundaries already do so.

## Integrations controller and fallback reasoning

Once the outer changing key is disabled, the existing locale builder creates another `DefaultTabController(length: 3)` at the same location with the same runtime type and key. Flutter updates that existing stateful element; the fixed length does not request a new controller or reset the selected index. Keep the wrapper tree and length unchanged. Merely creating a new Widget object is not a remount.

The provider fallback sits **above** `_IntegrationsScreenBody`. A locale event is consumed inside the body, so the fallback's State, its `late final` provider instances, and its one-time [loadFromStorage calls](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:89) survive. `ChangeNotifierProvider.value` continues exposing the same providers. Do not move locale-driven keyed elements around this fallback.

The calendar subscription tab remains an unkeyed StatefulWidget at the same position. Its [_handledInitialOAuthCallback guard](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:283) survives; [didUpdateWidget](/home/ubuntu/duoyi/lib/screens/integrations_screen.dart:295) only resets it when the callback URI changes. Changing language with the same URI must not open the OAuth dialog again. This is source reasoning, not executed verification.

## Invariants

- A marked route's State identity and descendant controllers/provider owners survive zh → en → zh events, with the route left mounted and no parent repump needed.
- Labels, date display, tooltips, and semantics that already use current-locale copy refresh on each event. Translate at build time; do not capture translated strings in State initialization or move locale into a state-bearing key.
- Refresh does not change user-entered text, domain IDs, group IDs, selected filters, tab indices, scroll controllers, provider state, theme choice, or navigation depth. Business state remains distinct from display labels.
- A locale subscription is attached once and removed once per State lifecycle; it performs no persistence, networking, provider reload, or timer action.
- Const translated descendants need their own dependency or fresh widget instances at the page build boundary. Preserve their elements using unchanged type/key/position.
- Mine's `remountOnLocaleChange: false` remains valid for unmarked self-refreshing pages. Existing constructor call sites remain const-compatible.

The contract does not finish all English translation coverage. Existing hardcoded page labels remain visible in source, for example [Calendar's Three days/Year tabs](/home/ubuntu/duoyi/lib/screens/calendar_screen.dart:891) and [Pomodoro's Study room tab](/home/ubuntu/duoyi/lib/screens/pomodoro_screen.dart:504). The content batch must migrate those labels to build-time copy. Open create/edit overlays have independent builders and captured strings; the subsequent editor migration is still required. The already available picker titleKey/subtitleKey API does not by itself migrate those editors. Do not solve editor gaps by remounting a whole route or resetting a draft.

## Future acceptance specifications — not run

### Stateful const probe

Extend the wrapper's existing probe coverage in a separately authorized verification batch:

1. Retain an unmarked `const StatelessWidget` that renders only `I18n.tr('nav.mine')`. With the default wrapper policy and a const MaterialApp, call only `I18n.setLocale`; copy must update. This proves preservation changes did not silently remove the current legacy const refresh.
2. Add a `const StatefulWidget implements LocaleStatePreservingRoute` whose State subscribes to the locale notifier, owns a counter plus TextEditingController, and exposes translated text. Record the State identity, init/dispose counts, counter, controller identity, and draft. After editing/incrementing, call only `I18n.setLocale` twice and pump. Copy must change; all state values/identities must stay unchanged, with init = 1 and dispose = 0 before route removal. Popping must dispose exactly once; a later locale event must cause no disposed-State callback.
3. Add a `const StatelessWidget implements LocaleStatePreservingRoute` facade that returns that stateful body. This specifically rejects a wrapper fix based solely on StatefulWidget type and models Pomodoro/Integrations. Require the same lifecycle assertions.
4. Add an unmarked self-refreshing stateful probe under `BrandRouteSurface(remountOnLocaleChange: false, ...)` to cover the Mine/Profile API. Also cover a marked probe with the bool explicitly true to lock in marker precedence.

Do not repump a newly constructed parent tree for the locale assertion: that could conceal failure to refresh const routes. Use a const MaterialApp for raw-notifier cases so normal MaterialApp locale dependencies do not hide the missing notifier subscription.

### Real route cases

| Route and initial interaction | Locale event | Required retained state and refreshed copy |
| --- | --- | --- |
| Today → Todo; choose list mode, a nondefault filter, collapse a group, select an item, and scroll with enough fixture rows | Change locale while that route remains mounted | Todo title/control copy changes; mode/filter/collapsed IDs/selected IDs/controller and list offset survive. Account for normal offset clamping if different text heights change the maximum extent. |
| TodayDetailRouter without Habit ID, or Search → Habit; open heatmap tab after scrolling Today | Change locale both directions | Tab remains selected; heatmap-built flag stays true; mounted scroll state survives. Include weekly-card weekdays/status to catch the formerly const descendant. |
| Search → Calendar(initialDate); select another day/month, a nondefault view tab, and filters | Change locale, then pop any route opened above it | Current date/month/tab/filter selections survive; initialDate is not reapplied. Month/weekday/title copy refreshes. |
| Widget preview → direct Calendar and widget URI → shell Calendar/Focus tab | Change locale | The direct page path refreshes without BrandRouteSurface; shell GlobalKey states remain attached and retain selections. |
| Today/Mine/calendar event sheet → Focus; use a nondefault tab and a running session | Change locale while mounted | Body/tab/provider identities survive; the session remains active with monotonically advancing time rather than resetting. Include Study room copy after content migration and room-tab scroll state. |
| Mine → Integrations; select Language tab and tap English, then Chinese | Use the actual LocaleProvider UI | The route remains on Language tab (index 2); title, all three tab labels, language labels/description, and selected radio reflect the choice. No route flicker/remount. |
| Main OAuth callback → Integrations; allow initial callback handling, retain a URI and provider state | Change locale without changing URI | Calendar tab state and callback guard survive; OAuth handling/dialog does not repeat. |
| Standalone Integrations with some/all optional providers absent; settle deterministic initial storage loads first | Change locale through fallback LocaleProvider and separately via raw I18n | Fallback State/provider identities and subscriptions/reminders survive; storage load is not repeated by locale refresh; DefaultTabController identity/index survive. Include Location tab labels to catch its formerly const child. |

For a route covered by another settings route during the event, make assertions again after popping settings: offstage route state must also survive. Editors/pickers remain a separate acceptance batch for live copy and retained drafts; do not claim this route-only contract proves them.

## Precise AGY handoff

Implement the route locale/state contract in the six production files listed above, based on the main snapshot supplied as `75d72d2`. Mark the five public route widgets; keep the Mine-compatible optional bool and compose it with marker precedence in BrandRouteSurface. Add balanced static-notifier subscriptions to Todo/Habit/Calendar and the existing stateful Pomodoro body. Reuse Integrations' current body notifier builder. Refresh the four identified const descendant boundaries with new unkeyed widget instances. Preserve public constructor signatures, const compatibility, controllers, provider fallback ownership, OAuth handled state, direct shell behavior, and route background/theme behavior. Do not add call-site flags to main/Today/Search/Mine/More Apps/widget preview/event sheet because the current marker handles those boundaries already. Do not use element traversal or widget-type heuristics. Do not access the live Mine worktree; reconcile its bool implementation only through the parent's eventual merge. Do not run Git, Flutter, compiler, analysis, tests, network commands, or edit test files unless separately authorized by the parent. Report exact files changed and any unresolved localization literals/editor coverage; do not claim the acceptance specifications passed.

This decision task made no production or test edits and ran no checks, compilers, builds, tests, Git commands, or network operations. Its only write is this private report.
