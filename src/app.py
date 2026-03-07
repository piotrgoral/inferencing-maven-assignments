from __future__ import annotations

import os
import uuid
from contextlib import asynccontextmanager
from typing import Optional

import httpx
from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from adapters.backend_registry import build_backend_registry
from adapters.backends import Backend
from core.config import default_config_path, load_config
from core.models import AppConfig, ChatRequest
from services.gateway import extract_last_user_message, normalize_response


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan: create and cleanup httpx client and backend registry."""
    config_path = os.getenv("CONFIG_PATH", default_config_path())
    backend_timeout = float(os.getenv("BACKEND_TIMEOUT", "30.0"))
    app.state.config = load_config(config_path)
    app.state.client = httpx.AsyncClient()
    app.state.backends = build_backend_registry(
        app.state.config, app.state.client, backend_timeout
    )
    app.state.backend_timeout = backend_timeout
    yield
    await app.state.client.aclose()


app = FastAPI(lifespan=lifespan)


PORT = int(os.getenv("PORT", "8080"))


@app.get("/healthz")
async def healthz():
    """Health check endpoint."""
    return {"status": "ok"}


@app.post("/v1/chat/completions")
async def chat_completions(
    request: ChatRequest,
    http_request: Request,
    x_request_id: Optional[str] = Header(None, alias="X-Request-ID"),
    request_id: Optional[str] = Header(None, alias="Request-Id"),
):
    """
    Handle chat completion requests through a backend registry.
    Streaming is out of scope for this assignment.
    """
    if request.stream:
        return JSONResponse(
            status_code=400,
            content={"error": "Streaming is out of scope for this assignment."},
        )

    req_id = x_request_id or request_id or str(uuid.uuid4())
    prompt = extract_last_user_message(request.messages)

    backends: dict[str, Backend] = http_request.app.state.backends
    config: AppConfig = http_request.app.state.config
    backend_name = (
        request.model if request.model in backends else config.default_backend
    )

    backend = backends.get(backend_name)
    if backend is None:
        return JSONResponse(
            status_code=400,
            content={"error": f"Backend '{backend_name}' is not configured."},
            headers={"X-Request-ID": req_id},
        )

    try:
        content = await backend.generate(
            prompt=prompt, request=request, request_id=req_id
        )
    except Exception as exc:
        return JSONResponse(
            status_code=502,
            content={"error": f"Backend error: {exc}"},
            headers={"X-Request-ID": req_id},
        )

    response = normalize_response(
        content=content, request_id=req_id, prompt=prompt, backend=backend_name
    )
    return JSONResponse(content=response.model_dump(), headers={"X-Request-ID": req_id})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
