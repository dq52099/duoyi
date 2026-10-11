# Accepted HEAD web artifact validation — 2026-10-11

## Pinned build

- Worktree: `.dart_tool/task-temp-20261011/accepted-head-729f2ea`
- Git revision: `729f2eaa3e2d5b89778355e9bb8a96bfb034280a` (detached HEAD; `git status --short --branch` reported only `## HEAD (no branch)`).
- Build command recorded by the root run: `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter build web --no-pub --release --base-href /duoyi/ --dart-define=DUOYI_SERVER_URL=/duoyi --dart-define=DUOYI_WEB_TARGET=mobile`.
- The root-collected build process exited 0. Its log reports `Built build/web` after 381.5 seconds. Flutter reported a successful Wasm dry run and tree-shook the Cupertino and Material icon fonts. This was a release build and did not resolve pub dependencies (`--no-pub`); the preceding offline pub log reports `Got dependencies`.
- Artifact size: 79 MB. `pubspec.yaml` has `version: 1.1.46+140012`; `build/web/version.json` has `version: 1.1.46`, `build_number: 140012`, and `app_name` / `package_name` `duoyi`.

## Artifact checks

`build/web/index.html` contains `<base href="/duoyi/">` and loads `flutter_bootstrap.js`. The bootstrap config selects the `dart2js` CanvasKit build and `main.dart.js`; it requests `flutter_service_worker.js?v=3146152289`. The generated service worker unregisters itself on activation and navigates existing clients to reload.

SHA-256 values from the pinned worktree:

| Artifact | SHA-256 |
|---|---|
| `index.html` | `dbb9336b491b42b296be0432f5b29157eb019bbc3b53e866e05a966ad4753d87` |
| `main.dart.js` | `69cfd706d2d72f99496bd0eede9b879af97db502ecf7dddd527d0071b038222d` |
| `flutter_bootstrap.js` | `d7db7171b09c16bd415093eed1d0ee8ee227cb98c40755f35c94690ec3fc1fd2` |
| `flutter.js` | `483fd28f51ed2fadd0da3fade5b672eba56310d549d736ce62eabf624a6a5788` |
| `flutter_service_worker.js` | `a131df5ca46154cc4eb79044f7f5a14029c2f8bfccf8cef34e3ec3b5a9f5a88c` |
| `version.json` | `844b3e1797fd51ff0c48f0f53017150cb3ffe7496cdb099fab9c7b09caa66a79` |

The root ran a loopback static server rooted at a temporary directory whose `duoyi` entry links to this artifact. Read-only `HEAD` requests to `/duoyi/`, `/duoyi/version.json`, `/duoyi/flutter_bootstrap.js`, `/duoyi/flutter_service_worker.js`, and `/duoyi/main.dart.js` each returned HTTP 200. `GET` requests to the first three paths returned HTTP 200 and their response SHA-256 values matched the files above. The JavaScript bundle response advertised 9,659,626 bytes. No app credentials were supplied and no form or account actions were performed.

## Browser verification

Browser checks used Python Playwright 1.59.0 with its matching Chromium 147 headless shell, in fresh contexts at 390×844 and 1440×900. The loopback preview served the pinned artifact at `http://127.0.0.1:18763/duoyi/`; service workers were blocked. Requests were permitted only for `GET`/`HEAD` under that loopback path, except in the explicitly controlled CanvasKit substitution run below. No credentials, form submissions, or account actions were used.

The strict offline run is recorded at `.dart_tool/task-temp-20261011/accepted-head-browser-strict-offline-20261011.json`. Both paths returned HTTP 200 and the document title was `多仪`, but Flutter did not create a view or canvas; the page stayed blank. The probe blocked requests for CanvasKit JS/WASM from `www.gstatic.com` and Roboto from `fonts.gstatic.com`. The resulting failed module import explains this blank strict-offline state; it does not establish a layout defect. Its screenshots are [mobile 390×844](../screenshots/accepted-head-729f2ea-20261011-strict-offline/mobile-390x844.png) and [desktop 1440×900](../screenshots/accepted-head-729f2ea-20261011-strict-offline/desktop-1440x900.png).

A second, controlled render run fulfilled only the exact CanvasKit JS/WASM URLs requested by this build from byte-identical local files in its own `build/web/canvaskit/chromium/` directory. The locally substituted JS SHA-256 is `ff8dcd85cee325699499ee23ffd7567bc8086e9592c24d4d8d411f951c16bda4`; WASM SHA-256 is `2bf5ea09d70b8eadb22bb0471c9edfd7b2bee909dbf84456c32480d944660418`. All other external traffic remained blocked, including Roboto and Noto Sans SC font requests. The artifacts and route policy are recorded in `.dart_tool/task-temp-20261011/accepted-head-browser-canvas-local-verified-20261011.json` and the probe is `.dart_tool/task-temp-20261011/accepted-head-local-canvas-probe.py`.

