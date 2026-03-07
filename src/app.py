from __future__ import annotations

import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional

import httpx
from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from src.adapters.backend_registry import build_backend_registry
from src.adapters.backends import Backend
from src.core.config import default_config_path, load_config
from src.core.logger import configure_logging
from src.core.models import AppConfig, ChatRequest
from src.services.gateway import extract_last_user_message, normalize_response

configure_logging()
logger = logging.getLogger(__name__)


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

logger = logging.getLogger(__name__)

PORT = int(os.getenv("PORT", "8080"))


@app.get("/healthz")
async def healthz():
    """Health check endpoint."""
    return {"status": "ok"}


@app.get("/v1/backends")
async def list_backends(http_request: Request):
    """Return configured backends and the default backend name."""
    config: AppConfig = http_request.app.state.config
    return {
        "default_backend": config.default_backend,
        "backends": list(config.backends.keys()),
    }


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

    start_time = time.perf_counter()
    try:
        content = await backend.generate(
            prompt=prompt, request=request, request_id=req_id
        )
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        logger.info(
            f"[chat_completions] success: req_id={req_id} "
            f"backend={backend_name} latency_ms={elapsed_ms:.2f}"
        )
    except Exception as exc:
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        logger.exception(
            f"[chat_completions] backend error: req_id={req_id} "
            f"backend={backend_name} latency_ms={elapsed_ms:.2f}"
        )
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
