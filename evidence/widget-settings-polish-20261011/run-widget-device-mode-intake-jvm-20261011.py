#!/usr/bin/env python3
"""Compile the real JVM-safe widget sources/tests with already-cached jars."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path


ROOT = Path("/home/ubuntu/duoyi")
CACHE = Path("/home/ubuntu/duoyi-gradle-cache-20261010/caches/modules-2/files-2.1")
WORK = ROOT / ".dart_tool/task-temp-20261011/widget-device-mode-intake-jvm"
LOGS = ROOT / "evidence/widget-settings-polish-20261011/widget-device-mode-intake-jvm-acceptance-logs"
CLASSES = WORK / "classes"

SOURCES = [
    ROOT / "android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationDocument.kt",
    ROOT / "android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationEnvelope.kt",
    ROOT / "android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetFrameCore.kt",
    ROOT / "android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFrozenWidgetPreferences.kt",
    ROOT / "android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetRenderFrame.kt",
    ROOT / "android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetCopy.kt",
    ROOT / "android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetDisplayMode.kt",
    ROOT / "android/app/src/test/java/com/duoyi/duoyi/DuoyiWidgetPublicationDocumentTest.kt",
    ROOT / "android/app/src/test/java/com/duoyi/duoyi/DuoyiWidgetFrameCoreTest.kt",
    ROOT / "android/app/src/test/java/com/duoyi/duoyi/DuoyiFrozenWidgetPreferencesTest.kt",
    ROOT / "android/app/src/test/java/com/duoyi/duoyi/DuoyiWidgetDeviceDisplayValuesTest.kt",
]
TEST_CLASSES = [
    "com.duoyi.duoyi.DuoyiWidgetPublicationDocumentTest",
    "com.duoyi.duoyi.DuoyiWidgetFrameCoreTest",
    "com.duoyi.duoyi.DuoyiFrozenWidgetPreferencesTest",
    "com.duoyi.duoyi.DuoyiWidgetDeviceDisplayValuesTest",
]


def cached_jar(group: str, artifact: str, version: str) -> Path:
    matches = sorted((CACHE / group / artifact / version).glob("*/*.jar"))
    if len(matches) != 1:
        raise FileNotFoundError(
            f"Expected exactly one cached {group}:{artifact}:{version} jar; found {matches}"
        )
    return matches[0]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def save_process_log(path: Path, command: list[str], result: subprocess.CompletedProcess[str]) -> None:
    path.write_text(
        "COMMAND: " + shlex.join(command) + "\n"
        + f"EXIT: {result.returncode}\n"
        + "--- stdout ---\n"
        + result.stdout
        + ("\n" if result.stdout and not result.stdout.endswith("\n") else "")
        + "--- stderr ---\n"
        + result.stderr,
        encoding="utf-8",
    )


def main() -> int:
    WORK.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    if CLASSES.exists():
        shutil.rmtree(CLASSES)
    CLASSES.mkdir(parents=True)
    for source in SOURCES:
        if not source.is_file():
            raise FileNotFoundError(source)

    compiler_jars = [
        cached_jar("org.jetbrains.kotlin", "kotlin-compiler-embeddable", "2.2.20"),
        cached_jar("org.jetbrains.kotlin", "kotlin-stdlib", "2.2.20"),
        cached_jar("org.jetbrains.kotlin", "kotlin-script-runtime", "2.2.20"),
        cached_jar("org.jetbrains.kotlin", "kotlin-reflect", "1.6.10"),
        cached_jar("org.jetbrains.kotlin", "kotlin-daemon-embeddable", "2.2.20"),
        cached_jar("org.jetbrains.kotlinx", "kotlinx-coroutines-core-jvm", "1.8.0"),
    ]
    stdlib = cached_jar("org.jetbrains.kotlin", "kotlin-stdlib", "2.2.20")
    annotations = cached_jar("org.jetbrains", "annotations", "13.0")
    junit = cached_jar("junit", "junit", "4.13.2")
    hamcrest = cached_jar("org.hamcrest", "hamcrest-core", "1.3")

    compiler_cp = os.pathsep.join(map(str, [*compiler_jars, annotations]))
    android_api = Path("/home/ubuntu/android-sdk/platforms/android-35/android.jar")
    assert android_api.is_file()
    test_cp = os.pathsep.join(map(str, [stdlib, annotations, junit, hamcrest, android_api]))
    compile_command = [
        "java", "-Xmx512m", "-cp", compiler_cp,
        "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
        "-no-stdlib", "-no-reflect", "-jvm-target", "17",
        "-classpath", test_cp,
        "-d", str(CLASSES),
        *map(str, SOURCES),
    ]
    source_hashes_before = {str(path.relative_to(ROOT)): sha256(path) for path in SOURCES}
    compiler = subprocess.run(
        compile_command, cwd=ROOT, text=True, capture_output=True, check=False,
    )
    save_process_log(LOGS / "01-kotlin-compile.log", compile_command, compiler)

    result: dict[str, object] = {
        "root": str(ROOT),
        "cache_root": str(CACHE),
        "java_heap": "512m",
        "kotlin_compiler": "2.2.20 K2JVMCompiler",
        "jvm_target": "17",
        "compile_command": compile_command,
        "compiler_exit": compiler.returncode,
        "compiler_log": str(LOGS / "01-kotlin-compile.log"),
        "source_hashes_before": source_hashes_before,
        "cached_jars": {str(path): sha256(path) for path in [*compiler_jars, annotations, junit, hamcrest, android_api]},
        "test_command": None,
        "test_exit": None,
        "test_count": None,
        "test_log": None,
    }

    if compiler.returncode == 0:
        runtime_cp = os.pathsep.join(map(str, [CLASSES, stdlib, annotations, junit, hamcrest, android_api]))
        test_command = [
            "java", "-Xmx512m", "-cp", runtime_cp,
            "org.junit.runner.JUnitCore", *TEST_CLASSES,
        ]
        tests = subprocess.run(
            test_command, cwd=ROOT, text=True, capture_output=True, check=False,
        )
        save_process_log(LOGS / "02-junit.log", test_command, tests)
        test_output = tests.stdout + "\n" + tests.stderr
        count_match = re.search(r"OK \((\d+) tests?\)", test_output)
        result.update({
            "test_command": test_command,
            "test_exit": tests.returncode,
            "test_count": int(count_match.group(1)) if count_match else None,
            "test_log": str(LOGS / "02-junit.log"),
        })

    source_hashes_after = {str(path.relative_to(ROOT)): sha256(path) for path in SOURCES}
    result["source_hashes_after"] = source_hashes_after
    result["source_hashes_unchanged"] = source_hashes_before == source_hashes_after
    summary_path = LOGS / "runner-summary.json"
    summary_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if compiler.returncode != 0:
        return compiler.returncode
    return int(result["test_exit"])


if __name__ == "__main__":
    raise SystemExit(main())
