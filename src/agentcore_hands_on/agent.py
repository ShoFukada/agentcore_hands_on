"""Strands Agent Runtime with OpenTelemetry support.

/ping と /invocations エンドポイントを実装
"""

import json
import logging
import sys

from bedrock_agentcore.tools.browser_client import BrowserClient
from bedrock_agentcore.tools.code_interpreter_client import CodeInterpreter
from fastapi import FastAPI
from playwright.sync_api import sync_playwright
from pydantic import BaseModel
from strands import Agent, tool
from strands.models.bedrock import BedrockModel

from agentcore_hands_on.config import Settings

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

# 設定の読み込み
settings = Settings()

app = FastAPI(title="Strands Agent Runtime")


@tool
def execute_python(code: str, description: str = "") -> str:
    r"""Execute Python code in a sandboxed Code Interpreter environment.

    This tool allows you to run Python code safely for data analysis, calculations,
    and file processing tasks. The code runs in an isolated sandbox environment.

    Args:
        code: The Python code to execute. Should be valid Python syntax.
        description: Optional description of what the code does. Will be added as a comment.

    Returns:
        str: The execution result as a JSON string containing the output,
             or an error message if execution fails.

    Example:
        execute_python("print('Hello, World!')", "Simple greeting")
        execute_python("result = 2 + 2\nprint(result)", "Basic calculation")

    """
    try:
        # Add description as comment if provided
        if description:
            code = f"# {description}\n{code}"

        # code_sessionではデフォルトのinterpreterしか使えないため、
        # CodeInterpreterクラスを直接使用してカスタムidentifierを指定
        client = CodeInterpreter(region=settings.AWS_REGION)

        # カスタムCode Interpreterでセッション開始
        session_id = client.start(identifier=settings.CODE_INTERPRETER_ID)
        logger.info("Code Interpreter session started: %s", session_id)

        try:
            # コード実行
            response = client.invoke(
                "executeCode",
                {"code": code, "language": "python", "clearContext": False},
            )

            # ストリーミングレスポンスの処理
            result_text = ""
            for event in response["stream"]:
                logger.debug("Code execution event: %s", event)

                if "result" in event:
                    result_text = json.dumps(event["result"], ensure_ascii=False)
                elif "stdout" in event:
                    result_text = event["stdout"]
                elif "structuredContent" in event:
                    result_text = json.dumps(event["structuredContent"], ensure_ascii=False)

            return result_text if result_text else "実行完了(出力なし)"

        finally:
            # セッション停止
            client.stop()
            logger.info("Code Interpreter session stopped")

    except Exception as e:
        error_msg = f"Code execution failed: {e!s}"
        logger.exception(error_msg)
        return json.dumps({"error": error_msg}, ensure_ascii=False)


@tool
def browse_web(url: str) -> str:
    """Browse the web and get page information.

    Access a URL and retrieve the page title and text content.

    Args:
        url: The URL to visit. Must be a valid HTTP/HTTPS URL.

    Returns:
        str: The page information as a JSON string containing title and text content,
             or an error message if the action fails.

    Example:
        browse_web("https://example.com")

    """
    try:
        # BrowserClientを使用してカスタムBrowserに接続
        client = BrowserClient(region=settings.AWS_REGION)

        # カスタムBrowserでセッション開始
        session_id = client.start(identifier=settings.BROWSER_ID)
        logger.info("Browser session started: %s", session_id)

        try:
            # WebSocket接続情報を取得
            ws_url, headers = client.generate_ws_headers()

            # Playwrightで接続
            with sync_playwright() as playwright:
                browser = playwright.chromium.connect_over_cdp(
                    endpoint_url=ws_url,
                    headers=headers,
                )

                try:
                    page = browser.new_page()
                    logger.info("Navigating to: %s", url)
                    page.goto(url, wait_until="domcontentloaded")

                    # ページ情報を取得
                    title = page.title()
                    text_content = page.inner_text("body")

                    result = {
                        "url": url,
                        "title": title,
                        "content": text_content,
                    }

                    return json.dumps(result, ensure_ascii=False)

                finally:
                    browser.close()

        finally:
            # セッション停止
            client.stop()
            logger.info("Browser session stopped")

    except Exception as e:
        error_msg = f"Browser action failed: {e!s}"
        logger.exception(error_msg)
        return json.dumps({"error": error_msg}, ensure_ascii=False)


# Strands Agent の初期化 (Code Interpreter + Browserツール付き)
agent = Agent(
    model=BedrockModel(
        model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
        region_name=settings.AWS_REGION,
    ),
    tools=[execute_python, browse_web],
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
    """メインの呼び出しエンドポイント - Strands Agent を使用

    Code Interpreter と Browser ツールを統合したAIエージェントとして動作します。
    """
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
