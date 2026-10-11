# Widget publication-state JVM acceptance — 2026-10-11

## Result

The cached-only JVM acceptance passed: Kotlin compilation exited `0`, and JUnit ran 31 tests across `DuoyiWidgetPublicationDocumentTest` and `DuoyiWidgetFrameCoreTest` with exit `0` (`OK (31 tests)`). The production Kotlin sources and test sources listed below had identical SHA-256 hashes before and after the run.

## Commands and scope

Runner command:

```sh
python3 .dart_tool/task-temp-20261011/run_widget_publication_state_jvm.py
```

The runner invoked the cached Kotlin 2.2.20 `K2JVMCompiler` with `java -Xmx512m`, `-jvm-target 17`, then ran JUnit 4.13.2 `JUnitCore` with the same heap limit. The exact expanded compile and JUnit commands, classpaths, and process exit codes are recorded in the logs:

- [Kotlin compile log](widget-publication-state-jvm-acceptance-logs/01-kotlin-compile.log) — exit `0`
- [JUnit log](widget-publication-state-jvm-acceptance-logs/02-junit.log) — exit `0`, 31 tests passed
- [Runner summary](widget-publication-state-jvm-acceptance-logs/runner-summary.json) — versions, cached JAR hashes, commands, and source hashes

The compile included these real sources:

- `DuoyiWidgetPublicationDocument.kt`
- `DuoyiWidgetPublicationEnvelope.kt` (required dependency referenced by the publication-document tests)
- `DuoyiWidgetFrameCore.kt`
- `DuoyiWidgetPublicationDocumentTest.kt`
- `DuoyiWidgetFrameCoreTest.kt`

Dependencies came from `/home/ubuntu/duoyi-gradle-cache-20261010`; no Gradle, Flutter, network, installs, generated stubs, or device commands were used. `DuoyiFrozenWidgetPreferencesTest` was not run.

## Initial compile attempt

The first compile used the two requested production files and two test files, but omitted `DuoyiWidgetPublicationEnvelope.kt`. It exited `1`: `DuoyiWidgetPublicationDocumentTest.kt` could not resolve `DuoyiWidgetPublicationEnvelope` (first reported at line 417, with further dependent unresolved references). The temporary runner was then updated to include that real production dependency; no production or test file was changed. The final successful compile supersedes the initial attempt. Its original log was overwritten by the final compile log, so the failure details are recorded here rather than presented as a retained log.

The successful compile emitted Kotlin visibility warnings for the two private-constructor data classes in the envelope source and one unchecked test cast. There were no compile errors.

## Source hashes

The runner recorded the same hashes before and after compilation for every compiled source:

| Source | SHA-256 |
| --- | --- |
| `DuoyiWidgetPublicationDocument.kt` | `76a0327ca702a423737b859f357d398c9a08b928046a041500e2edea2f050538` |
| `DuoyiWidgetPublicationEnvelope.kt` | `4e815f7c2c0df318a5da21533fe8c784cbcee2afb28b2a9a7e53e8032a501a3d` |
| `DuoyiWidgetFrameCore.kt` | `87917bd3877e925f5744e948d8039989e546a4393c4da0b08ef78b54489d0d12` |
| `DuoyiWidgetPublicationDocumentTest.kt` | `7c257adab1d62b6336da897f19f7c009403f6bc7e78efa2df02773030ea32e7b` |
| `DuoyiWidgetFrameCoreTest.kt` | `cc7ccd2c8fc9d59fbee2dc819b60d07bde505ea2c86e5d4413af346bfaf50175` |

## Evidence limit

This verifies the pure JVM publication document, its envelope dependency, frame-core behavior, and their named unit tests. It does not establish Android/FrozenPreferences integration, renderer behavior, or device acceptance.
