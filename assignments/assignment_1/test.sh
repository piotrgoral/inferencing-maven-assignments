#!/bin/bash

# Test script for Assignment 1 Gateway
# Starts gateway instances as needed for each test

BASE_URL="${BASE_URL:-http://localhost:8080}"

# Initialize PID variables
ECHO_GATEWAY_PID=""
MOCK_PID=""
GATEWAY_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up background processes..."
    [ -n "$ECHO_GATEWAY_PID" ] && kill $ECHO_GATEWAY_PID 2>/dev/null
    [ -n "$MOCK_PID" ] && kill $MOCK_PID 2>/dev/null
    [ -n "$GATEWAY_PID" ] && kill $GATEWAY_PID 2>/dev/null
    wait $ECHO_GATEWAY_PID $MOCK_PID $GATEWAY_PID 2>/dev/null
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

echo "Testing Assignment 1 Gateway..."
echo "Base URL: $BASE_URL"
echo ""

# Start gateway in echo mode for Tests 1 and 2
echo "Starting gateway in echo mode on port 8080..."
cd "$(dirname "$0")"
PORT=8080 poetry run python app.py > /tmp/echo_gateway.log 2>&1 &
ECHO_GATEWAY_PID=$!
sleep 2   # wait for uvicorn to be ready

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

# Stop echo-mode gateway before starting Test 3
echo "Stopping echo-mode gateway..."
kill $ECHO_GATEWAY_PID 2>/dev/null
wait $ECHO_GATEWAY_PID 2>/dev/null
ECHO_GATEWAY_PID=""
sleep 1   # ensure port 8080 is free before Test 3 restarts it

# Test 3: Backend forwarding with mock backend
echo "Test 3: Backend forwarding with mock backend"
MOCK_PORT="${MOCK_PORT:-8081}"
GATEWAY_PORT="${GATEWAY_PORT:-8080}"
MOCK_URL="http://localhost:$MOCK_PORT"
GATEWAY_URL="http://localhost:$GATEWAY_PORT"

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

echo ""

# Test 4: Streaming in echo mode (no backend)
echo "Test 4: Streaming in echo mode (no backend)"
echo "Stopping gateway with backend..."
kill $GATEWAY_PID 2>/dev/null
wait $GATEWAY_PID 2>/dev/null
GATEWAY_PID=""
sleep 1

echo "Starting gateway in echo mode on port $GATEWAY_PORT..."
cd "$(dirname "$0")"
PORT=$GATEWAY_PORT poetry run python app.py > /tmp/echo_gateway_stream.log 2>&1 &
ECHO_GATEWAY_PID=$!
sleep 2

echo "Sending streaming POST /v1/chat/completions..."
STREAM_RESPONSE=$(curl -s -N -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: stream-test-echo" \
  -d '{
    "messages": [
      {"role": "user", "content": "Hi"}
    ],
    "stream": true
  }')

