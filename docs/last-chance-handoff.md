# Last Chance Handoff

Date: 2026-06-01

Current status:

1. Public backend `http://6688667.xyz` is now running the current API contract.
2. `/api/config` returns version `1.1.17`, version code `120017`, contract `2026-06-01.2`, and required routes hash `2554d781b96849f9`.
3. Live E2E on the public domain passed for admin login, profile update, avatar upload and fetch, password change, user group create/update/list/delete, admin user create with camelCase flags, default time-coin grant, time-coin adjustment, focus room heartbeat/ranking, global focus leaderboard, provider healthcheck, and account email test.
4. Flutter analyze passed.
5. Full Flutter test suite passed with 1306 tests.
6. Backend `python3 -m unittest test_workspaces` passed with 141 tests.

Latest user priorities kept in this release:

1. No weather feature.
2. Do not change Android signing.
3. Keep 今日待办 visible.
4. Put 今日提醒 and 今日待办 icons before the task name in the same row.
5. Habit 今日打卡 uses the stored or template habit icon, not a checkmark as identity icon.
6. 今日 page shows 万年历 at the top and does not call it 打卡万年历.
7. Almanac content uses the `lunar` package data source and includes Xiaomi-style fields such as 宜忌、农历、干支、胎神、彭祖、五行、星宿、冲煞、时辰吉凶.
8. Habit cards and todo cards should not expose a duplicate left-swipe detail action when tap already opens details.
9. Secondary route AppBar titles use the same size as main pages, and secondary filled buttons adjust the action background for readable contrast.

Release baseline:

1. Version: `1.1.17+120017`.
2. Release notes: `docs/releases/v1.1.17.md`.
3. Signing: unchanged; local signing material is intentionally incomplete, so release build should use the existing GitHub Actions secrets.
4. Remaining device-only risks: real file picker behavior, long-session thermal/jank on physical 120 Hz devices, and multi-process token invalidation if the backend is scaled beyond one process.
