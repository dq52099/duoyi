# Backend final regression — 2026-10-11

- Result: **PASS** — 154 tests passed, 0 failures, 0 errors; unittest runtime 132.590 seconds; process exit code 0.
- Tested checkout: `cf4ed63ed7382381f7a2dce7337547e7d12f6868`.
- Requested baseline: `f2bc7b3`. `git diff f2bc7b3 cf4ed63 -- backend` is empty, so the backend files at the tested checkout match that baseline.
- `git status --short backend` was empty after the run.

## Command and isolation

```sh
/usr/bin/python3 -m unittest discover -s backend -v
```

The command ran from the repository root with `env -i`, `PYTHONDONTWRITEBYTECODE=1`, a temporary `DUOYI_DB_PATH`, `SERVER_BACKUP_DIR`, `DUOYI_AVATAR_UPLOAD_DIR`, and `DUOYI_MOBILE_APK_DIR` under `.dart_tool/task-temp-20261011/backend-final-regression-20261011/`; `APP_UPDATE_REPOSITORY` was empty and `REMINDER_EMAIL_POLL_SECONDS=3600`. No dependencies were installed.

Full output: `.dart_tool/task-temp-20261011/backend-final-regression-20261011.log` (exit code file: `.dart_tool/task-temp-20261011/backend-final-regression-20261011.exit-code`).

## Runtime versions and caveat

- Python 3.10.12
- FastAPI 0.136.3; Starlette 1.2.0; Pydantic 2.11.7
- Uvicorn 0.35.0; HTTPX 0.28.1; python-multipart 0.0.12; AnyIO 4.13.0

The available system packages do not match several versions pinned by `backend/requirements.txt` (FastAPI 0.115.6, Pydantic 2.10.3, Uvicorn 0.34.0, python-multipart 0.0.20). The regression passed with the preinstalled system interpreter and packages; dependencies were not changed.

## Backend source integrity

The pre-run source manifest SHA-256 is `7dfdbc1e1ef214f00081d3ad2c582974a3182afa2d58be7d508551a956cdcac0` and it still matches. Recorded file hashes:

- `backend/main.py`: `bf620c243f83c3f4947dc5cd0fa67c88b2358701d43079058d24c9c8b1f6b137`
- `backend/requirements.txt`: `da9a52abb763bad1888fcb57b5385b4946ba013a7873215cffd36eb28fc7fcfe`
- `backend/test_workspaces.py`: `40cc344173c4e6d3616d5f06846cf8613b5c5e734528e24d15c140ec28f627ef`
