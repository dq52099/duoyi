# Android widget platform compilation — 2026-10-11

## Scope and result

At native source HEAD `c9c742f4d9792a1dbb85923cfa455a7b72f63a79`, the Android debug Kotlin/resource dependency build completed successfully at **09:51:24 UTC**. Gradle reported **208 actionable tasks: 203 executed, five up to date**. Runner duration was 471.793 seconds; exit code was 0.

This compiles the current Android sources, including the later publication-state and device-display intake changes that the previous APK evidence predates. It closes the platform compilation gap left by the pure JVM runner.

## Reproducible command

```sh
cd /home/ubuntu/duoyi/android
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
GRADLE_USER_HOME=/home/ubuntu/duoyi-gradle-cache-20261010 \
  ./gradlew :app:compileDebugKotlin --offline \
    -x :app:compileFlutterBuildDebug --max-workers=1 --no-daemon \
    -Dorg.gradle.jvmargs=-Xmx2G --console=plain
```

The build used the existing SDK and dependency cache. No package upgrade, signing change, download, release build, or deployment was performed.

## Evidence inspected

- [compile.log](android-widget-platform-compile-20261011/compile.log): final `BUILD SUCCESSFUL` and the actual app Kotlin/resource tasks.
- [summary.json](android-widget-platform-compile-20261011/summary.json): exit code, timing, and 16 required output classes, including all ten catalog providers, Snapshot, publication/store/launch adapters, day-boundary scheduling, and configuration.
- [declared-component-classes.json](android-widget-platform-compile-20261011/declared-component-classes.json): **all 36** app-owned widget components and `MainActivity` declared in the manifest have class outputs; their SHA-256 hashes are recorded.
- [sources-before.json](android-widget-platform-compile-20261011/sources-before.json) and [sources-after.json](android-widget-platform-compile-20261011/sources-after.json): hashes matched for **273** tracked Android sources/resources/build files and selected Flutter inputs. Dart widget schedule integration happened after this compilation and is accepted separately.

The log retains existing deprecation and Kotlin data-class copy-visibility warnings. They did not cause a build error under the current Kotlin 2.2.20 toolchain.

## Remaining boundaries

The command excludes Flutter compilation and produces no packaged APK. It runs no Android unit, instrumentation, or launcher test. Class outputs prove compilation, not pinning, Binder delivery, resizing, alarms, action execution, visual fidelity, or smoothness. Existing **47 JVM checks** remain separate evidence; no new JVM count is claimed here. Android launcher/device acceptance, iOS/Xcode rendering, and final signed delivery remain open.
