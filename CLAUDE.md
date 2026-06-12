# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

多仪 (Duoyi) is a cross-platform productivity app built with Flutter + FastAPI backend. It integrates todo management (Eisenhower matrix), habit tracking (GitHub-style heatmap), Pomodoro focus sessions, calendar, and personal profile into a single app. Supports 8 theme variations with custom backgrounds, AI assistant integration, cloud sync, and Android home screen widgets.

- **Frontend**: Flutter (Dart SDK ^3.11.5). CI pins Flutter **3.44.1**; the local install may be older (currently 3.41.9) — analyzer behavior differs between versions, and code must stay clean on the CI version.
- **Backend**: Python FastAPI single-file monolith with SQLite
- **State Management**: Provider pattern
- **Platforms**: Android, Linux desktop, Web (iOS scaffolding exists but is not a CI target)

**On this machine** `flutter` is not on PATH. Use `/home/ubuntu/flutter/bin/flutter`; repo scripts default to this via the `FLUTTER_BIN` env var. Android SDK lives at `/home/ubuntu/android-sdk`.

## Development Commands

### Flutter Client

```bash
flutter pub get
flutter run -d linux              # Linux desktop
flutter analyze
dart format .

# Run all tests
flutter test

# Run a single test file
flutter test test/screens/countdown_screen_test.dart

# Build Android APK (release) with custom server URL (compile-time constant)
flutter build apk --release --dart-define=DUOYI_SERVER_URL=https://your-server.com
```

### Backend

```bash
cd backend
pip install -r requirements.txt

# Start development server (creates duoyi.db on first run)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Run all backend tests (unittest-style; pytest also works)
python -m unittest test_workspaces -v

# Run a single backend test
python -m unittest test_workspaces.WorkspaceApiTest.test_admin_current_management_routes_do_not_404
```

Despite its name, `backend/test_workspaces.py` (~150 tests in `WorkspaceApiTest`) is the **entire backend test suite**: route contracts, auth, admin, sync, feedback, coins — not just workspaces.

**Backend environment variables** (first-run bootstrap only; managed via admin panel afterwards): `ADMIN_BOOTSTRAP_USER` / `ADMIN_BOOTSTRAP_PASSWORD` (default admin/admin123), `INVITE_CODE_REQUIRED`, `AI_BASE_URL` / `AI_API_KEY` / `AI_MODEL`, `CORS_ORIGINS`, `DUOYI_DB_PATH`. Many more exist for email/SMTP, OpenList/WebDAV backup, and server backup — grep `os.getenv` in `backend/main.py`.

### Full Regression Gate

```bash
scripts/alignment_regression_gate.sh
```

The release gate. Runs 8 groups: batched Flutter tests (static guards, screens, notifications, widget contracts), backend route-contract tests via unittest, `flutter analyze`, a debug APK build, and a device/emulator regression (`scripts/device_regression_check.sh` — needs Android SDK + KVM). Report written to `build/alignment-regression/latest/`.

## Critical Conventions

### Static guard tests enforce project rules

Roughly 95 of ~240 Flutter test files match `*_static_test.dart`. These regex-scan `lib/` source and **fail when banned patterns appear anywhere in the codebase** — e.g., `test/services/no_global_bold_static_test.dart` bans `FontWeight.bold` / `FontWeight.w500+` in all of `lib/`. When your change trips one, read the test's `reason` message (it states the convention in Chinese) and fix the code to comply — do not weaken the guard. Release commits routinely have to "satisfy release static guards"; expect any UI change to be checked against them.

### Version bump touches two files

The app version lives in **both** `pubspec.yaml` (`version: 1.1.37+140003`) and `lib/core/app_version.dart` (`name` / `build`). Bump them together or version checks will disagree.

### Backend routes are contract-pinned

`test_workspaces.py` pins every client-facing route against 404s (many tests are named `..._do_not_404`). When adding or renaming a backend route the client calls, add/update the matching contract test. `API_CONTRACT_VERSION` and `API_CONTRACT_FEATURES` in `backend/main.py` track client compatibility.

### Screenshots and evidence (from AGENTS.md)

- Store UI verification screenshots in `evidence/screenshots/`; larger batches in a named directory under `evidence/`.
- Never leave generated screenshots in the repository root.
- Real app image assets belong in their existing asset directories (`assets/`, `android/app/src/main/res/`, `ios/Runner/Assets.xcassets/`, `linux/`, `web/`).

