from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from pydantic import ValidationError

from models import AppConfig


def load_config(path: str | Path) -> AppConfig:
    config_path = Path(path)
    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found at {config_path}")

    with config_path.open("r", encoding="utf-8") as f:
        raw: Any = yaml.safe_load(f) or {}

    try:
        return AppConfig.model_validate(raw)
    except ValidationError as exc:
        raise ValueError(f"Invalid configuration: {exc}") from exc
