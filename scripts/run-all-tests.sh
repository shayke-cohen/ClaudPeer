#!/usr/bin/env bash
# Run every automated test in ClaudPeer:
#   1) Swift unit tests (ClaudPeerTests)
#   2) Sidecar: unit + integration + API + E2E (includes live Claude when CLAUDPEER_E2E_LIVE=1)
#   3) Legacy sidecar-api harness against a fresh sidecar on ephemeral ports
#
# Not run here (need separate runners):
#   - tests/appxray/ui-tests.yaml (Argus / AppXray)
#
# Usage (from repo root):
#   ./scripts/run-all-tests.sh
#   Live SDK tests use your normal Claude / Agent SDK auth (e.g. subscription); no API key env var required.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LIVE="${CLAUDPEER_E2E_LIVE:-1}"
export CLAUDPEER_E2E_LIVE="$LIVE"

OVERALL=0

step() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

step "1/3 Swift — xcodebuild test (ClaudPeerTests)"
if xcodebuild test \
  -project ClaudPeer.xcodeproj \
  -scheme ClaudPeer \
  -destination 'platform=macOS' \
  -quiet; then
  echo "OK: Swift tests"
else
  echo "FAIL: Swift tests"
  OVERALL=1
fi

step "2/3 Sidecar — bun test (unit, integration, api, e2e) CLAUDPEER_E2E_LIVE=$LIVE"
DATA_E2E="${TMPDIR:-/tmp}/claudpeer-alltests-e2e-$$"
export CLAUDPEER_DATA_DIR="$DATA_E2E"
if (cd sidecar && bun test test/unit test/integration test/api test/e2e); then
  echo "OK: Sidecar bundled tests"
else
  echo "FAIL: Sidecar bundled tests"
  OVERALL=1
fi

step "3/3 Sidecar — legacy test/sidecar-api.test.ts (ephemeral WS/HTTP ports)"
if ! command -v curl >/dev/null 2>&1; then
  echo "SKIP: curl not found (needed for health check)"
  OVERALL=1
elif ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found (needed to pick free ports)"
  OVERALL=1
else
  pick_port() {
    python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()"
  }
  API_WS_PORT="$(pick_port)"
  API_HTTP_PORT="$(pick_port)"
  while [[ "$API_HTTP_PORT" == "$API_WS_PORT" ]]; do
    API_HTTP_PORT="$(pick_port)"
  done
  echo "Using CLAUDPEER_WS_PORT=$API_WS_PORT CLAUDPEER_HTTP_PORT=$API_HTTP_PORT for sidecar-api harness"

  DATA_API="${TMPDIR:-/tmp}/claudpeer-alltests-api-$$"
  mkdir -p "$DATA_API/blackboard"
  API_PID=""
  cleanup_api() {
    if [[ -n "${API_PID}" ]] && kill -0 "${API_PID}" 2>/dev/null; then
      kill "${API_PID}" 2>/dev/null || true
      wait "${API_PID}" 2>/dev/null || true
    fi
  }
  trap cleanup_api EXIT

  (
    cd sidecar || exit 1
    export CLAUDPEER_WS_PORT="$API_WS_PORT"
    export CLAUDPEER_HTTP_PORT="$API_HTTP_PORT"
    export CLAUDPEER_DATA_DIR="$DATA_API"
    bun run src/index.ts > "${TMPDIR:-/tmp}/claudpeer-api-sidecar-$$.log" 2>&1 &
    echo $!
  ) > "${TMPDIR:-/tmp}/claudpeer-api-pid-$$.txt"
  sleep 0.3
  API_PID="$(cat "${TMPDIR:-/tmp}/claudpeer-api-pid-$$.txt" 2>/dev/null | tr -d '\n')"
  if [[ -z "${API_PID}" ]] || ! kill -0 "${API_PID}" 2>/dev/null; then
    echo "FAIL: could not start sidecar subprocess (see ${TMPDIR:-/tmp}/claudpeer-api-sidecar-$$.log)"
    OVERALL=1
    API_PID=""
  fi

  if [[ -n "${API_PID}" ]]; then
    READY=0
    for _ in $(seq 1 90); do
      if curl -sf "http://127.0.0.1:${API_HTTP_PORT}/health" >/dev/null; then
        READY=1
        break
      fi
      sleep 0.5
    done
    if [[ "$READY" -ne 1 ]]; then
      echo "FAIL: sidecar did not become healthy on :${API_HTTP_PORT} (log: ${TMPDIR:-/tmp}/claudpeer-api-sidecar-$$.log)"
      OVERALL=1
    else
      if (cd sidecar && \
          CLAUDPEER_WS_PORT="$API_WS_PORT" \
          CLAUDPEER_HTTP_PORT="$API_HTTP_PORT" \
          bun run test/sidecar-api.test.ts); then
        echo "OK: sidecar-api harness"
      else
        echo "FAIL: sidecar-api harness"
        OVERALL=1
      fi
    fi
  fi
  cleanup_api
  trap - EXIT
fi

echo ""
if [[ "$OVERALL" -eq 0 ]]; then
  echo "All automated test phases completed successfully."
else
  echo "One or more phases failed (exit 1)."
fi
exit "$OVERALL"