### Documentation layout

Canonical requirement/design/task docs live in `docs/` (`requirement-v2.md`, `design-v2.md`, `cloud-sync-v2-contract.md`, etc.). The many `*_REPORT.md` / `*_SUMMARY.md` files in the repo root are historical working-session notes — don't treat them as current guidance and don't add new ones there.

## Architecture

### Frontend Structure

```
lib/
├── core/              # Theme system, design tokens, business logic (no Flutter UI deps for most)
│   ├── app_brand.dart         # 8 theme definitions (defaultBrand, re0, genshin, starRail, wuthering, zzz, yanyun, botw)
│   ├── brand_strings.dart     # Theme-specific UI text (e.g., "待办" → "咒文" in RE0 theme)
│   ├── app_config.dart        # Compile-time server URL (defaultServerUrl + --dart-define override)
│   ├── app_version.dart       # App version constants (keep in sync with pubspec.yaml)
│   ├── design_tokens.dart     # Spacing/typography tokens (enforced by static guard tests)
│   └── ...                    # achievements, report_engine, recurrence, insights, validation, etc.
├── models/            # Data models (Todo, Habit, Pomodoro, CalendarEvent, UserProfile, Goal, etc.)
├── providers/         # Provider state management (TodoProvider, HabitProvider, CloudSyncProvider, etc.)
├── services/          # API clients, platform integrations (ApiClient, AiService, SystemTray, DeepLinkService)
├── screens/           # UI screens (admin_screen, calendar_screen, habit_detail_screen, etc.)
└── widgets/           # Reusable widgets (eisenhower matrix, heatmap, brand_background, etc.)
```

### Backend Structure

**Single-file monolith**: `backend/main.py` (~12,400 lines)

- FastAPI app with SQLite at `backend/duoyi.db` (auto-created; a legacy `fingertip_time.db` is auto-detected and preferred only if it holds more data; override path via `DUOYI_DB_PATH`)
- Routes: `/api/auth/*`, `/api/sync/*`, `/api/admin/*`, `/api/ai/chat`, `/api/focus-rooms/*`, `/api/theme-shop/*`, `/ws/*`
- Admin panel settings stored in database, read via API (AI config, cloud backup settings, announcements, user management)

### Theme System

The app uses a **brand/theme system** that switches not just colors but also:
- Background images (7 themed backgrounds in `assets/backgrounds/`)
- UI terminology (e.g., "待办" becomes "咒文" in RE0 theme, "委托" in Genshin theme)
- Greeting messages and notification text

Theme switching is managed by `AppBrand` (`lib/core/app_brand.dart`) and `BrandStrings` (`lib/core/brand_strings.dart`).

### Cloud Sync

- **Client**: `lib/providers/cloud_sync_provider.dart` implements timestamp-based 3-way merge
- **Server**: `/api/sync/push` and `/api/sync/pull` endpoints in `backend/main.py`
- Sync payloads: todos, habits, calendar events, pomodoro sessions, notes, diaries, goals, courses, etc.
- Conflict resolution: last-write-wins based on `updatedAt` timestamps
- Configurable via admin panel: max payload size, minimum sync interval, retention days
- Contract doc: `docs/cloud-sync-v2-contract.md`

### Android Widgets

- **Location**: `android/app/src/main/kotlin/com/.../`
- **Type**: MIUI/generic home screen widgets with 3 columns (todo, habit, pomodoro)
- **Deep links**: `duoyi://` scheme for widget tap actions
- Widget resource contracts are guarded by `test/services/android_widget_resources_test.dart` (and an iOS counterpart)

## Build & Release

### CI/CD (GitHub Actions)

Workflow file: `.github/workflows/build-apk.yml` (pins `FLUTTER_VERSION: 3.44.1`)

| Trigger | Job | Output |
|---------|-----|--------|
| Every push/PR | `analyze` | `flutter analyze`, `dart format`, `flutter test`, and backend tests |
| Every push/PR | `android` | Generic APK + per-ABI APKs (armeabi-v7a, arm64-v8a, x86_64) |
| Tag push or manual trigger | `web` | `duoyi-web-*.tar.gz` for nginx deployment |
| Tag `v*` push | `release` | Auto-creates GitHub Release with APKs, AAB, and web tarball |

### Required Repository Secrets

