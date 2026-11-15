#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_LOG="$ROOT_DIR/.field_shift_server.log"
DEVICE="${1:-}"
API_HOST="${API_HOST:-}"

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

DEVICE_INFO="$(flutter devices --machine 2>/dev/null || true)"
ANDROID_DEVICE=false
if ! command -v adb >/dev/null 2>&1 &&
   python3 -c 'import json, sys; device = sys.argv[1]; print(any(item.get("id") == device and item.get("targetPlatform", "").startswith("android") for item in json.load(sys.stdin)))' "$DEVICE" <<<"$DEVICE_INFO" | grep -q '^True$'; then
  ANDROID_DEVICE=true
fi
if [[ "$ANDROID_DEVICE" == true ]]; then
  echo "Android device detected, but adb is not installed." >&2
  echo "Install it with: brew install android-platform-tools" >&2
  echo "Then reconnect the phone and run this script again." >&2
  exit 1
fi

if command -v adb >/dev/null 2>&1 &&
   adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }' | grep -Fxq "$DEVICE"; then
  if ! adb reverse tcp:8080 tcp:8080; then
    echo "Could not create the USB port forward. Check USB debugging and accept the phone's authorization prompt." >&2
    exit 1
  fi
  API_HOST="127.0.0.1"
  echo "USB reverse tunnel: phone:8080 -> Mac:8080"
else
  if [[ -z "$API_HOST" ]]; then
    API_HOST="$(ipconfig getifaddr en0 2>/dev/null || true)"
  fi
  if [[ -z "$API_HOST" ]]; then
    API_HOST="$(ipconfig getifaddr en1 2>/dev/null || true)"
  fi
  if [[ -z "$API_HOST" ]]; then
    echo "Could not find the Mac LAN IP. Run with API_HOST=192.168.x.x." >&2
    exit 1
  fi
fi

cd "$ROOT_DIR"
echo "Flutter device: $DEVICE"
echo "NASA gateway: http://$API_HOST:8080/api"
flutter run -d "$DEVICE" --dart-define=API_BASE_URL=http://$API_HOST:8080/api
