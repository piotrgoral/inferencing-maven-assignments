#!/bin/bash

# Assignment 2 test script: validates routing by model, backend metadata, and default fallback.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-$ROOT_DIR/config.yaml}"
GATEWAY_PORT="${GATEWAY_PORT:-8080}"
MOCK_PORT="${MOCK_PORT:-8081}"
GATEWAY_URL="http://localhost:$GATEWAY_PORT"
MOCK_URL="http://localhost:$MOCK_PORT"

GATEWAY_PID=""
MOCK_PID=""

cleanup() {
  echo "Cleaning up..."
  [ -n "$GATEWAY_PID" ] && kill "$GATEWAY_PID" 2>/dev/null || true
  [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
  wait "$GATEWAY_PID" "$MOCK_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

echo "Starting mock backend on $MOCK_URL"
cd "$ROOT_DIR"
PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}" poetry run python src/dev/mock_backend.py > /tmp/mock_backend.log 2>&1 &
MOCK_PID=$!
sleep 1

echo "Starting gateway on $GATEWAY_URL using config $CONFIG_PATH"
PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}" CONFIG_PATH="$CONFIG_PATH" PORT="$GATEWAY_PORT" poetry run python src/app.py > /tmp/gateway.log 2>&1 &
GATEWAY_PID=$!
sleep 2

echo "=== Test 1: model=local routes to echo backend ==="
RESP_LOCAL=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [{"role": "user", "content": "ping local"}]
  }')
echo "$RESP_LOCAL" | python3 -m json.tool
python3 - "$RESP_LOCAL" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data.get("backend") == "local", "backend should be local"
assert data["choices"][0]["message"]["content"] == "Echo: ping local", "echo content mismatch"
PY
echo "✔ backend=local present and echo content ok"

echo "=== Test 2: model=remote routes to mock backend ==="
RESP_REMOTE=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "remote",
    "messages": [{"role": "user", "content": "ping remote"}]
  }')
echo "$RESP_REMOTE" | python3 -m json.tool
python3 - "$RESP_REMOTE" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data.get("backend") == "remote", "backend should be remote"
assert data["choices"][0]["message"]["content"] == "Mock", "remote content should be Mock"
PY
echo "✔ backend=remote present and mock content ok"

echo "=== Test 3: missing model falls back to default backend ==="
RESP_DEFAULT=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "ping default"}]
  }')
echo "$RESP_DEFAULT" | python3 -m json.tool
python3 - "$RESP_DEFAULT" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data.get("backend") == "local", "default backend should be local"
PY
echo "✔ fallback to default backend"

echo "All tests passed."
