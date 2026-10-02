# AGENTS.md — 多仪 (Duoyi)

Cross-platform productivity app: **Flutter client** (Android / Linux desktop / Web) + **single-file FastAPI backend** (`backend/main.py`, ~12k lines, SQLite). Modules: Eisenhower todos, habit heatmap, pomodoro, calendar, profile. 8 switchable themes that change colors, background images, **and UI copy** (待办 → 咒文/委托/…) — user-visible strings come from `lib/core/brand_strings.dart`, don't hardcode them. `CLAUDE.md` holds the extended version of this guidance.

## Commands

```bash
flutter pub get
flutter analyze                     # must stay clean; CI pins Flutter 3.44.1
dart format .
flutter test                        # ~240 test files under test/
flutter test test/screens/todo_screen_test.dart   # single file

# Backend (backend/test_workspaces.py is the ENTIRE backend suite despite its name)
cd backend && pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
python -m unittest test_workspaces -v

# Release gate: Flutter tests + backend tests + analyze + debug APK build + device regression
scripts/alignment_regression_gate.sh
```

**Gotcha:** `flutter` is not on PATH on this machine, and `scripts/*.sh` default `FLUTTER_BIN` to `/home/ubuntu/flutter/bin/flutter` (a Linux path from another machine). Set `FLUTTER_BIN` (and `PYTHON_BIN`) explicitly when running them.

## Hard rules (enforced by static guard tests)

~96 files named `test/**/*_static_test.dart` regex-scan `lib/` and **fail the whole suite when banned patterns appear anywhere** — e.g. `FontWeight.bold` / `FontWeight.w500+`, raw values instead of design tokens (`lib/core/design_tokens.dart`), screens not using the i18n wrapper. When one trips: read the test's `reason` message (Chinese) and fix the code — never weaken the guard. Any UI change should be checked against them.

- **Version bump touches two files**: `pubspec.yaml` (`version: 1.1.41+140007`) AND `lib/core/app_version.dart` (`name`/`build`) — change together or update checks disagree.
- **Backend routes are contract-pinned**: `backend/test_workspaces.py` asserts client-facing routes do not 404. Adding/renaming a route the client calls → add/update the matching contract test; keep `API_CONTRACT_VERSION` / `API_CONTRACT_FEATURES` in `backend/main.py` current.
- **Server URL is compile-time**: default in `lib/core/app_config.dart`; override with `--dart-define=DUOYI_SERVER_URL=<url>` (empty value = same-domain relative `/api/`, `/ws/` — used for web builds).
- **i18n**: Chinese ARB template (`lib/l10n/app_zh.arb`, zh primary / en); use `I18n.tr()` from `lib/core/i18n.dart`.

## Layout

```
lib/core/        AppBrand (8 themes) / BrandStrings / design_tokens / app_config / app_version
lib/models/ lib/providers/ lib/services/ lib/screens/ lib/widgets/
backend/main.py  FastAPI monolith: /api/auth, /api/sync, /api/admin, /api/ai/chat, /ws/*
android/app/src/main/kotlin/…  Kotlin home-screen widgets (todo/habit/pomodoro), `duoyi://` deep links;
                               widget resource contracts guarded by test/services/android_widget_resources_test.dart
docs/            canonical requirement/design/contract docs (requirement-v2.md, design-v2.md, cloud-sync-v2-contract.md)
```

Cloud sync (`lib/providers/cloud_sync_provider.dart` + `/api/sync/*`): timestamp-based 3-way merge, last-write-wins on `updatedAt`; contract in `docs/cloud-sync-v2-contract.md`.

## Docs & deployment hygiene

- Root-level `*_REPORT.md` / `*_SUMMARY.md` / `*_ANALYSIS.md` files are historical working-session notes — not current guidance, and don't add new ones to the root.
- Prod backend runs as systemd `duoyi-backend`; **backend code changes take effect only after restart** via `./scripts/deploy_backend_prod.sh`. Client releases ship via GitHub Releases: bump both version files, push a `v*` tag.
- Sign-off repo secrets (`DUOYI_KEYSTORE_*`) are required for release builds — no debug-signing fallback.

## Screenshots & evidence

- Store UI verification screenshots in `evidence/screenshots/`.
- Store larger screenshot batches in a named directory under `evidence/`.
- Do not leave generated agent screenshots in the repository root.
- Keep real app image assets in their existing asset directories, such as `assets/`, `android/app/src/main/res/`, `ios/Runner/Assets.xcassets/`, `linux/`, and `web/`.
