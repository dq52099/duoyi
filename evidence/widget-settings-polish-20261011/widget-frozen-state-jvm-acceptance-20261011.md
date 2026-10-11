# Widget frame and frozen preferences JVM acceptance — 2026-10-11

## Result

The final cached-only Kotlin compile and JUnit run both exited **0**. Three suites passed **41 tests**: `DuoyiWidgetPublicationDocumentTest`, `DuoyiWidgetFrameCoreTest`, and `DuoyiFrozenWidgetPreferencesTest`. The first two overlap the earlier 31-test acceptance; the frozen-preferences suite adds 10 tests. All nine compiled source/test hashes were unchanged before and after execution.

The tests exercise the actual read-only preference implementation and render-value projection, including fresh values, stale daily masking, entity removal, counters, locale, timer trust and clock formatting, alongside the new exact published-state gate. Cleared/absent neutral copy and preview corrections are still pending frontend work.

## Execution

Runner: `.dart_tool/task-temp-20261011/run_widget_frozen_state_jvm.py`. It uses the cached Kotlin 2.2.20 compiler, Java 17 with `-Xmx512m`, JUnit 4.13.2, and the installed Android 35 API jar for interface/class definitions. It compiles these real production files plus their three named tests:

- `DuoyiWidgetPublicationDocument.kt`
- `DuoyiWidgetPublicationEnvelope.kt`
- `DuoyiWidgetFrameCore.kt`
- `DuoyiFrozenWidgetPreferences.kt`
- `DuoyiWidgetRenderFrame.kt`
- `DuoyiWidgetCopy.kt`

No source stubs, downloads, Gradle, Flutter or devices were used. The original license/source files and preferences were not changed.

Logs and exact commands, dependency hashes, source hashes and exit codes are in `widget-frozen-state-jvm-acceptance-logs/`: `01-kotlin-compile.log`, `02-junit.log`, and `runner-summary.json`.

## Initial harness failure

The first compile succeeded, but the JUnit runtime classpath omitted the Android API jar. Frozen-preferences initialization failed with `NoClassDefFoundError: android/content/SharedPreferences`; the existing document/frame suites still ran. The temporary runner was corrected to include the same API jar at runtime. Initial logs were preserved with an `initial-` prefix; the subsequent 41-test run supersedes this harness failure. Production and test sources were unchanged.

## Evidence limits

This is JVM acceptance of the named implementation and projection tests. The API jar supplies Android type definitions; it does not provide a running Android platform. Launcher layouts, Binder updates, touch delivery, resize behavior, notifications and real devices remain unverified by this run.
