#!/bin/bash

# Test script for Assignment 1 Gateway
# Make sure the gateway is running on localhost:8080

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "Testing Assignment 1 Gateway..."
echo "Base URL: $BASE_URL"
echo ""

# Test 1: Echo mode - basic request
echo "Test 1: Echo mode (no backend)"
echo "Sending POST /v1/chat/completions..."
RESPONSE=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Hello, world!"}
    ]
  }')

echo "Response:"
echo "$RESPONSE" | python3 -m json.tool
echo ""

# Check if response has required fields
if echo "$RESPONSE" | grep -q '"id"' && echo "$RESPONSE" | grep -q '"choices"' && echo "$RESPONSE" | grep -q '"usage"'; then
  echo "✓ Test 1 PASSED: Response has required fields (id, choices, usage)"
else
  echo "✗ Test 1 FAILED: Missing required fields"
fi

if echo "$RESPONSE" | grep -q '"Echo: Hello, world!"'; then
  echo "✓ Test 1 PASSED: Echo content is correct"
else
  echo "✗ Test 1 FAILED: Echo content mismatch"
fi

echo ""

# Test 2: Request ID handling
echo "Test 2: Request ID handling"
CUSTOM_ID="test-request-id-$(date +%s)"
echo "Sending request with X-Request-ID: $CUSTOM_ID"
RESPONSE2=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: $CUSTOM_ID" \
  -d '{
    "messages": [
      {"role": "user", "content": "Test message"}
    ]
  }')

echo "Response:"
echo "$RESPONSE2" | python3 -m json.tool
echo ""

# Check if request ID is echoed back
if echo "$RESPONSE2" | grep -q "\"$CUSTOM_ID\""; then
  echo "✓ Test 2 PASSED: Request ID is echoed in response"
else
  echo "✗ Test 2 FAILED: Request ID not found in response"
fi

# Check header
HEADER_ID=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: $CUSTOM_ID" \
  -d '{"messages": [{"role": "user", "content": "test"}]}' \
  -D - | grep -i "X-Request-ID" | cut -d' ' -f2 | tr -d '\r\n')

if [ "$HEADER_ID" = "$CUSTOM_ID" ]; then
  echo "✓ Test 2 PASSED: Request ID is echoed in X-Request-ID header"
else
  echo "✗ Test 2 FAILED: Request ID mismatch in header (got: $HEADER_ID, expected: $CUSTOM_ID)"
fi

echo ""

# Test 3: Backend forwarding with mock backend
echo "Test 3: Backend forwarding with mock backend"
MOCK_PORT="${MOCK_PORT:-8081}"
GATEWAY_PORT="${GATEWAY_PORT:-8080}"
MOCK_URL="http://localhost:$MOCK_PORT"
GATEWAY_URL="http://localhost:$GATEWAY_PORT"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up background processes..."
    [ -n "$MOCK_PID" ] && kill $MOCK_PID 2>/dev/null
    [ -n "$GATEWAY_PID" ] && kill $GATEWAY_PID 2>/dev/null
    wait $MOCK_PID 2>/dev/null
    wait $GATEWAY_PID 2>/dev/null
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Start mock backend
echo "Starting mock backend on port $MOCK_PORT..."
cd "$(dirname "$0")"
poetry run python mock_backend.py > /tmp/mock_backend.log 2>&1 &
MOCK_PID=$!

# Start gateway with BACKEND_URL
echo "Starting gateway with BACKEND_URL=$MOCK_URL on port $GATEWAY_PORT..."
BACKEND_URL=$MOCK_URL PORT=$GATEWAY_PORT poetry run python app.py > /tmp/gateway.log 2>&1 &
GATEWAY_PID=$!

# Wait for servers to start
echo "Waiting for servers to start..."
sleep 3

# Check if servers are running
if ! kill -0 $MOCK_PID 2>/dev/null; then
    echo "✗ Test 3 FAILED: Mock backend failed to start"
    cat /tmp/mock_backend.log
    exit 1
fi

if ! kill -0 $GATEWAY_PID 2>/dev/null; then
    echo "✗ Test 3 FAILED: Gateway failed to start"
    cat /tmp/gateway.log
    exit 1
fi

# Test health endpoints
if ! curl -s "$MOCK_URL/healthz" > /dev/null; then
    echo "✗ Test 3 FAILED: Mock backend health check failed"
    exit 1
fi

if ! curl -s "$GATEWAY_URL/healthz" > /dev/null; then
    echo "✗ Test 3 FAILED: Gateway health check failed"
    exit 1
fi

# Send request to gateway
echo "Sending POST /v1/chat/completions to gateway..."
RESPONSE3=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Test with backend"}
    ]
  }')

echo "Response:"
echo "$RESPONSE3" | python3 -m json.tool
echo ""

# Check if response has required fields
if echo "$RESPONSE3" | grep -q '"id"' && echo "$RESPONSE3" | grep -q '"choices"' && echo "$RESPONSE3" | grep -q '"usage"'; then
    echo "✓ Test 3 PASSED: Response has required fields (id, choices, usage)"
else
    echo "✗ Test 3 FAILED: Missing required fields"
    exit 1
fi

# Check if content is "Mock"
if echo "$RESPONSE3" | grep -q '"Mock"'; then
    echo "✓ Test 3 PASSED: Backend response content is 'Mock'"
else
    echo "✗ Test 3 FAILED: Expected 'Mock' but got different content"
    exit 1
fi

# Cleanup
cleanup
trap - EXIT INT TERM

echo ""
echo "Tests completed!"
