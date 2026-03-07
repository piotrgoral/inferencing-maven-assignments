from __future__ import annotations

from typing import Protocol

import httpx

from models import ChatRequest, BackendResponse


class Backend(Protocol):
    """Common backend interface with a single generate() method."""

    async def generate(
        self, prompt: str, request: ChatRequest, request_id: str | None = None
    ) -> str: ...


class EchoBackend:
    """Simple echo backend; returns the prompt with a prefix."""

    async def generate(
        self, prompt: str, request: ChatRequest, request_id: str | None = None
    ) -> str:
        return f"Echo: {prompt}"


class RemoteHttpBackend:
    """HTTP backend that forwards the full request payload to a remote gateway."""

    def __init__(
        self,
        url: str,
        client: httpx.AsyncClient,
        timeout: float,
    ) -> None:
        self.url = url.rstrip("/")
        self.client = client
        self.timeout = timeout

    async def generate(
        self, prompt: str, request: ChatRequest, request_id: str | None = None
    ) -> str:
        """POST to remote /v1/chat/completions and return the first message content."""
        backend_response = await self.client.post(
            f"{self.url}/v1/chat/completions",
            json=request.model_dump(),
            headers={"X-Request-ID": request_id} if request_id else None,
            timeout=self.timeout,
        )
        backend_response.raise_for_status()
        backend_data = backend_response.json()
        backend_resp = BackendResponse.model_validate(backend_data)
        return backend_resp.choices[0].message.content
