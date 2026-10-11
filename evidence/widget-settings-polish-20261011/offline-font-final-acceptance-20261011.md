# Offline web font acceptance — 2026-10-11

## Candidate scope

Validation used the detached `4dbf766` candidate under `.dart_tool/task-temp-20261011/font-candidate-4dbf766`. Its task manifest records the five font-related source files below; all five SHA-256 values matched before validation:

| Source file | SHA-256 |
| --- | --- |
| `assets/fonts/DejaVuSans.ttf` | `690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648` |
| `assets/fonts/DejaVuSans-LICENSE.txt` | `9017a163db9ef1168811dca991bca1293cbdca2c6c78bfa4567750e6bcf2d733` |
| `lib/core/app_brand.dart` | `63dc0eebbd54ab15a60c28998851ec5e2c50cf4c2ae77c5c3a9b0869b7dc2219` |
| `pubspec.yaml` | `97c5396a7c1c36f3adf815ed1f099f997aa8afbdbe7cb1023f404f746af002ba` |
| `test/core/web_cjk_font_static_test.dart` | `3ac38ad5f259fba7879ba5c242edbe932bb81e736a37a1ab432e2619432b9d89` |

This establishes the font change on that accepted Today snapshot. It does not validate every unrelated source change in the main working tree.

## Flutter validation

- `flutter pub get --offline`: succeeded.
- `flutter test --no-pub --concurrency=1 --reporter expanded test/core/web_cjk_font_static_test.dart`: **4 tests passed**.
- `flutter analyze --no-pub lib/core/app_brand.dart test/core/web_cjk_font_static_test.dart`: no issues found across 2 items.
- `flutter build web --no-pub --release --no-wasm-dry-run --base-href /duoyi/`: succeeded in 118.1 seconds.

Logs are in `.dart_tool/task-temp-20261011/font-candidate-pub-get-20261011.log`, `font-candidate-static-test-20261011.log`, `font-candidate-analyze-20261011.log`, and `font-candidate-web-build-20261011.log`.

## Built asset hashes

The packaged font and license match their source bytes exactly. `assets/FontManifest.json` places `DejaVu Sans` before `DroidSansFallbackFull`.

| Build file | Bytes | SHA-256 |
| --- | ---: | --- |
| `index.html` | 2,458 | `dbb9336b491b42b296be0432f5b29157eb019bbc3b53e866e05a966ad4753d87` |
| `flutter_bootstrap.js` | 9,972 | `2f0e8e99f6074cfbe53a2ea599b0aa3b9c1e1ed3ea7d627f373fb13ec76f8938` |
| `main.dart.js` | 9,699,527 | `4f97225f3977187aca03287cb49c9962f3506468ef4e9a2911e0bc1fb09b224a` |
| `assets/FontManifest.json` | 379 | `4af73b0354763a1c858355295e7fcabb81211866bd3dc79c79877909a612c8a8` |
| `assets/assets/fonts/DejaVuSans.ttf` | 757,076 | `690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648` |
| `assets/assets/fonts/DejaVuSans-LICENSE.txt` | 9,712 | `9017a163db9ef1168811dca991bca1293cbdca2c6c78bfa4567750e6bcf2d733` |

Font manifest order: MaterialIcons, DejaVu Sans, DroidSansFallbackFull, CupertinoIcons.

## Offline browser comparison

The prepared Playwright runner served only the candidate build under `/duoyi/`. It blocked all other outbound requests and fulfilled the two CanvasKit assets from this same build. It ran A (block the local DejaVu TTF) and B (allow the local DejaVu TTF) for Chinese and English at 390×844 and 1440×900: **8 scenarios**.

The executed runner is preserved as [offline-font-ab-runner-20261011.py](offline-font-ab-runner-20261011.py), SHA-256 `26b2b919b0656cafe9ffce68c75410f473eb05bc33466db276a78ac1a244b019`. Reproduce with `python3 <runner> --build-dir <candidate>/build/web --output-dir <evidence-directory>` and an available Playwright Chromium installation.

All scenarios returned HTTP 200 and reached `document.readyState=complete`, with one Flutter view, one glass pane, one canvas, and `/duoyi/` as the base href. Each scenario fulfilled both CanvasKit assets from the build. A made zero successful DejaVu GETs. B made one successful GET per scenario; each response was 757,076 bytes with SHA-256 `690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648`.

There were 49 `request-failed` events across the scenarios, all marked `expectedByOfflinePolicy`; there were no unmarked failed requests, page errors, HTTP errors, or runner fatal errors. The corresponding browser console messages were for those intentionally blocked font requests.

| Locale and viewport | A/B screenshot pixels changed | A SHA-256 | B SHA-256 |
| --- | ---: | --- | --- |
| Chinese, 390×844 | 23,429 / 329,160 | `c7d22cf9dcfc4484edfe96d81a0e23ab92e5619ee23071791a0d3170d04dba92` | `68f78980a2790612f4c8882cc4b94c3d4bbda05010c13aa55f41cd3f871fefca` |
| Chinese, 1440×900 | 63,445 / 1,296,000 | `18854d17203995aaba22072c1deba4d7d181530523b376d1f511e730b60e09b3` | `a7a1a0a91d9edbe4f9c784fd8c5a7d64026bee1f39592739fe3e7678acaece72` |
| English, 390×844 | 106,858 / 329,160 | `ba2a50e9406f3bdb7664faa1c8cacaa11626b6e5e21238bb9b7c4c4038bed8e8` | `86aab88297b010f17749411c5e144d45b870ab11567a41432f4c3ea1c469bd95` |
| English, 1440×900 | 118,701 / 1,296,000 | `79c82c981cd18173dfaa3f8a7d49de43d754d8884918d220478c3fb203e3c252` | `9d282aedf5506d73b15fe7beac19287dffa4e8e9567c2ae9a1fd22773910504e` |

Root inspected all eight screenshots in the [mobile contact sheet](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/contact-mobile-390x844.png) and [desktop contact sheet](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/contact-desktop-1440x900.png). With DejaVu blocked, Latin labels and numerals render as missing-glyph squares, including the English greeting/navigation and Chinese date/counters. With the bundled font enabled, those labels and numerals are readable in both locales and viewports. This confirms offline glyph recovery on the pinned candidate; it does not establish global localization, device performance, or acceptance of the other pending frontend changes.

Screenshots and run records are in `evidence/screenshots/widget-settings-offline-font-ab-20261011/`:

| View | A: DejaVu blocked | B: DejaVu loaded |
| --- | --- | --- |
| Chinese mobile | [A screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/A-block-local-dejavu-zh-mobile-390x844.png) | [B screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/B-allow-local-dejavu-zh-mobile-390x844.png) |
| Chinese desktop | [A screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/A-block-local-dejavu-zh-desktop-1440x900.png) | [B screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/B-allow-local-dejavu-zh-desktop-1440x900.png) |
| English mobile | [A screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/A-block-local-dejavu-en-mobile-390x844.png) | [B screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/B-allow-local-dejavu-en-mobile-390x844.png) |
| English desktop | [A screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/A-block-local-dejavu-en-desktop-1440x900.png) | [B screenshot](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/B-allow-local-dejavu-en-desktop-1440x900.png) |

Run records: [readiness](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/offline-font-ab-readiness.json), [errors and blocked requests](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/offline-font-ab-errors.json), and [font requests](/home/ubuntu/duoyi/evidence/screenshots/widget-settings-offline-font-ab-20261011/offline-font-ab-font-requests.json).
