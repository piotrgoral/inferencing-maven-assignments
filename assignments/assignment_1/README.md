# Assignment 1: Minimal Inference Gateway

A minimal FastAPI-based inference gateway that implements OpenAI-style chat completions API.

## Features

- POST `/v1/chat/completions` endpoint accepting OpenAI-style JSON requests
- Configurable backend forwarding (via `BACKEND_URL` environment variable)
- Echo mode when no backend is configured
- Request ID handling (reads `X-Request-ID` or `Request-Id` header, generates UUID if missing)
- OpenAI-compatible response format with `id`, `choices`, and `usage` fields
- Optional `/healthz` endpoint for health checks

## Requirements

- Python 3.13+
- Poetry (for dependency management)

## Installation

Install dependencies:

```bash
poetry install
```

## Configuration

Environment variables:

- `PORT` (default: `8080`) - Port to listen on
- `BACKEND_URL` (optional) - Backend URL to forward requests to. If not set, the gateway runs in echo mode.

## Running

### Echo Mode (no backend)

```bash
poetry run python assignments/assignment_1/app.py
```

Or with custom port:

```bash
PORT=3000 poetry run python assignments/assignment_1/app.py
```

### With Backend

```bash
BACKEND_URL=http://localhost:8000 poetry run python assignments/assignment_1/app.py
```

Or using uvicorn directly:

```bash
poetry run uvicorn assignments.assignment_1.app:app --host 0.0.0.0 --port 8080
```

## Usage Examples

### Basic Request (Echo Mode)

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Hello, world!"}
    ]
  }'
```

Expected response:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "object": "chat.completion",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Echo: Hello, world!"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 2,
    "completion_tokens": 3,
    "total_tokens": 5
  }
}
```

### With Custom Request ID

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: my-custom-id-123" \
  -d '{
    "messages": [
      {"role": "user", "content": "Test message"}
    ]
  }'
```

The response will include `"id": "my-custom-id-123"` and the `X-Request-ID` header will be echoed back.

### Health Check

```bash
curl http://localhost:8080/healthz
```

Returns: `{"status": "ok"}`

## Testing

Run the test script:

```bash
bash assignments/assignment_1/test.sh
```

This will test:
1. Echo mode functionality
2. Request ID handling

