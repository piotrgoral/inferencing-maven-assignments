Extend your Class 1 gateway with backend abstraction, config-driven routing, and a remote backend

## Overview

In Class 1 (assignment_1) you built a minimal gateway with a single backend or echo. Today you saw how RelayServe extends that pattern to support multiple swappable backends routed by model name. Your homework is to apply that same pattern to your own gateway from Class 1.

You are not reimplementing RelayServe. You are evolving your own code using the design principles from today.

## Objective

Extend your Class 1 gateway to:

    1. Support at least two backends i.e. one local (or echo) and one remote — selectable per request

    2. Define a clean backend interface so your routing logic doesn't branch on backend type

    3. Load backend configuration from a file or environment variables — not hardcoded

    4. Route requests by the model field in the request body, with a fallback to a default backend

    5. Report which backend handled each request in the response metadata

## Requirements

### Must have:
- Backend interface: define a common interface or base class with a single generate(prompt) method. Both backends must implement it. Your router must call only generate() - no if/else on backend type inside the handler.
- Two backends:
    - Local / Echo backend: your Class 1 echo or local llama.cpp connection, now wrapped behind the interface
    - Remote backend: an HTTP backend reachable via a URL (can be a Mock server, a classmate's gateway, a Modal deployment, or any HTTP endpoint that returns the right shape). Implement this as a second class that POSTs to the configured URL.
- Config-driven: backend URLs and the default backend name must come from a config file (YAML, JSON, or TOML) or environment variables. They should not be hardcoded strings in your routing logic
- Routing: read the model field from the request body. If it matches a configured backend name, use that backend. If it is missing or unrecognized, fall back to the default backend.
- Backend metadata in response: add a backend field to your response (either top-level or inside a relay or meta object) that tells the client which backend handled the request

Response shape (non-streaming) - same as Class 1 plus metadata:
```json
{
  "id": "<request-id>",
  "backend": "<backend-name>",
  "choices": [{
    "message": { "role": "assistant", "content": "<reply>" },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```


## Optional stretch
- Add a third backend (e.g. a second remote URL serving a different backend - vllm)
- Add GET /v1/backends that returns the list of configured backends and which is default
- Add per-request latency logging: log which backend was used and how long it took
- If the primary backend fails, fall back to the echo backend and note it in the response metadata

# Out of scope — do not implement (Class 3)
- Load balancing across multiple replicas of the same backend
- Queue, scheduler, or worker threads
- Health checks or retries
- Streaming

# Deliverables
1. Code: Your extended gateway — any language/framework. Must be runnable. Include a short README covering: how to run, what env vars or config file is needed, how to point at a remote backend, and how to run in echo-only mode without any backend.
2. Config file: A sample config.yaml (or equivalent) showing at least two backend entries and a default backend name.
3. Tests: curl commands or a small script that demonstrates:
    - Sending "model": "local" routes to the local/echo backend and response includes "backend": "local"
    - Sending "model": "remote" routes to the remote backend and response includes "backend": "remote"
    - Omitting the model field falls back to the default backend
4. Submission: One repo or ZIP per group. List group members in the README. Submit before next Friday 12 am, anywhere on earth.

# Success criteria
- Sending POST /v1/chat/completions with "model": "local" returns 200 with the echo or local reply and "backend": "local" in the response
- Sending the same request with "model": "remote" returns the remote backend's reply and "backend": "remote" in the response
- Omitting model uses the default backend without error
- Adding a third backend requires only a config change — no edits to your routing or handler code
- The backend interface is clearly defined and both backends implement it — a reviewer should be able to add a new backend by writing one class and one config entry

# What I am looking for

The core of this homework is the interface and routing design, not the HTTP plumbing. A correct submission where the handler calls backend.generate() with no type-checking is better than one with two working backends but branching logic in the handler. Show me that you understood today's lesson: the gateway should not care what the backend is.