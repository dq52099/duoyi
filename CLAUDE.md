# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

多仪 (Duoyi) is a cross-platform productivity app built with Flutter + FastAPI backend. It integrates todo management (Eisenhower matrix), habit tracking (GitHub-style heatmap), Pomodoro focus sessions, calendar, and personal profile into a single app. Supports 8 theme variations with custom backgrounds, AI assistant integration, cloud sync, and Android home screen widgets.

- **Frontend**: Flutter 3.41.9+ (Dart SDK ^3.11.5)
- **Backend**: Python FastAPI with SQLite
- **State Management**: Provider pattern
- **Platforms**: Android, Linux desktop, Web

## Development Commands

### Flutter Client

```bash
# Install dependencies
flutter pub get

# Run on Linux desktop
flutter run -d linux

# Build Android APK (release)
flutter build apk --release

# Build with custom server URL (compile-time constant)
flutter build apk --release --dart-define=DUOYI_SERVER_URL=https://your-server.com

# Run tests
flutter test

# Analyze code
flutter analyze

# Format code
dart format .
```

### Backend

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Start development server (creates fingertip_time.db on first run)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Production deployment (on VPS)
./scripts/deploy_backend_prod.sh  # Restarts systemd service and validates routes
```

**Environment variables for backend** (first-run bootstrap only; managed via admin panel afterwards):
- `ADMIN_BOOTSTRAP_USER` (default: admin)
- `ADMIN_BOOTSTRAP_PASSWORD` (default: admin123)
- `INVITE_CODE_REQUIRED` (default: false)
- `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL`
- `CORS_ORIGINS`

### Testing

```bash
# Run widget/unit tests
flutter test

