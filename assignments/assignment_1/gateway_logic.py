import httpx
from models import (
    Message,
    Choice,
    AssistantMessage,
    GatewayResponse,
    Usage,
    ChatRequest,
    BackendResponse,
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
