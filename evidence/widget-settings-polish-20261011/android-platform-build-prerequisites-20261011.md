# Android platform build prerequisites — 2026-10-11

Read-only audit at `HEAD c9c742f4d9792a1dbb85923cfa455a7b72f63a79` on Linux `aarch64`. No Flutter, Dart, Gradle, test, download, install, or signing-secret inspection was performed.

## Finding

The local toolchain and caches are sufficient to attempt a debug compile. A current-HEAD compile has **not** been recorded: the most recent full APK evidence is for `b94117d`, and `c9c742f` changes three Android main-source files (`DuoyiWidgetFrameCore.kt`, `DuoyiWidgetPublicationDocument.kt`, and `DuoyiWidgetSnapshot.kt`). Re-run a native compile for this HEAD before treating those edits as compiled.

Existing evidence:

- [native-check/run.py](../../.dart_tool/task-temp-20261011/native-check/run.py) records a direct Gradle `:app:compileDebugKotlin --offline` invocation with `:app:compileFlutterBuildDebug` excluded. [native-check/build.log](../../.dart_tool/task-temp-20261011/native-check/build.log) ends `BUILD SUCCESSFUL` (3m57s; 209 actionable tasks, four executed), but is timestamped 01:37 UTC, before the later `b94117d` and current `c9c742f` edits. It verifies the prior native source/toolchain only, not the Flutter Dart snapshot.
- [accepted-head-b94117d-android-build-20261011.md](accepted-head-b94117d-android-build-20261011.md) records `flutter pub get --offline --enforce-lockfile` and `flutter build apk --debug --no-pub`, both exit 0. The full debug APK build took 1996.1s and emitted a nonfatal SDK XML v4 versus v3 tooling warning. That build predates the three current Android source edits. Its recorded APK output directory is absent now, so the artifact is not presently available at the recorded path.
- No Android build failure appears in the inspected task-temp records. No explicit `android.aapt2FromMavenOverride` property was found in the project or the inspected Gradle/task-temp configuration.

## Present toolchain and inputs

| Input | Read-only finding |
| --- | --- |
| Host / Java | `aarch64`; OpenJDK `17.0.20.1`, native AArch64 binary. The Android module targets Java/Kotlin 17. |
| Flutter / Dart | Flutter version file `3.41.9`; Dart version file `3.11.5`; Dart executable is AArch64. Flutter Gradle extension defaults are compile/target SDK 36, min SDK 24, NDK `28.2.13676358`. |
| Android SDK | `local.properties` points to `/home/ubuntu/android-sdk`; API 36 platform (revision 2), build-tools 36.0.0, command-line tools 12.0, and NDK `28.2.13676358` are present. |
| Gradle / plugins | Wrapper specifies Gradle 8.14 and its distribution is cached under `/home/ubuntu/duoyi-gradle-cache-20261010`. AGP 8.11.1 and Kotlin Gradle plugin 2.2.20 cache directories are present. |
| App libraries | Gradle caches contain `core-ktx:1.13.1`, `play-services-location:21.3.0`, and `desugar_jdk_libs:2.1.5`; core-library desugaring is enabled. |
| Flutter packages | `.dart_tool/package_config.json` and `.flutter-plugins-dependencies` exist; the pub cache has 305 hosted packages. The Android plugin list includes `audioplayers_android`, `connectivity_plus`, `file_selector_android`, `flutter_local_notifications`, `flutter_timezone`, `home_widget`, `integration_test`, `jni`, `jni_flutter`, `permission_handler_android`, `share_plus`, `shared_preferences_android`, and `url_launcher_android`. |
| Disk | `df` reports about 31 GiB available on `/`. |

`/home/ubuntu/.local/bin/aapt2` is on PATH and symlinks to SDK build-tools 36.0.0 `aapt2`; the target binary is x86-64, not native AArch64. The host has enabled `qemu-x86_64` binfmt registration, and the recorded full debug APK build succeeded without an explicit AAPT2 override. This is a working emulation path with a long prior build time, not a native ARM AAPT2 binary.

The ten widget-category providers are Todo, FocusHabit, Habit, Calendar, Schedule, Goal, Course, Note, Anniversary, and Diary; compact/detailed subclasses live in `DuoyiWidgetVariantProviders.kt`. The manifest also has the separate general `DuoyiWidgetProvider`. Native widget/application adapters include `DuoyiWidgetSnapshot`, `DuoyiWidgetFrameCore`, `DuoyiWidgetPublicationDocument`, `DuoyiWidgetPublicationBridge`, `DuoyiWidgetLaunchBridge`, and `MainActivity` method-channel handlers. A single `:app:compileDebugKotlin` target compiles the Android app Kotlin sources and their plugin compile dependencies; a full debug APK build also runs the Flutter debug asset/kernel task and packaging. No release signing material is needed for these debug commands.

## Suggested commands (not run)

For the Android Kotlin providers, Snapshot, and host adapters only, the historical successful Gradle shape is:

```sh
cd /home/ubuntu/duoyi/android
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
GRADLE_USER_HOME=/home/ubuntu/duoyi-gradle-cache-20261010 \
  ./gradlew :app:compileDebugKotlin --offline \
    -x :app:compileFlutterBuildDebug --max-workers=1 --no-daemon \
    -Dorg.gradle.jvmargs=-Xmx2G
```

That exclusion deliberately skips Dart compilation. To compile the complete Flutter Android debug app, including the Flutter app snapshot/kernel and Android packaging, use the previously accepted full-build command:

```sh
cd /home/ubuntu/duoyi
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
GRADLE_USER_HOME=/home/ubuntu/duoyi-gradle-cache-20261010 \
  /home/ubuntu/flutter/bin/flutter build apk --debug --no-pub
```

The current package config is present, so `--no-pub` avoids changing dependency resolution. If it is stale or missing when building, the recorded offline prerequisite is `flutter pub get --offline --enforce-lockfile`; the prior run completed successfully with exit 0. The SDK XML warning may recur and was nonfatal in the historical APK build.
