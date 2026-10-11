# Nameless custom sound metadata — scoped acceptance

Date: 2026-10-11 UTC. This extends the missing-selection placeholder repair in `a2b43cc` to retained custom sound objects with missing/null metadata names.

## Changed behavior

`CustomFocusSound` keeps a nullable stored name and resolves generated display copy when read. Missing/null names follow the live locale as Custom audio/自定义音频; an explicit locale read does not change the global locale. The provider's `labelFor` passes its locale to that retained object.

Explicit saved names remain literal, including empty strings, whitespace, and names equal to either old default. Serialization preserves the nullable marker rather than saving a translated display name. An imported file with an empty basename creates this generated marker; ordinary imported names stay literal. No IDs, storage keys, file paths, playback registration or focus configuration fields were changed.

## Evidence

The root ran three serial `flutter test --no-pub --concurrency=1 --reporter=expanded` suites: provider locale **6 passed**, custom contract **1 passed**, and Pomodoro config **9 passed**. Five-item scoped analysis found no issues; every command exited 0. All ten input hashes match before, after and the current tree.

Raw logs, commands and hashes: `custom-sound-nameless-final-acceptance-20261011/`. The Sol source audit also confirmed consumers read labels without writing display copy back to storage.

## Remaining scope

No actual file-picker import, mounted Goal/Pomodoro sound picker locale repaint, custom-file portability, audio/device execution or smoothness acceptance is claimed. Those frontend and runtime cases remain part of the original active goal. This batch made no version, APK, push or deployment.