# Run backend tests
cd backend
python -m pytest test_workspaces.py -v
```

## Architecture

### Frontend Structure

```
lib/
├── core/              # Theme system (AppBrand, BrandStrings), utilities, business logic
│   ├── app_brand.dart         # 8 theme definitions (defaultBrand, re0, genshin, starRail, wuthering, zzz, yanyun, botw)
│   ├── brand_strings.dart     # Theme-specific UI text (e.g., "待办" → "咒文" in RE0 theme)
│   ├── achievements.dart      # Achievement/badge system
│   ├── report_engine.dart     # Weekly AI report generation
│   └── smart_todo_draft.dart  # AI task breakdown logic
├── models/            # Data models (Todo, Habit, Pomodoro, CalendarEvent, UserProfile, Goal, etc.)
├── providers/         # Provider state management (TodoProvider, HabitProvider, CloudSyncProvider, etc.)
├── services/          # API clients, platform integrations (ApiClient, AiService, SystemTray, DeepLinkService)
├── screens/           # UI screens (admin_screen, calendar_screen, habit_detail_screen, etc.)
└── widgets/           # Reusable widgets (eisenhower matrix, heatmap, brand_background, etc.)
```

### Backend Structure

**Single-file monolith**: `backend/main.py` (~434KB, 10,000+ lines)

- FastAPI app with SQLite (`fingertip_time.db`)
- Routes: `/api/auth/*`, `/api/sync/*`, `/api/admin/*`, `/api/ai/chat`, `/api/focus-rooms/*`, `/ws/*`
- Admin panel settings stored in database, read via API (AI config, cloud backup settings, announcements, user management)
- Contract version tracking: `API_CONTRACT_VERSION` and `API_CONTRACT_FEATURES` for client compatibility

### Theme System

The app uses a **brand/theme system** that switches not just colors but also:
- Background images (7 themed backgrounds in `assets/backgrounds/`)
- UI terminology (e.g., "待办" becomes "咒文" in RE0 theme, "委托" in Genshin theme)
- Greeting messages and notification text

Theme switching is managed by `AppBrand` (in `lib/core/app_brand.dart`) and `BrandStrings` (in `lib/core/brand_strings.dart`).

### Cloud Sync

- **Client**: `lib/providers/cloud_sync_provider.dart` implements timestamp-based 3-way merge
- **Server**: `/api/sync/push` and `/api/sync/pull` endpoints in `backend/main.py`
- Sync payloads: todos, habits, calendar events, pomodoro sessions, notes, diaries, goals, courses, etc.
- Conflict resolution: last-write-wins based on `updatedAt` timestamps
- Configurable via admin panel: max payload size, minimum sync interval, retention days

### Android Widgets

- **Location**: `android/app/src/main/kotlin/com/.../`
- **Type**: MIUI/generic home screen widgets with 3 columns (todo, habit, pomodoro)
- **Deep links**: `duoyi://` scheme for widget tap actions

## Build & Release

### CI/CD (GitHub Actions)

Workflow file: `.github/workflows/build-apk.yml`

| Trigger | Job | Output |
|---------|-----|--------|
| Every push/PR | `analyze` | Runs `flutter analyze`, `dart format`, and `flutter test` |
| Every push/PR | `android` | Generic APK + per-ABI APKs (armeabi-v7a, arm64-v8a, x86_64) |
| Tag push or manual trigger | `web` | `duoyi-web-*.tar.gz` for nginx deployment |
| Tag `v*` push | `release` | Auto-creates GitHub Release with APKs, AAB, and web tarball |

### Required Repository Secrets

- `DUOYI_KEYSTORE_BASE64`: Base64-encoded Android keystore (build fails without this)
- `DUOYI_KEYSTORE_PASSWORD`, `DUOYI_KEY_ALIAS`, `DUOYI_KEY_PASSWORD`

### Optional Repository Variables

- `DUOYI_SERVER_URL`: Backend URL injected at build time (falls back to `lib/core/app_config.dart`)

### Creating a Release

```bash
git tag v1.0.3
git push origin v1.0.3
```

GitHub Actions will build and attach:
- `duoyi-v1.0.3.apk` (universal)
- `duoyi-v1.0.3-arm64-v8a.apk`, `-armeabi-v7a.apk`, `-x86_64.apk`
- `duoyi-v1.0.3.aab` (for Play Store)
- `duoyi-web-v1.0.3.tar.gz`

App checks for updates via "我的 → 检查更新" by querying GitHub Releases API.

## Server URL Configuration

**Important**: Server URL is a compile-time constant, not runtime configurable.

- Default defined in `lib/core/app_config.dart` as `defaultServerUrl`
- Override via `--dart-define=DUOYI_SERVER_URL=<url>` during build
- GitHub Actions uses `DUOYI_SERVER_URL` repository variable (or manual input)
- For same-domain deployment: leave empty to use relative paths (`/api/`, `/ws/`)

## Key Features

### AI Integration

- Compatible with OpenAI `chat/completions` API (any OpenAI-compatible gateway works)
- Managed via admin panel (Base URL, API Key, model selection, daily usage limits)
- **AI Task Breakdown**: Converts single-line task description into structured subtasks
- **AI Weekly Review**: Generates summary and suggestions based on completed tasks
- Rate limiting: per-user daily quota enforced in backend

### Admin Panel

Accessible in-app via "我的 → 管理员后台" (only for admin users). Tabs:
- Overview: KPIs, 7-day registration trend
- Site Settings: Allow registration, invite code requirement, maintenance mode
- AI Config: Enable/disable AI, configure provider, test connection
- Cloud Backup: Enable/disable sync, set limits, view per-user backup size
- Users: Search, promote, disable, reset password, delete
- Announcements: Publish, draft, archive
- Feedback: Filter, reply, delete
- Invite Codes: Generate, copy, delete unused

### Multi-Workspace (Note: In Development)

Backend has experimental multi-workspace support. See `backend/test_workspaces.py` for tests.

## Testing Strategy

- Widget tests in `test/widgets/`
- Backend API tests in `backend/test_workspaces.py`
- CI runs both Flutter and Python tests automatically

## Deployment Notes

### Production Backend

- Runs as systemd service `duoyi-backend` on port `127.0.0.1:18015`
- Proxied via OpenResty/nginx from public domain
- Deploy script: `./scripts/deploy_backend_prod.sh` (restarts service and validates critical routes)
- SQLite database: `backend/fingertip_time.db` (auto-created on first run)

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

- Uses Flutter's built-in l10n (`flutter_localizations`)
- Custom I18n wrapper: `lib/core/i18n.dart` with `I18n.tr()` helper
- L10n config: `l10n.yaml`
- Generated files: `lib/l10n/generated/`

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