# Check Content-Type header
CONTENT_TYPE=$(curl -s -N -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: stream-test-echo-header" \
  -d '{"messages": [{"role": "user", "content": "Hi"}], "stream": true}' \
  -D - -o /dev/null | grep -i "content-type" | cut -d' ' -f2 | tr -d '\r\n')

if echo "$CONTENT_TYPE" | grep -qi "text/event-stream"; then
    echo "✓ Test 4 PASSED: Content-Type is 'text/event-stream'"
else
    echo "✗ Test 4 FAILED: Content-Type should be 'text/event-stream', got: $CONTENT_TYPE"
fi

echo "Streaming response received:"
echo "$STREAM_RESPONSE"
echo ""

# Check for SSE format
if echo "$STREAM_RESPONSE" | grep -q "^data: "; then
    echo "✓ Test 4 PASSED: Response is in SSE format (starts with 'data: ')"
else
    echo "✗ Test 4 FAILED: Response is not in SSE format"
fi

# Check for request ID in chunks
if echo "$STREAM_RESPONSE" | grep -q '"stream-test-echo"'; then
    echo "✓ Test 4 PASSED: Request ID is present in SSE chunks"
else
    echo "✗ Test 4 FAILED: Request ID not found in SSE chunks"
fi

# Check for [DONE]
if echo "$STREAM_RESPONSE" | grep -q "data: \[DONE\]"; then
    echo "✓ Test 4 PASSED: Stream ends with 'data: [DONE]'"
else
    echo "✗ Test 4 FAILED: Stream does not end with 'data: [DONE]'"
fi

# Count data chunks (should have multiple chunks for "Echo: Hi" + [DONE])
CHUNK_COUNT=$(echo "$STREAM_RESPONSE" | grep -c "^data: " || echo "0")
if [ "$CHUNK_COUNT" -ge 2 ]; then
    echo "✓ Test 4 PASSED: Multiple SSE chunks received ($CHUNK_COUNT chunks)"
else
    echo "✗ Test 4 FAILED: Expected multiple chunks, got $CHUNK_COUNT"
fi

# Check for echo content (extract content from chunks and reconstruct)
EXTRACTED_CONTENT=$(echo "$STREAM_RESPONSE" | grep -o '"content": "[^"]*"' | sed 's/"content": "//g' | sed 's/"//g' | tr -d '\n')
if echo "$EXTRACTED_CONTENT" | grep -q "Echo: Hi"; then
    echo "✓ Test 4 PASSED: Echo content found in stream"
else
    echo "✗ Test 4 FAILED: Echo content not found in stream (extracted: $EXTRACTED_CONTENT)"
fi

echo ""

# Test 5: Streaming with mock backend
echo "Test 5: Streaming with mock backend"
echo "Stopping echo-mode gateway..."
kill $ECHO_GATEWAY_PID 2>/dev/null
wait $ECHO_GATEWAY_PID 2>/dev/null
ECHO_GATEWAY_PID=""
sleep 1

echo "Starting gateway with BACKEND_URL=$MOCK_URL on port $GATEWAY_PORT..."
BACKEND_URL=$MOCK_URL PORT=$GATEWAY_PORT poetry run python app.py > /tmp/gateway_stream.log 2>&1 &
GATEWAY_PID=$!
sleep 2

if ! kill -0 $GATEWAY_PID 2>/dev/null; then
    echo "✗ Test 5 FAILED: Gateway failed to start"
    cat /tmp/gateway_stream.log
    exit 1
fi

echo "Sending streaming POST /v1/chat/completions to gateway..."
STREAM_RESPONSE2=$(curl -s -N -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: stream-test-backend" \
  -d '{
    "messages": [
      {"role": "user", "content": "Test streaming"}
    ],
    "stream": true
  }')

# Check Content-Type header
CONTENT_TYPE2=$(curl -s -N -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: stream-test-backend-header" \
  -d '{"messages": [{"role": "user", "content": "Test"}], "stream": true}' \
  -D - -o /dev/null | grep -i "content-type" | cut -d' ' -f2 | tr -d '\r\n')

if echo "$CONTENT_TYPE2" | grep -qi "text/event-stream"; then
    echo "✓ Test 5 PASSED: Content-Type is 'text/event-stream'"
else
    echo "✗ Test 5 FAILED: Content-Type should be 'text/event-stream', got: $CONTENT_TYPE2"
fi

echo "Streaming response received:"
echo "$STREAM_RESPONSE2"
echo ""

# Check for SSE format
if echo "$STREAM_RESPONSE2" | grep -q "^data: "; then
    echo "✓ Test 5 PASSED: Response is in SSE format (starts with 'data: ')"
else
    echo "✗ Test 5 FAILED: Response is not in SSE format"
fi

# Check for request ID in chunks
if echo "$STREAM_RESPONSE2" | grep -q '"stream-test-backend"'; then
    echo "✓ Test 5 PASSED: Request ID is present in SSE chunks"
else
    echo "✗ Test 5 FAILED: Request ID not found in SSE chunks"
fi

# Check for [DONE]
if echo "$STREAM_RESPONSE2" | grep -q "data: \[DONE\]"; then
    echo "✓ Test 5 PASSED: Stream ends with 'data: [DONE]'"
else
    echo "✗ Test 5 FAILED: Stream does not end with 'data: [DONE]'"
fi

# Count data chunks (should have multiple chunks for "Mock" + [DONE])
CHUNK_COUNT2=$(echo "$STREAM_RESPONSE2" | grep -c "^data: " || echo "0")
if [ "$CHUNK_COUNT2" -ge 2 ]; then
    echo "✓ Test 5 PASSED: Multiple SSE chunks received ($CHUNK_COUNT2 chunks)"
else
    echo "✗ Test 5 FAILED: Expected multiple chunks, got $CHUNK_COUNT2"
fi

# Check for "Mock" content (extract content from chunks and reconstruct)
EXTRACTED_CONTENT2=$(echo "$STREAM_RESPONSE2" | grep -o '"content": "[^"]*"' | sed 's/"content": "//g' | sed 's/"//g' | tr -d '\n')
if echo "$EXTRACTED_CONTENT2" | grep -q "Mock"; then
    echo "✓ Test 5 PASSED: Backend content 'Mock' found in stream"
else
    echo "✗ Test 5 FAILED: Expected 'Mock' content not found in stream (extracted: $EXTRACTED_CONTENT2)"
fi

# Verify character-by-character streaming (should have separate chunks for M, o, c, k)
# Fix grep pattern to include space after colon: "content": "M" not "content":"M"
MOCK_CHUNKS=$(echo "$STREAM_RESPONSE2" | grep -o '"content": "[^"]*"' | grep -c "content" || echo "0")
if [ "$MOCK_CHUNKS" -ge 4 ]; then
    echo "✓ Test 5 PASSED: Character-by-character streaming detected ($MOCK_CHUNKS content chunks)"
else
    echo "⚠ Test 5 WARNING: Expected character-by-character chunks, got $MOCK_CHUNKS content chunks"
fi

echo ""
echo "Tests completed!"
