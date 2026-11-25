# Android widget validation

The Flutter gallery, Android JVM contracts, host POSIX/SQLite transports and real Launcher behavior require different checks. A passing color/layout test or APK build does not establish store durability, widget rendering or action delivery on Android.

## Current test stack

The UI uses Flutter and Provider. Native JVM tests use JUnit4 plus the real `org.json` parser. The16existing JVM files contain232tests. A separate `androidTest` source set now uses `AndroidJUnitRunner`, AndroidX Test runner1.7.0 and JUnit extension1.3.0. The Gradle test stack has no Robolectric or new dependency-injection framework; the separate evidence-only SDK34/NATIVE callback harness described below uses pinned Robolectric without modifying the Gradle dependencies. The instrumentation suite calls real Android filesystem/SQLite APIs; it does not make those APIs executable in the default JVM suite.

The [current Flutter report](../evidence/goal-continuation-20261023/native-runtime-recheck/summary.md) records115passing widget/theme checks, including all ten preview kinds and both priority themes. They use simulated platform channels and do not execute RemoteViews or Android SQLite.

## Default JVM run

From `android/`, run `./gradlew :app:testDebugUnitTest` with the project's supported Java/SDK setup. The [2026-10-23 complete run](../evidence/goal-continuation-20261023/native-runtime-recheck/android-all.outcome.json) records232tests,228passes and4failures. Its Flutter compilation task was excluded to isolate native contracts.

All four failures are in `DuoyiWidgetPublicationStoreAdmissionTest`. The store now calls Android `Os.lstat` before reaching file-lock admission. The JVM's mockable Android jar throws `Method lstat in android.system.Os not mocked`, which the production failure handler maps to `unavailable`. Assertions expecting `absent` or `busy` therefore fail before exercising their intended branch. Three other admission cases expect `unavailable`; their passing status in this configuration does not prove their intended deeper branch. See the [direct probe and diagnosis](../evidence/goal-continuation-20261023/native-runtime-recheck/android-admission-diagnosis.json).

