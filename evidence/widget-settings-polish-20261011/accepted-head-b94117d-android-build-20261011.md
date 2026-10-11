# Android debug build acceptance

- Revision: `b94117d9aebe18f3f6d4a7002d8ef85f333deac8`
- Build tree: `/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/accepted-head-b94117d-android` (detached worktree)
- Build type: Flutter Android debug APK

Commands were run from the build tree. `android/local.properties` was copied from the main checkout for SDK discovery; no signing keys were copied or inspected.

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter pub get --offline --enforce-lockfile
# Exit code: 0

TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
GRADLE_USER_HOME=/home/ubuntu/duoyi-gradle-cache-20261010 \
  /home/ubuntu/flutter/bin/flutter build apk --debug --no-pub
# Exit code: 0
```

The build emitted an Android SDK tooling warning: the installed tooling supports SDK XML through version 3, while an SDK XML version 4 file was encountered. The build completed successfully in 1996.1 seconds.

- APK: `/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/accepted-head-b94117d-android/build/app/outputs/flutter-apk/app-debug.apk`
- Size: 219,888,933 bytes
- SHA-256: `ec9c0746e0bfd713c89c7a9e5437f23fee99e68c99bbb033ee59827aba576388`

Release signing and device behavior were not validated.

After result collection, root removed only this isolated build's derived
`build/app/intermediates`, `tmp`, `kotlin`, and `generated` directories to
relieve disk pressure. The APK, output paths, source worktree and build log
were retained. This cleanup does not change the build result.
