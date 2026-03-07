---
name: Minimal backend extras
overview: Add the optional backend-list endpoint and per-request latency logging with the smallest possible code change, keeping the implementation centered in the FastAPI entrypoint.
todos:
  - id: add-backends-endpoint
    content: Add `GET /v1/backends` in `src/app.py` using `app.state.config`.
    status: in_progress
  - id: add-latency-logging
    content: Wrap `backend.generate(...)` in `src/app.py` with `perf_counter()` timing and module logging.
    status: pending
  - id: verify-minimal-change
    content: Sanity-check endpoint output, existing chat behavior, and lints for `src/app.py`.
    status: pending
isProject: false
---

# Minimal backend extras

## Goal

Implement the two optional items from `@context/assignment_2/1_task.md` with minimal code:

- `GET /v1/backends` returning configured backend names plus the default backend
- per-request latency logging that records the chosen backend and elapsed time

## Minimal change surface

Change only [src/app.py](/Users/piotr/Desktop/maven-inferencing/inferencing-maven-assignments/src/app.py).

Why this is enough:

- `lifespan()` already loads config into `app.state.config`
- `chat_completions()` already resolves `backend_name` and wraps the single `await backend.generate(...)` call
- `AppConfig` already exposes `default_backend` and `backends`

Relevant existing logic:

```46:94:/Users/piotr/Desktop/maven-inferencing/inferencing-maven-assignments/src/app.py
@app.post("/v1/chat/completions")
async def chat_completions(...):
    req_id = x_request_id or request_id or str(uuid.uuid4())
    ...
    backends: dict[str, Backend] = http_request.app.state.backends
    config: AppConfig = http_request.app.state.config
    backend_name = (
        request.model if request.model in backends else config.default_backend
    )
    ...
    content = await backend.generate(...)
    response = normalize_response(..., backend=backend_name)
```

## Planned edits

1. Add a small `GET /v1/backends` route in [src/app.py](/Users/piotr/Desktop/maven-inferencing/inferencing-maven-assignments/src/app.py).
  Return a compact JSON payload built from `http_request.app.state.config`, for example:
  - `default_backend`
  - `backends` as the list of configured backend names
2. Add lightweight timing/logging in `chat_completions()` in [src/app.py](/Users/piotr/Desktop/maven-inferencing/inferencing-maven-assignments/src/app.py).
  Use:
  - `time.perf_counter()` for elapsed time
  - Python `logging` with a module logger
3. Log one line per request around the existing backend call.
  Include at least:
  - `request_id`
  - `backend_name`
  - elapsed milliseconds
  - whether the call succeeded or failed
4. Keep response and config models unchanged unless a lint/type issue makes a tiny schema helper worthwhile.
  The current models already support the request flow, and the new endpoint can return a plain dict without adding more Pydantic models.

## Verification

- Call `GET /v1/backends` and confirm it returns configured names from [config.yaml](/Users/piotr/Desktop/maven-inferencing/inferencing-maven-assignments/config.yaml) plus `default_backend`.
- Call `POST /v1/chat/completions` and confirm behavior is unchanged.
- Check application logs for backend name and latency on both success and backend error paths.
- Run lint diagnostics on the edited file only.

## Notes

This plan intentionally avoids touching [src/core/models.py](/Users/piotr/Desktop/maven-inferencing/inferencing-maven-assignments/src/core/models.py), [src/services/gateway.py](/Users/piotr/Desktop/maven-inferencing/inferencing-maven-assignments/src/services/gateway.py), or backend adapter code because the existing app entrypoint already has everything needed for both requested additions.