- `DUOYI_KEYSTORE_BASE64`: Base64-encoded Android keystore (release build fails without it — no debug-signing fallback)
- `DUOYI_KEYSTORE_PASSWORD`, `DUOYI_KEY_ALIAS`, `DUOYI_KEY_PASSWORD`

### Optional Repository Variables

- `DUOYI_SERVER_URL`: Backend URL injected at build time (falls back to `lib/core/app_config.dart`)

### Creating a Release

1. Bump the version in **both** `pubspec.yaml` and `lib/core/app_version.dart`
2. Tag and push:

```bash
git tag v1.1.38
git push origin v1.1.38
```

GitHub Actions attaches the universal APK, per-ABI APKs, AAB, and web tarball to the Release. The app checks for updates via "我的 → 检查更新" by querying the GitHub Releases API.

Download pages in `deploy/duoyi.html` and `deploy/duoyi-test-cases.html` are updated and published alongside releases (see `docs: publish ... download pages` commits).

## Server URL Configuration

**Important**: Server URL is a compile-time constant, not runtime configurable.

- Default defined in `lib/core/app_config.dart` as `defaultServerUrl` (currently `http://6688667.xyz`)
- Override via `--dart-define=DUOYI_SERVER_URL=<url>` during build
- GitHub Actions uses the `DUOYI_SERVER_URL` repository variable (or manual input)
- For same-domain deployment: pass an empty value to use relative paths (`/api/`, `/ws/`)

## Key Features

### AI Integration

- Compatible with OpenAI `chat/completions` API (any OpenAI-compatible gateway works)
- Managed via admin panel (Base URL, API Key, model selection, daily usage limits)
- **AI Task Breakdown**: Converts single-line task description into structured subtasks
- **AI Weekly Review**: Generates summary and suggestions based on completed tasks
- Rate limiting: per-user daily quota enforced in backend

### Admin Panel

Accessible in-app via "我的 → 管理员后台" (admin users only). Tabs cover: overview KPIs, site settings (registration/invite code/maintenance mode), AI config, cloud backup, user management, announcements, feedback, and invite codes.

## Testing Strategy

- Flutter tests live under `test/{core,models,providers,screens,services,widgets}/` (~240 files); shared helpers in `test/test_support/`
- `*_static_test.dart` files are source-scanning convention guards (see Critical Conventions above)
- Integration smoke test: `integration_test/app_alignment_smoke_test.dart`
- Backend API tests: `backend/test_workspaces.py` (the full backend suite, unittest-style)
- CI runs Flutter and Python tests on every push/PR; `scripts/alignment_regression_gate.sh` is the heavier pre-release gate

## Deployment Notes

### Production Backend

- Runs as systemd service `duoyi-backend` on `127.0.0.1:18015`
- Proxied via OpenResty/nginx from the public domain (`http://6688667.xyz`)
- Deploy script: `./scripts/deploy_backend_prod.sh` — restarts the service, then validates `/api/config` locally and publicly and probes auth-protected routes (expects 401, proving routes are registered)
- **Backend code changes do not take effect until the service is restarted** — GitHub Releases only ship client artifacts
- SQLite database: `backend/duoyi.db`; periodic backups in `backend/backups/`

### Web Client

Build with empty `DUOYI_SERVER_URL` for same-domain deployment:

```bash
flutter build web --release --dart-define=DUOYI_SERVER_URL=
```

Nginx config example:
```nginx
location /api/ { proxy_pass http://127.0.0.1:8000; }
location /ws/ { proxy_pass http://127.0.0.1:8000; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
location / { try_files $uri $uri/ /index.html; }
```

## Localization

- Uses Flutter's built-in l10n (`flutter_localizations`); config in `l10n.yaml`
- Template ARB is **Chinese** (`lib/l10n/app_zh.arb`); supported locales: zh (primary), en
- Generated files: `lib/l10n/generated/`
- Custom wrapper: `lib/core/i18n.dart` with `I18n.tr()` helper; several static guard tests enforce i18n usage in screens

## Platform-Specific Features

### Linux Desktop
- System tray integration (see `lib/services/system_tray.dart`)
- DBus desktop notifications

### Android
- Home screen widgets (todo/habit/pomodoro 3-column layout)
- Deep links via `duoyi://` scheme
- Notifications via `flutter_local_notifications`

### Web
- PWA manifest in `web/manifest.json`
- WebSocket support for real-time features (focus rooms)
