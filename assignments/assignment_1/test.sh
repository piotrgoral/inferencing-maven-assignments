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
echo "Tests completed!"
