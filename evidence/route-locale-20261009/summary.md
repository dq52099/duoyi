# Main route locale state retention — 2026-10-09

## Implemented

Todo, Habit, Calendar, Pomodoro and Integrations declare the public LocaleStatePreservingRoute marker. BrandRouteSurface preserves marked routes' mounted elements; its optional remountOnLocaleChange flag supports other self-refreshing pages, while unmarked legacy const routes retain locale-keyed refresh. The marker takes precedence over that flag.

Four route States register balanced locale listeners. Integrations reuses its existing locale builder. Fresh unkeyed weekly-card, focus-room, location and language-tab widgets update static copy while preserving their element State and controllers.

## Executed verification

- 48 focused checks passed across seven files. Actual mounted routes exercise raw zh → en → zh events, Todo mode/filter/scroll, Habit heatmap tab, Calendar selected date/tab and direct route, Pomodoro history/session snapshot, and Integrations language selection/controller. Wrapper probes verify drafts, controllers, counter, lifecycle disposal, stateless facade and bool/marker precedence.
- 925 integrated Flutter regressions across 74 files passed with unchanged frozen hashes; targeted Dart analysis passed.
- Initial fixture failures are retained: missing ThemeProvider in the new Integrations wrapper fixture and implicit host locale in pre-existing standalone fixtures. Corrected fixture setup does not change production behavior.
- An initial analyzer failure found three fixture style issues. Its exact log is retained; all checks were rerun after those fixes.
- [source-audit.md](source-audit.md), exact logs and [verification.json](verification.json) document checks and scope.

## Remaining work

Todo/Habit use in-memory data; Pomodoro uses a fixed running snapshot and suppresses room refreshes. This proves retained route/controller/provider identity and copy, not true timer progression, audio/DND, persistence or duplicate mutation counts. Initial standalone fallback rendering and location action tests pass, but a mounted fallback/OAuth transition contract still needs focused coverage.

Main app-owned literals and create/edit overlays remain separate required localization work. Mine/Profile feedback, comprehensive iOS visuals and real device startup/frame timing are open. This locally integrated batch does not publish an artifact or close the full goal.
