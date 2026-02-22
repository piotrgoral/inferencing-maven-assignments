import os
import asyncio
import json
import uuid
from typing import Optional

from fastapi import FastAPI, Header
from fastapi.responses import StreamingResponse

from models import ChatRequest, BackendResponse, Choice, AssistantMessage

app = FastAPI()

# Config from environment
MOCK_PORT = int(os.getenv("MOCK_PORT", "8081"))


@app.get("/healthz")
async def healthz():
    """Health check endpoint."""
    return {"status": "ok"}


async def char_stream(text: str, req_id: str):
    """Generate SSE chunks for streaming response, one character at a time."""
    for char in text:
        chunk = {
            "id": req_id,
            "object": "chat.completion.chunk",
            "choices": [
                {
                    "index": 0,
                    "delta": {"content": char},
                    "finish_reason": None,
                }
            ],
        }
        yield f"data: {json.dumps(chunk)}\n\n"
        await asyncio.sleep(0)  # yield to event loop
    yield "data: [DONE]\n\n"


@app.post("/v1/chat/completions")
async def chat_completions(
    request: ChatRequest,
    x_request_id: Optional[str] = Header(None, alias="X-Request-ID"),
    request_id: Optional[str] = Header(None, alias="Request-Id"),
):
    """
    Mock backend endpoint that returns "Mock" as the response content.
    Supports streaming when stream=True.
    """
    req_id = x_request_id or request_id or str(uuid.uuid4())
    text = "Mock"

    if request.stream:
        return StreamingResponse(
            char_stream(text, req_id),
            media_type="text/event-stream",
        )
    else:
        return BackendResponse(choices=[Choice(message=AssistantMessage(content=text))])


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=MOCK_PORT)
