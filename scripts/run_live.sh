#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_LOG="$ROOT_DIR/.field_shift_server.log"
DEVICE="${1:-}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

cd "$ROOT_DIR/server"
dart pub get
dart run bin/server.dart >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in {1..30}; do
  if curl --silent --fail --max-time 1 http://127.0.0.1:8080/api/health >/dev/null; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$SERVER_LOG"
    exit 1
  fi
  sleep 1
done

if ! curl --silent --fail --max-time 1 http://127.0.0.1:8080/api/health >/dev/null; then
  cat "$SERVER_LOG"
  echo "NASA gateway did not become ready on port 8080." >&2
  exit 1
fi

if [[ -z "$DEVICE" ]]; then
  DEVICE_LIST="$(flutter devices 2>/dev/null || true)"
  if grep -Eq '^[[:space:]]*macOS \(desktop\)' <<<"$DEVICE_LIST"; then
    DEVICE="macos"
  elif grep -Eq '^[[:space:]]*Chrome' <<<"$DEVICE_LIST"; then
    DEVICE="chrome"
  else
    echo "No supported Flutter device found. Run 'flutter devices' and pass one to this script." >&2
    exit 1
  fi
fi

cd "$ROOT_DIR"
flutter run -d "$DEVICE" --dart-define=API_BASE_URL=http://127.0.0.1:8080/api
