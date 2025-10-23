"""超シンプルなAgent Runtime.

/ping と /invocations エンドポイントのみを実装
"""

from fastapi import FastAPI
from pydantic import BaseModel

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
    return {"status": "healthy"}


@app.post("/invocations")
def invoke(request: InvocationRequest) -> InvocationResponse:
    """メインの呼び出しエンドポイント"""
    prompt = request.input.get("prompt", "")

    # シンプルなエコーレスポンス
    response_text = f"受信したメッセージ: {prompt}"

    return InvocationResponse(output={"response": response_text}, session_id=request.session_id)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)  # noqa: S104
