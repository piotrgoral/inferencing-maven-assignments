from __future__ import annotations

import httpx

from backends import Backend, EchoBackend, RemoteHttpBackend
from models import AppConfig


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
