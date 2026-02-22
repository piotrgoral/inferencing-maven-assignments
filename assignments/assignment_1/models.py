from pydantic import BaseModel


# --- Request ---
class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]
    stream: bool = False
    model: str = "default"


# --- Response ---
class AssistantMessage(BaseModel):
    role: str = "assistant"
    content: str


class Choice(BaseModel):
    index: int = 0
    message: AssistantMessage
    finish_reason: str = "stop"


# --- Streaming Response (SSE chunks) ---
class DeltaMessage(BaseModel):
    role: str | None = None
    content: str | None = None


class StreamChoice(BaseModel):
    index: int = 0
    delta: DeltaMessage
    finish_reason: str | None = None


class BackendResponse(BaseModel):
    choices: list[Choice]


# --- Gateway Response (full OpenAI-style with id, usage, etc.) ---
class Usage(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


class GatewayResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    choices: list[Choice]
    usage: Usage
