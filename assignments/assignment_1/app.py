import os
import uuid
from typing import Optional

import httpx
from fastapi import FastAPI, Request, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel

app = FastAPI()

# Config from environment
PORT = int(os.getenv("PORT", "8080"))
BACKEND_URL = os.getenv("BACKEND_URL")


class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]
    stream: bool = False
    model: str = "default"


def estimate_tokens(text: str) -> int:
    """Approximate token count using word splitting."""
    return len(text.split())


def extract_last_user_message(messages: list[Message]) -> str:
    """Extract content from the last user message."""
    for msg in reversed(messages):
        if msg.role == "user":
            return msg.content
    return ""


def normalize_response(content: str, request_id: str, prompt: str) -> dict:
    """Build OpenAI-style response shape."""
    prompt_tokens = estimate_tokens(prompt)
    completion_tokens = estimate_tokens(content)

    return {
        "id": request_id,
        "object": "chat.completion",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    }


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

    # Forward to backend or echo
    if BACKEND_URL:
        # Forward to backend
        backend_url = f"{BACKEND_URL.rstrip('/')}/v1/chat/completions"
        try:
            async with httpx.AsyncClient() as client:
                backend_response = await client.post(
                    backend_url,
                    json=request.model_dump(),
                    headers={"X-Request-ID": req_id},
                    timeout=30.0,
                )
                backend_response.raise_for_status()
                backend_data = backend_response.json()

                # Extract content from backend response
                if "choices" in backend_data and len(backend_data["choices"]) > 0:
                    content = (
                        backend_data["choices"][0].get("message", {}).get("content", "")
                    )
                else:
                    content = str(backend_data)

                # Normalize response
                response = normalize_response(content, req_id, prompt)
        except Exception as e:
            # On backend error, fall back to echo
            content = f"Backend error: {str(e)}"
            response = normalize_response(content, req_id, prompt)
    else:
        # Echo mode
        content = f"Echo: {prompt}"
        response = normalize_response(content, req_id, prompt)

    # Return response with X-Request-ID header
    return JSONResponse(content=response, headers={"X-Request-ID": req_id})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
