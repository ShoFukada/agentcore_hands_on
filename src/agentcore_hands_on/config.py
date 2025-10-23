import os
from pathlib import Path
from typing import Any

from pydantic_settings import BaseSettings, SettingsConfigDict


def find_env_file() -> str | None:
    """プロジェクトルートの.envファイルを再帰的に探す"""
    current_path: Path = Path(__file__).resolve()

    for parent in current_path.parents:
        env_file: Path = parent / ".env"
        if env_file.exists():
            return str(env_file)

    return None


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=find_env_file(),
        env_file_encoding="utf-8",
    )

    OPENAI_API_KEY: str | None = None

    def __init__(self, **data: Any) -> None:  # noqa: ANN401
        super().__init__(**data)
        for field_name, field_value in self.model_dump().items():
            if field_value is not None:
                os.environ[field_name] = str(field_value)