Do not enable `unitTests.returnDefaultValues`, weaken status assertions, skip the admission class or relax production no-follow/inode checks to make this command green. [Android's local-test documentation](https://developer.android.com/training/testing/local-tests) explains this exception and cautions that default null/zero returns can let failing tests pass.

## Existing host transport checks

The existing coordinator can execute the production store bytecode with explicit JNI host POSIX and Python host SQLite transports:

```bash
python3 evidence/widget-android-recovery-20261020/run_jvm.py <new-output-label>
```

Choose an unused label; the runner refuses an existing output directory. It compiles production sources against the actual Android SDK before substituting the explicit runtime transports. Its admission phase forbids SQLite entry using an `AssertionError` tripwire, outside the store's caught `Exception` path. Its recovery phase exercises host SQLite, file identities, lock races, contention and postcommit uncertainty in synthetic directories.

The [accepted historical run](../evidence/widget-android-recovery-20261020/summary.md) passes24document/admission checks and60recovery checks. [Current native reconciliation](../evidence/android-debug-current-20261023/native-historical-reconciliation.json) verifies that all seven production/test inputs still match. These overlapping checks must not be added to232as a unique total. This is host transport evidence; it neither changes the failed default Gradle result nor proves Android `Os`, SQLite connection-pool or device behavior.

## Platform and device acceptance

Actual Android filesystem/SQLite checks must run against Android APIs on a device or emulator; [instrumented tests](https://developer.android.com/training/testing/instrumented-tests) provide that environment. Use fresh app-private synthetic storage rather than existing user widget authority. Required boundaries include absent stores, orphan/dangling journals, shared/exclusive contention, removed/replaced/symlinked fixed locks, quarantine, synchronized commit/close/readback and stale action rejection. No instrumented runtime acceptance is claimed by the current host checks.

`android/app/src/androidTest/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationStoreDeviceTest.kt` provides18device tests with an independently copied v1 protocol fixture under `src/androidTest/assets/`. They create UUID-named directories beneath the app cache or no-backup directory and instantiate the production store with those isolated paths; they never call `forContext`, open the real `widget_publication_store`, launch an activity or use account data. The no-backup case deliberately retains Context's original path to exercise the production directory policy. The other cases use a canonical temporary cache path. Cleanup removes only their owned fixture directories.

Coverage includes absent reads, initialization and exact committed receipt replay, held/missing/replaced/symlinked fixed locks, regular/dangling orphan journals, corrupt/future databases, actual Cursor storage-type/64-bit ID rejection, stale render acceptance and seal-only recovery with fresh inspection/operation after receipt uncertainty. The latest two additions also verify that an operational mutation cannot initialize absent authority and an empty publication table cannot grant snapshot acceptance; recovery uncertainty additionally denies old-writer mutation and render callbacks. Postcommit fault injection, crash/hot-journal recovery and independent-process interleavings still require additional device evidence; these18cases are not comprehensive durability acceptance.

Compile the test APK from `android/`:

```bash
./gradlew :app:assembleDebugAndroidTest
```

With a test Android device attached, execute the actual suite:

```bash
./gradlew :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.duoyi.duoyi.DuoyiWidgetPublicationStoreDeviceTest
```

The connected task builds and installs the matching app/test APKs. Use a test device; successful test-APK assembly alone runs zero tests. Preserve the generated JUnit XML under `build/app/outputs/androidTest-results/connected/` and verify all18methods executed with zero failures, errors or skips. A device absent from ADB cannot produce acceptance. The [instrumentation preparation report](../evidence/widget-android-instrumented-20261023/summary.md) records actual build outcomes and current runtime availability separately.

The [current runtime attempt](../evidence/native-widget-runtime-20261023/summary.md) assembles all18methods and reconciles all59native production inputs against the available debug target APK. It reaches a real Android28 guest with ext4-backed data and a successful ADB `shell id`. Installing the target APK then exceeds600seconds, followed by a120second ADB diagnostic timeout during severe host resource pressure. No instrumentation method executed and no XML test result was produced. The owned VM was stopped after identity verification; those observations do not establish full Android boot, Launcher readiness, native durability or physical-device acceptance. The SDK-emulator and native-QEMU probes remain bounded environment attempts, not proof that all future emulator paths are unavailable.

### Independent lightweight Store test hosts

To isolate native Store and concurrency validation from the 222MB full Flutter debug target, two independent lightweight Android test applications were prepared and verified. These are distinct application packages from the in-tree `com.duoyi.duoyi.test` suite:

1. **Store standalone runtime host (`com.duoyi.duoyi.storetesthost`)**:
   Compiles five production Store sources with 18 original test methods plus 4 supplemental cases into a 1.75MB target and 916KB test APK. See the [isolated Store runtime host summary](../evidence/widget-store-runtime-host-20261023/summary.md). Across 4 QEMU/TCG runtime attempts, `system_server` initialization stalled (>301s); **22 packaged / 0 executed**.
   Runner entry:
   ```bash
   adb shell am instrument -w -r com.duoyi.duoyi.storetesthost.test/androidx.test.runner.AndroidJUnitRunner
   ```

2. **Cross-process lock host (`com.duoyi.duoyi.storelockhost`)**:
   Packages an unexported `:lock_holder` private-process Service and 2 instrumentation tests verifying OS file-lock contention and Binder death lock release (1.76MB target and 908KB test APK). See the [cross-process lock host summary](../evidence/widget-cross-process-host-20261023/summary.md). Runtime execution remains **2 packaged / 0 executed**.
   Runner entry:
   ```bash
   adb shell am instrument -w -r -e class com.duoyi.duoyi.DuoyiWidgetCrossProcessLockTest com.duoyi.duoyi.storelockhost.test/androidx.test.runner.AndroidJUnitRunner
   ```

Both lightweight hosts and the in-tree 18-method suite are separate packages with distinct runner entries. Across all three packages, **0 instrumentation methods have executed on a live Android device or completed emulator run**; physical device and native runtime gates remain open.

Follow [device regression evidence](device-regression-evidence.md) for all ten launcher widgets, compact/standard/detailed modes, add/resize/refresh/actions, notifications and retained state. The physical-device requirements and full goal remain open until their actual evidence passes. Build and analyzer outcomes are recorded separately in the [current Android build report](../evidence/android-debug-current-20261023/summary.md).


## 本机原生字体与布局回调（2026-11-13）

[614/615 验收记录](../evidence/theme-widget-resume-20261109-v898/robolectric-callback-acceptance-615.json)使用 Linux ARM64 Robolectric 4.18-beta-1、真实 SDK 34 二进制资源及 NATIVE graphics，执行现有测试的六个原始回调：六项通过，失败、忽略和 assumption 均为零；六个回调进入并返回，327 项输入复核无变化，保护进程和全部原始工作进程已退出。当前 Habit 139/140 测试迁移已包含在此次编译及运行中。

覆盖 Todo 两行头部、Habit 窄宽度标题让位、放大字体下完整百分比与待刷新状态、刷新文字框、必需头部和多行导航拒绝。此记录限 RemoteViews/XML、TextView 与 StaticLayout 的受控回调；不替代 Launcher 显示与点击、真实设备、OS/POSIX/Store、两主题像素或 iOS WidgetKit 验收。Habit 准入分支仍使用产品 Metrics，详见 [586 审查边界](../evidence/theme-widget-resume-20261109-v898/native-fixture-migration-audit-586.md)。

[628/630 两主题截图验收](../evidence/theme-widget-resume-20261109-v898/native-theme-screenshot-review-630.md)另外覆盖 defaultBrand/liquidGlass、Todo/Habit、中英文、plain_card、360×500dp 和双倍字体，共八张实际 provider 构建截图。已查看全部图像，复核 341 项输入及图像哈希无变化，保护进程与全部原始工作进程均已退出。可见文字未发现越界、省略或缺失尾部；默认主题的黑色强调文字来自产品对比度规则。此项执行主题配置、finishRender 和 RemoteViews.apply，仍未执行发布权限、Launcher 更新与点击、真实设备或 WidgetKit；八个截图方法不计入上述六个原始回调测试。

[634/639 其他八类小组件检查](../evidence/theme-widget-resume-20261109-v898/additional-theme-screenshot-review-639.md)生成并查看了 32 张双主题、中英文截图，复核 342 项输入无变化。日历的四个组合均发现底部月份说明被省略，故该批仅记录生成成功，日历布局验收未通过；其他 28 张仅在固定短内容用例下未发现同类文字问题。[640/656 窄布局验收](../evidence/theme-widget-resume-20261109-v898/narrow-theme-acceptance-656.json)另覆盖完整三条长待办、152dp 必需控件、139/140dp 完整习惯恢复提示、40dp 无可见内容说明和过期计数；八张图已由主会话查看，并通过独立策略审查。这些记录均不替代宿主发布、点击、设备或 WidgetKit 验收。

[678/679/680 控件点击验收](../evidence/theme-widget-resume-20261109-v898/native-click-acceptance-review-680.md)在一次完整 SDK34/NATIVE 运行中通过 16 项测试，覆盖 17 次实际可见控件点击、17 个独立桥接回执和一项隐藏控件零派发。终态复核 911 项当前输入及新编译测试产物无变化，全部原始验证进程已退出。旧账号控件在构建新账号小组件后仍携带原绑定；过期、缺失 ID 和旧式入口未获得账号授权。首次失败来自 Robolectric 将发送端 Intent 原对象交给测试；修正仅在测试接收边界复制 Intent，保留完整账号、URI 和回执断言，失败证据继续保留。此记录执行实际 provider、RemoteViews 控件、PendingIntent、Bridge 和 Queue，接收副本模拟对象隔离；仍未验证 Binder、MainActivity 生命周期、Flutter 通道与页面、Dart ACK、Store 操作、Launcher、R8 release 或设备行为。

[689/690 原生资源复用检查](../evidence/theme-widget-resume-20261109-v898/native-cache-terminal-acceptance-690.json)只运行上述一个既有用例，不增加产品通过数。实际字体路径指向已有缓存，296 项缓存文件及 1,216 项当前输入终态复核无变化，全部相关原始进程已退出。复用字体、ICU 和断词资源共 194,036,853 字节，新增验证文件占用 565,248 字节；Java 仍使用自己的少量临时运行文件。后续使用 [缓存校验器](../scripts/robolectric_asset_cache.py)在每个阶段重新核对源 jar 哈希、修改时间、缓存键和完整文件清单，保持单路验证及实时磁盘保护。[686 独立审查](../evidence/theme-widget-resume-20261109-v898/native-cache-reuse-audit-686.md)确认该接线没有放宽未来 Calendar 的新源码、新 SDK 和新资源要求；Calendar 八用例仍未执行。
