import os

from fastapi import FastAPI

from models import ChatRequest, BackendResponse, Choice, AssistantMessage

app = FastAPI()

# Config from environment
MOCK_PORT = int(os.getenv("MOCK_PORT", "8081"))


@app.get("/healthz")
async def healthz():
    """Health check endpoint."""
    return {"status": "ok"}


@app.post("/v1/chat/completions", response_model=BackendResponse)
async def chat_completions(request: ChatRequest):
    """
    Mock backend endpoint that always returns "Mock" as the response content.
    """
    return BackendResponse(choices=[Choice(message=AssistantMessage(content="Mock"))])


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=MOCK_PORT)
