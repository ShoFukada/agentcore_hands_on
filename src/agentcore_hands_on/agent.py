"""超シンプルなAgent Runtime.

/ping と /invocations エンドポイントのみを実装
"""

import logging
import sys

from fastapi import FastAPI
from pydantic import BaseModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Simple Agent Runtime")


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
    """メインの呼び出しエンドポイント"""
    prompt = request.input.get("prompt", "")
    logger.info("リクエストを受信: prompt=%s, session_id=%s", prompt, request.session_id)

    # シンプルなエコーレスポンス
    response_text = f"受信したメッセージ: {prompt}"
    logger.info("レスポンスを生成: %s", response_text)

    return InvocationResponse(output={"response": response_text}, session_id=request.session_id)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)  # noqa: S104
