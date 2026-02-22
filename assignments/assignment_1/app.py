import os
import uuid
from contextlib import asynccontextmanager
from typing import Optional

import httpx
from fastapi import FastAPI, Request, Header
from fastapi.responses import JSONResponse, StreamingResponse

from models import ChatRequest
from gateway_logic import (
    extract_last_user_message,
    normalize_response,
    fetch_from_backend,
    stream_from_backend,
    echo_stream,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan: create and cleanup httpx client."""
    app.state.client = httpx.AsyncClient()
    yield
    await app.state.client.aclose()


app = FastAPI(lifespan=lifespan)


PORT = int(os.getenv("PORT", "8080"))
BACKEND_URL = os.getenv("BACKEND_URL")
BACKEND_TIMEOUT = float(os.getenv("BACKEND_TIMEOUT", "30.0"))


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
    Handle chat completion requests.
    Forwards to backend if BACKEND_URL is set, otherwise returns echo response.
    """
    # Get request ID from headers or generate UUID
    req_id = x_request_id or request_id or str(uuid.uuid4())

    # Extract last user message as prompt
    prompt = extract_last_user_message(request.messages)

    # Handle streaming requests
    if request.stream:

        async def event_generator():
            if BACKEND_URL:
                async for chunk in stream_from_backend(
                    client=http_request.app.state.client,
                    backend_url=BACKEND_URL,
                    request=request,
                    req_id=req_id,
                    timeout=BACKEND_TIMEOUT,
                ):
                    yield chunk
            else:
                async for chunk in echo_stream(f"Echo: {prompt}", req_id):
                    yield chunk

        return StreamingResponse(
            event_generator(),
            media_type="text/event-stream",
            headers={"X-Request-ID": req_id},
        )

    # Non-streaming path (existing behavior)
    try:
        content = (
            await fetch_from_backend(
                client=http_request.app.state.client,
                backend_url=BACKEND_URL,
                request=request,
                req_id=req_id,
                timeout=BACKEND_TIMEOUT,
            )
            if BACKEND_URL
            else f"Echo: {prompt}"
        )
    except Exception as e:
        content = f"Backend error: {str(e)}"

    response = normalize_response(content, req_id, prompt)

    return JSONResponse(content=response.model_dump(), headers={"X-Request-ID": req_id})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
