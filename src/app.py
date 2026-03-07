from __future__ import annotations

import os
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import httpx
from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from backends import Backend, EchoBackend, RemoteHttpBackend
from config_loader import load_config
from gateway_logic import extract_last_user_message, normalize_response
from models import AppConfig, ChatRequest


def _default_config_path() -> str:
    # project root relative to this file
    return str(Path(__file__).resolve().parent.parent / "config.yaml")


def build_backend_registry(
    config: AppConfig, client: httpx.AsyncClient, timeout: float
) -> dict[str, Backend]:
    registry: dict[str, Backend] = {}
    for name, backend_cfg in config.backends.items():
        if backend_cfg.type == "local":
            registry[name] = EchoBackend()
        else:
            if not backend_cfg.url:
                raise ValueError(f"Backend '{name}' requires a url")
            registry[name] = RemoteHttpBackend(
                url=backend_cfg.url,
                client=client,
                timeout=timeout,
            )
    if config.default_backend not in registry:
        raise ValueError(
            f"Configured default_backend '{config.default_backend}' is not defined"
        )
    return registry


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan: create and cleanup httpx client and backend registry."""
    config_path = os.getenv("CONFIG_PATH", _default_config_path())
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

    # Get request ID from headers or generate UUID
    req_id = x_request_id or request_id or str(uuid.uuid4())

    prompt = extract_last_user_message(request.messages)

    backends: dict[str, Backend] = http_request.app.state.backends
    config: AppConfig = http_request.app.state.config
    backend_name = request.model if request.model in backends else config.default_backend

    backend = backends.get(backend_name)
    if backend is None:
        return JSONResponse(
            status_code=400,
            content={"error": f"Backend '{backend_name}' is not configured."},
            headers={"X-Request-ID": req_id},
        )

    try:
        content = await backend.generate(prompt=prompt, request=request, request_id=req_id)
    except Exception as exc:
        return JSONResponse(
            status_code=502,
            content={"error": f"Backend error: {exc}"},
            headers={"X-Request-ID": req_id},
        )

    response = normalize_response(content, req_id, prompt, backend_name)

    return JSONResponse(content=response.model_dump(), headers={"X-Request-ID": req_id})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
