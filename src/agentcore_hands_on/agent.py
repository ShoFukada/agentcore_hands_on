"""Strands Agent Runtime with OpenTelemetry support.

/ping と /invocations エンドポイントを実装
"""

import logging
import sys

from fastapi import FastAPI
from pydantic import BaseModel
from strands import Agent
from strands.models.bedrock import BedrockModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Strands Agent Runtime")

# Strands Agent の初期化
agent = Agent(
    model=BedrockModel(
        model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
        region_name="us-east-1",
    ),
)


class InvocationRequest(BaseModel):
    """リクエストモデル"""

    input: dict
    session_id: str | None = None


class InvocationResponse(BaseModel):
    """レスポンスモデル"""

    output: dict
    session_id: str | None = None


@app.get("/ping")
def health_check() -> dict[str, str]:
    """ヘルスチェックエンドポイント"""
    logger.info("ヘルスチェックリクエストを受信")
    return {"status": "healthy"}


@app.post("/invocations")
def invoke(request: InvocationRequest) -> InvocationResponse:
    """メインの呼び出しエンドポイント - Strands Agent を使用"""
    prompt = request.input.get("prompt", "")
    logger.info("リクエストを受信: prompt=%s, session_id=%s", prompt, request.session_id)

    try:
        # Strands Agent で処理
        response = agent(prompt)
        response_text = str(response)

        return InvocationResponse(
            output={"response": response_text},
            session_id=request.session_id,
        )
    except Exception as e:
        logger.exception("Agent 実行中にエラーが発生")
        return InvocationResponse(
            output={"response": f"エラーが発生しました: {e!s}"},
            session_id=request.session_id,
        )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)  # noqa: S104