In both `zh-CN` and fresh `en-US` contexts, both viewport sizes then produced one Flutter view and one viewport-sized canvas, and no page exceptions or non-blocking runtime errors were recorded. Screenshots are [mobile, zh-CN](../screenshots/accepted-head-729f2ea-20261011-canvas-local-repeat/mobile-390x844.png), [desktop, zh-CN](../screenshots/accepted-head-729f2ea-20261011-canvas-local-repeat/desktop-1440x900.png), [mobile, en-US](../screenshots/accepted-head-729f2ea-20261011-canvas-local-en/mobile-390x844-en.png), and [desktop, en-US](../screenshots/accepted-head-729f2ea-20261011-canvas-local-en/desktop-1440x900-en.png). The layout surfaces, navigation, cards, and spacing are visible, but several date/count numerals and some fallback Latin glyphs render as square boxes while many Chinese labels remain readable. A read-only [offline font audit](web-offline-font-audit-20261011.md) found the bundled Droid fallback maps 20,902 CJK ideographs but none of the ASCII digits or letters, consistent with the missing numerals/Latin glyphs when external Roboto and Noto Sans SC requests are blocked; it does not isolate the exact CanvasKit font-selection path. In the `en-US` screenshots the title is `Duoyi`; most English text is rendered as tofu boxes, while some Chinese lunar/almanac and quote text remains readable. Because the external font requests were blocked, these screenshots do not support a conclusion about locale switching. The screenshots are limited rendering evidence, not clean visual acceptance, and the controlled run substitutes CanvasKit locally rather than exercising its public-host delivery path.

The fresh loopback server used for the final controlled runs was stopped after capture. It listened only on `127.0.0.1:18763` and served the temporary preview root; that port is no longer in use by this run.

## Widget verification recorded separately

The isolated Flutter regression log `.dart_tool/task-temp-20261011/accepted-widget-locale-layout-20261011.log` records **27 passed and 1 skipped** (the Sunday-only skip) across `test/screens/widget_locale_layout_test.dart` and `test/widgets/widget_polish_interaction_test.dart`, using the accepted HEAD worktree. These widget tests are not a browser run and do not establish the compiled web layout.

The Swift display-core log `.dart_tool/task-temp-20261011/ios-widget-display-core-accepted-20261011.log` records **19 fixture cases passed**, `COMMAND_EXIT_CODE=0`, and Swift container digest `sha256:eccc7a97f9b9881d9659e2e788081fd7675f86d39793b51200bfb178398b3784`. The log records production-core and fixture source hashes but does not independently record the repository HEAD used when the runner executed. I recomputed the production-core hash (`b748ed33b9816d42ddded90abf192743760d4d201c7cb5362336838ca5ca5098`) and fixture hash (`79d1e8bcd67b513f75c0ba6504e65f05761ddd32a6a74f05acef12e90e809bcd`); both match the run log. At a later comparison checkpoint, commit `49b2d2a9fd865acdc2b28d7b19edbce832ff36cf`, the full `ios/DuoyiWidgets/DuoyiWidgets.swift` file SHA-256 was `47beb6af03ddcaee65c5b5ad564de419677ae07662057b06442028210e0f4b38`; the pinned `729f2ea` worktree has the same file hash. This after-the-fact comparison shows the source file bytes match between those two snapshots, but does not establish the runner's unrecorded HEAD. The verification covers the extracted pure core only; it does not compile the WidgetKit target or establish device rendering.

## Other local verification commands

These commands were inventoried but not run as part of the web artifact check:

- Backend update policy/API regression (inventoried, not run here): `DUOYI_DB_PATH=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/backend-update-policy-scratch.db SERVER_BACKUP_DIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/backend-backups DUOYI_AVATAR_UPLOAD_DIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/backend-avatars python3 -m unittest -v test_workspaces.WorkspaceApiTest.test_update_policy_fills_default_notes_and_mobile_update` from `backend/`. These explicit scratch paths avoid the production database, backup directory, and avatar directory; `backend/main.py` initializes its database at import, before the test fixture's per-test temporary database setup. The test uses `TestClient` and disables the release repository for the mobile endpoint portion. It was not run as part of this browser check. The existing `.dart_tool/task-temp-20261011/backend-regression-final.log` records a broader prior run of 154 backend tests passing in 129.002 seconds; a full repeat is unnecessary absent backend changes.
- Source-extracted Swift display core and fixture runner: `python3 scripts/verify_ios_widget_display_core.py --output-dir /home/ubuntu/duoyi/.dart_tool/task-temp-20261011/ios-widget-display-core-accepted`. This validates the marked pure display core against its Swift cases; it does not compile the WidgetKit target or render device UI.

## Limits

The strict offline run does not establish runtime rendering because the browser blocked the build's external CanvasKit and font dependencies. The controlled CanvasKit run establishes that the pinned bundle can create a Flutter view and canvas when its exact bundled renderer bytes are supplied, and gives a bounded look at mobile and desktop layout; it does not verify public CanvasKit delivery, font availability, clean text rendering, backend behavior, or authentication flows. The recorded widget layout and Swift core fixture runs do not cover web page rendering or full WidgetKit/provider integration. No physical-device, native installer, full WidgetKit target compilation, or Xcode acceptance was performed here. Same-name newer APK builds cannot be distinguished from release tags or file metadata when those sources omit the build code.
