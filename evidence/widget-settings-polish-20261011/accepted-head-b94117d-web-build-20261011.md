# Isolated Web release build evidence

Revision: `b94117d9aebe18f3f6d4a7002d8ef85f333deac8`; version `1.1.46+140012`.
The detached build tree was `.dart_tool/task-temp-20261011/accepted-head-b94117d-web`.

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter build web --no-pub --release \
  --base-href /duoyi/ --dart-define=DUOYI_SERVER_URL=/duoyi \
  --dart-define=DUOYI_WEB_TARGET=mobile
```

The build completed with exit 0 in 1267.0 seconds. Log:
`.dart_tool/task-temp-20261011/accepted-head-b94117d-web-build.log`.
Artifact: the detached tree's `build/web/`.

A loopback static-server probe performed GET and HEAD requests for six assets.
All returned HTTP 200, and received content hashes matched the build files.
Probe result: `.dart_tool/task-temp-20261011/accepted-head-b94117d-web-static-20261011.json`.
The loopback server was closed afterward.

| Asset | SHA-256 |
| --- | --- |
| `main.dart.js` (9,662,378 bytes) | `e93bed4cebc84081cf10b9b72174a82ad86dceb7137582b8dccd0887a94163f9` |
| `flutter_bootstrap.js` | `ee7ad74b33d956954cca3b0166c93f93f6543a979178aec10d7961bc2a4f2e8c` |
| `index.html` | `dbb9336b491b42b296be0432f5b29157eb019bbc3b53e866e05a966ad4753d87` |

This artifact predates commits `c8236fe`, `666c26c`, and the new frontend
patches. It has not been deployed and does not establish current-candidate
browser rendering or offline font coverage. The broader analyzer process was
terminated (analysis-server exit -15); its wrapper exit code is not evidence
of clean analysis. No signing, device validation, or delivery follows from
this build.
