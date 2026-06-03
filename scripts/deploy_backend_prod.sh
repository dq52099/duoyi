#!/usr/bin/env bash
set -euo pipefail

SERVICE="${DUOYI_BACKEND_SERVICE:-duoyi-backend}"
PUBLIC_BASE="${DUOYI_PUBLIC_BASE:-http://6688667.xyz}"
LOCAL_BASE="${DUOYI_LOCAL_BASE:-http://127.0.0.1:18015}"

echo "Restarting ${SERVICE}..."
sudo systemctl restart "${SERVICE}"

echo "Waiting for local backend..."
for _ in $(seq 1 30); do
  if curl -fsS "${LOCAL_BASE}/api/config" >/tmp/duoyi_backend_config.json; then
    break
  fi
  sleep 1
done

if ! curl -fsS "${LOCAL_BASE}/api/config" >/tmp/duoyi_backend_config.json; then
  echo "Backend did not become healthy at ${LOCAL_BASE}" >&2
  sudo systemctl status "${SERVICE}" --no-pager >&2 || true
  exit 1
fi

echo "Verifying public /api/config..."
curl -fsS "${PUBLIC_BASE}/api/config" >/tmp/duoyi_public_config.json

echo "Verifying theme route is loaded..."
theme_status="$(
  curl -sS -o /tmp/duoyi_theme_route.json -w '%{http_code}' \
    -X POST "${PUBLIC_BASE}/api/theme-shop/apply" \
    -H 'Content-Type: application/json' \
    -d '{"theme_id":"defaultBrand"}'
)"
if [ "${theme_status}" != "401" ]; then
  echo "Expected /api/theme-shop/apply to return 401 without token, got ${theme_status}" >&2
  cat /tmp/duoyi_theme_route.json >&2 || true
  exit 1
fi

echo "Verifying focus room route is loaded..."
focus_status="$(
  curl -sS -o /tmp/duoyi_focus_route.json -w '%{http_code}' \
    "${PUBLIC_BASE}/api/focus-rooms/deep_work_room/ranking"
)"
if [ "${focus_status}" != "401" ]; then
  echo "Expected focus ranking to return 401 without token, got ${focus_status}" >&2
  cat /tmp/duoyi_focus_route.json >&2 || true
  exit 1
fi

echo "Backend deployment verified."
python3 - <<'PY'
import json
from pathlib import Path

payload = json.loads(Path("/tmp/duoyi_public_config.json").read_text())
print(
    "current_version={version} latest_version={latest} routes_hash={routes}".format(
        version=payload.get("current_version"),
        latest=payload.get("latest_version"),
        routes=payload.get("required_routes_hash"),
    )
)
PY
