# Objective
Build a minimal inference gateway that:
1. Accepts POST /v1/chat/completions with an OpenAI-style JSON body (messages, optional stream).
2. Forwards the request to a backend (another HTTP server that speaks the same API), or returns a simple echo if no backend is configured.
3. Returns a non-streaming response: one JSON object with choices[0].message.content, usage, and an id (request-id).
4. (Optional) Supports streaming: when stream: true, return Server-Sent Events (SSE) until data: [DONE].

No queue, no scheduler, no device probing—just: request in → call backend (or echo) → response/stream out.

## Must have
1. HTTP server that listens on a configurable port (e.g. env PORT or 8080).
2. Single route: POST /v1/chat/completions.
3. Request body: JSON with messages (list of {role, content}). Extract the last user content as the prompt.
4. Backend: Configurable backend URL (e.g. env BACKEND_URL). If set, POST the same shape to the backend and return its response (or a normalized form). If not set, return a simple echo response (e.g. "Echo: <prompt>").
5. Request-id: Read X-Request-ID (or Request-Id) from the request; if missing, generate a UUID. Include it in the response (e.g. top-level id and/or response header X-Request-ID).
6. Response shape (non-streaming): JSON with at least:
- id (request-id)
- choices: [{ "message": { "role": "assistant", "content": "<reply>" }, "finish_reason": "stop" }]
- usage: { "prompt_tokens", "completion_tokens", "total_tokens" } (can be approximate).

## Optional
- Streaming: If stream: true in the request body and the backend supports streaming, proxy SSE from the backend to the client; otherwise return one SSE chunk with the full reply then data: [DONE].
- GET /healthz or GET /v1/models for health or model list.

# Deliverables
1. Code: A runnable minimal gateway, ideally in Python. Include a short README: how to run, env vars, how to point at a backend or run without one.
2. Test: At least one way to verify it (e.g. curl commands or a small script) that shows:
- Non-streaming POST /v1/chat/completions returns JSON with id and choices[0].message.content.
- Request-id from the client is echoed in the response.
3. Submission: One repo or ZIP per group; link or upload by the deadline. List group members in the README.

# Success Criteria
- Running the gateway and sending POST /v1/chat/completions with valid messages returns 200 and a JSON body with the expected shape and request-id.
- With BACKEND_URL set to a running backend (e.g. llama.cpp or the notebook’s mock), the gateway returns the backend’s reply (or a normalized version).
- Without a backend, the gateway returns an echo (or a clear placeholder) so it runs standalone.
