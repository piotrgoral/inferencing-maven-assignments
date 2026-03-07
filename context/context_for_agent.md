What This Repository Is
-----------------------
A lightweight chat gateway that presents a single OpenAI-style `/v1/chat/completions` API while routing requests to interchangeable backends. It standardizes how clients talk to different model providers and keeps responses consistent.

Why It Exists
-------------
The project demonstrates how to separate client-facing behavior from provider choice. 
- Assignment 1 introduced the minimal single-backend gateway; 
- Assignment 2 evolved it into a config-driven router with multiple named backends and a clean backend interface. The goal is easy backend swaps without changing request handling.

Key Features (User-Facing)
--------------------------
- One primary chat endpoint; non-streaming responses by design for this scope.
- Backend selection via the request `model` field with a safe default fallback.
- Out-of-the-box local/echo backend plus remote HTTP backend support.
- Responses include which backend handled the request for traceability.
- Request IDs are accepted or generated and echoed back for observability.
- `GET /v1/backends` returns configured backend names and the default backend.
- Per-request latency logging: each chat call logs backend name and elapsed ms.
- Simple health check endpoint.

How Requests Flow
-----------------
Clients POST chat messages to the gateway. The gateway picks a backend based on the requested model (or the default), forwards the prompt through a common backend interface, and returns a normalized OpenAI-style response that names the backend and includes usage-style metadata. If streaming is requested, the gateway rejects it because streaming is out of scope for this assignment.

Architecture Overview
---------------------
- API entrypoint: FastAPI app that owns lifecycle, config loading, and public routes (`/v1/chat/completions`, `/healthz`).
- Configuration layer: loads YAML config and validates it into app settings.
- Contracts: shared request/response and backend config models define the common shapes the app expects and returns.
- Backend abstraction: a simple `generate(prompt, request, request_id)` interface with pluggable implementations for local echo and remote HTTP providers.
- Backend registry: builds the map of named backends from config and enforces the default selection.
- Gateway helpers: extract the last user message as the prompt and normalize backend output into the public response format with usage-style fields.
- Dev/test support: mock remote backend to exercise routing without an external provider.

Main Building Blocks (by role)
------------------------------
- `src/app.py`: public API surface, lifecycle setup, request routing to the chosen backend.
- `src/core/config.py`: reads and validates YAML configuration.
- `src/core/logger.py`: basic logging setup (console, INFO) when none exists.
- `src/core/models.py`: defines the request/response and config data shapes used across the app.
- `src/adapters/backends.py`: backend interface plus local/echo and remote HTTP implementations.
- `src/adapters/backend_registry.py`: assembles the configured backends and validates the default.
- `src/services/gateway.py`: prompt extraction, response normalization, and supporting helpers.
- `src/dev/mock_backend.py`: mock provider for local development and tests.

Current Scope and Boundaries
----------------------------
- Non-streaming responses only; streaming requests are explicitly rejected at the gateway.
- No load balancing, retries, health probing of backends, or queueing/orchestration—those are intentionally out of scope for this assignment.
- Configuration drives backend definitions; adding a backend should be mostly a config change plus an implementation of the shared interface.

What an Agent Should Keep in Mind
---------------------------------
- The gateway’s value is stable client behavior while backends change behind the scenes.
- Provenance matters: responses name the backend and carry request IDs for tracing.
- Keep explanations high-level; avoid code-level mechanics when sharing context.
