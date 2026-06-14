# Fresh Codex Handoff Prompt

Superseded: the user explicitly wants to keep using the old session. Prefer `codex-old-session-resume-prompt-019e99a1.md` for the current workflow.

Do not resume session `019e99a1-5469-7ec1-8f8d-8cedea01da87`.
That transcript is too large and contains wrong turns. Start from this compact handoff instead.

You are working in `/home/ubuntu/duoyi`.

## User Intent

The user only wants the Duoyi Flutter Web app at:

`http://6688667.xyz/duoyi/`

to be fixed and published correctly.

Do not touch unrelated sites, domains, certificates, default server config, or other apps.

Explicitly avoid:

- `image.6688667.xyz`
- `duoyitimes.com`
- `mcpserver.6688667.xyz`
- certificate issuance or SSL config
- OpenResty default server config changes
- broad full-disk searches

## Current Problem

The user says the notification settings UI is still misaligned on the web app.

There was a previous mistake: a CSS fix was published to `image.6688667.xyz`, which is the wrong app. Do not continue in that direction. If needed, inspect only enough to understand whether that mistaken change should be reverted, but the primary target is `/duoyi/`.

## Correct Deployment Target

`http://6688667.xyz/duoyi/` is a Flutter Web app.

Observed online:

- `http://6688667.xyz/duoyi/` returns `200 OK`
- HTML has `<base href="/duoyi/">`
- title is `多仪`

Actual static file location:

- inside container: `/usr/share/nginx/html/duoyi`
- host bind mount: `/opt/1panel/apps/openresty/openresty/root/duoyi`

Docker mount confirmed:

`/opt/1panel/apps/openresty/openresty/root -> /usr/share/nginx/html`

The online `/duoyi/` files were still from June 9, 2026 when last checked, so the newer local changes had not been published there.

## Build Notes

Do not directly sync the existing local `build/web` unless you verify it was rebuilt for `/duoyi/`.

Last checked local `build/web/index.html` had:

`<base href="/">`

That is wrong for `/duoyi/`.

Rebuild for the target path, for example:

```bash
/opt/migrate/flutter/bin/flutter build web --release --base-href=/duoyi/
```

Server URL behavior:

- `lib/core/app_config.dart` default server URL is `http://6688667.xyz`
- The app also supports `--dart-define=DUOYI_SERVER_URL=` for same-origin relative API calls.
- `http://6688667.xyz/api/config` is currently reachable and reports app version `1.1.37`, build `140003`.

If using the existing default server URL, web API requests should still hit `http://6688667.xyz/api/...`.

## Important Local State

The git worktree is very dirty with many existing modified files and untracked files. Do not revert anything unless the user explicitly asks.

Key modified areas include:

- `lib/screens/admin_screen.dart`
- many Flutter screens/providers/widgets/services
- many tests
- `lib/core/app_version.dart` currently shows `1.1.37`, build `140003`

There are evidence screenshots under:

`evidence/screenshots/`

Store any new UI verification screenshots there, not in the repo root.

## What To Do Next

1. Inspect the current notification settings UI implementation in the Flutter app, not the unrelated image gateway CSS.
2. Confirm the exact misaligned screen/route if possible from code and existing screenshots.
3. Make the smallest Flutter layout fix needed for web/mobile narrow width.
4. Run targeted formatting/analyzer/tests with `/opt/migrate/flutter/bin/flutter`.
5. Rebuild Flutter Web with `--base-href=/duoyi/`.
6. Publish only the rebuilt Flutter Web files to `/opt/1panel/apps/openresty/openresty/root/duoyi`.
7. Verify:
   - `curl -I http://6688667.xyz/duoyi/`
   - online `index.html` has `<base href="/duoyi/">`
   - key assets return `200`
   - ideally use Playwright/browser screenshot saved under `evidence/screenshots/`

## Process Rules

- Keep the user updated in Chinese.
- Do not start long broad searches.
- Do not change certificates or server defaults.
- Do not touch unrelated containers/sites.
- Work with the dirty tree; do not reset or checkout files.
- If something is uncertain, inspect locally first and state concrete findings.
