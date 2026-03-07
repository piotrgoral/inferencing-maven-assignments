# Assignment 2: Config-Driven Gateway

FastAPI gateway extended from Assignment 1 to support multiple backends behind a single `generate()` interface, routed by the request `model` field and configured via YAML.

## Features (must-have scope)

- POST `/v1/chat/completions` (non-streaming for this assignment)
- Config-driven backend routing by `model` with default fallback
- Two backends out of the box:
  - `local` echo backend
  - `remote` HTTP backend (points to the included mock by default)
- Response metadata includes `backend` to show which backend handled the request
- Request ID handling (reads `X-Request-ID` or `Request-Id`, generates UUID if missing)
- `/healthz` endpoint

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
- `CONFIG_PATH` (default: `config.yaml` in repo root) - Path to YAML config
- `BACKEND_TIMEOUT` (default: `30.0`) - Timeout for remote HTTP backend

## Running

### Start mock remote backend

```bash
poetry run python src/mock_backend.py
```

Listens on port `8081` by default (`MOCK_PORT` env to override).

### Run the gateway

```bash
poetry run python src/app.py
```

or with explicit config/ports:

```bash
CONFIG_PATH=./config.yaml PORT=8080 poetry run python src/app.py
```

### Config (YAML)

`config.yaml` (root) defines the default backend and named backends:

```yaml
default_backend: local

backends:
  local:
    type: local
  remote:
    type: remote
    url: http://127.0.0.1:8081
  modal:
    type: modal
    url: https://piotrek-grl--relay-llama-server-web.modal.run
  modal_vllm:
    type: vllm
    url: https://YOUR_MODAL_VLLM_URL
```

Types other than `local` are treated as HTTP backends using `url`.

## Usage Examples

### Basic Request (Echo/backend shown)

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [{"role": "user", "content": "Hello, world!"}]
  }'
```

Expected response:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "object": "chat.completion",
  "backend": "local",
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
    "messages": [{"role": "user", "content": "Test message"}]
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
bash src/test.sh
```

The script automatically starts the mock backend, starts the gateway with `config.yaml`, and verifies:
- `model: local` → echo backend and `backend: "local"`
- `model: remote` → mock backend and `backend: "remote"`
- missing `model` → default backend fallback

> Streaming is out of scope for Assignment 2; requests with `stream: true` return 400.

