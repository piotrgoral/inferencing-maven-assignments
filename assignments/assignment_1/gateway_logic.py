import asyncio
import json
import httpx
from models import (
    Message,
    Choice,
    AssistantMessage,
    GatewayResponse,
    Usage,
    ChatRequest,
    BackendResponse,
    ChatCompletionChunk,
    StreamChoice,
    DeltaMessage,
)


def estimate_tokens(text: str) -> int:
    """Approximate token count using word splitting."""
    return len(text.split())


def extract_last_user_message(messages: list[Message]) -> str:
    """Extract content from the last user message."""
    for msg in reversed(messages):
        if msg.role == "user":
            return msg.content
    return ""


async def fetch_from_backend(
    client: httpx.AsyncClient,
    backend_url: str,
    request: ChatRequest,
    req_id: str,
    timeout: float,
) -> str:
    """Fetch content from backend API. Returns content string or raises on failure."""
    url = f"{backend_url.rstrip('/')}/v1/chat/completions"
    backend_response = await client.post(
        url,
        json=request.model_dump(),
        headers={"X-Request-ID": req_id},
        timeout=timeout,
    )
    backend_response.raise_for_status()
    backend_data = backend_response.json()
    backend_resp = BackendResponse.model_validate(backend_data)
    return backend_resp.choices[0].message.content


def normalize_response(content: str, request_id: str, prompt: str) -> GatewayResponse:
    """Build OpenAI-style response shape."""
    prompt_tokens = estimate_tokens(prompt)
    completion_tokens = estimate_tokens(content)

    return GatewayResponse(
        id=request_id,
        object="chat.completion",
        choices=[
            Choice(
                index=0,
                message=AssistantMessage(content=content),
                finish_reason="stop",
            )
        ],
        usage=Usage(
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=prompt_tokens + completion_tokens,
        ),
    )


async def echo_stream(content: str, req_id: str):
    """Generate SSE chunks from a plain string, one character at a time."""
    for char in content:
        chunk = ChatCompletionChunk(
            id=req_id,
            choices=[
                StreamChoice(
                    index=0,
                    delta=DeltaMessage(content=char),
                    finish_reason=None,
                )
            ],
        )
        yield f"data: {chunk.model_dump_json()}\n\n"
        await asyncio.sleep(0)  # yield to event loop
    yield "data: [DONE]\n\n"


async def stream_from_backend(
    client: httpx.AsyncClient,
    backend_url: str,
    request: ChatRequest,
    req_id: str,
    timeout: float,
):
    """
    Stream SSE from backend if it supports streaming, otherwise return
    one SSE chunk with the full reply then [DONE].
    """
    url = f"{backend_url.rstrip('/')}/v1/chat/completions"

    try:
        async with client.stream(
            "POST",
            url,
            json=request.model_dump(),
            headers={"X-Request-ID": req_id},
            timeout=timeout,
        ) as response:
            response.raise_for_status()

            # Check if backend supports streaming
            content_type = response.headers.get("content-type", "")
            if "text/event-stream" in content_type:
                # Backend supports streaming - proxy SSE chunks
                async for line in response.aiter_lines():
                    if line:
                        yield f"{line}\n"
            else:
                # Backend doesn't support streaming - get full response and convert to SSE
                full_response = await response.aread()
                backend_data = json.loads(full_response)
                backend_resp = BackendResponse.model_validate(backend_data)
                content = backend_resp.choices[0].message.content

                # Return one SSE chunk with full content, then [DONE]
                chunk = ChatCompletionChunk(
                    id=req_id,
                    choices=[
                        StreamChoice(
                            index=0,
                            delta=DeltaMessage(content=content),
                            finish_reason=None,
                        )
                    ],
                )
                yield f"data: {chunk.model_dump_json()}\n\n"
                yield "data: [DONE]\n\n"
    except Exception as e:
        # On error, return error message as SSE chunk
        error_content = f"Backend error: {str(e)}"
        async for chunk in echo_stream(error_content, req_id):
            yield chunk
