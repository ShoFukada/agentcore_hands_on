"""Strands Agent Runtime with OpenTelemetry support.

AgentCore SDK を使用した実装
"""

import json
import logging
import sys

import boto3
from bedrock_agentcore import BedrockAgentCoreApp
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import (
    AgentCoreMemorySessionManager,
)
from bedrock_agentcore.tools.browser_client import BrowserClient
from bedrock_agentcore.tools.code_interpreter_client import CodeInterpreter
from httpx_aws_auth import AwsCredentials, AwsSigV4Auth
from mcp.client.streamable_http import streamablehttp_client
from playwright.sync_api import sync_playwright
from strands import Agent, tool
from strands.models.bedrock import BedrockModel
from strands.tools.mcp.mcp_client import MCPClient

from agentcore_hands_on.config import Settings

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

# 設定の読み込み
settings = Settings()

# AgentCore アプリケーションを作成
app = BedrockAgentCoreApp(debug=True)


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


@tool
def web_research(query: str, search_depth: str = "basic") -> str:
    """Perform web research using Tavily search engine via AgentCore Gateway.

    This tool uses a dedicated research agent to search the web for information
    using the Tavily API through AWS Bedrock AgentCore Gateway with AWS_IAM authentication.
    It's designed for read-only research tasks that require up-to-date information from the web.

    Args:
        query: The search query or research topic. Be specific and clear.
        search_depth: Search depth level. Options: "basic" (faster, general results)
                     or "advanced" (slower, more comprehensive). Default is "basic".

    Returns:
        str: Research results as a JSON string containing relevant information,
             or an error message if the research fails.

    Example:
        web_research("latest AI developments in 2025", "basic")
        web_research("Python best practices for async programming", "advanced")

    """
    try:
        # Gateway設定の検証
        if not settings.GATEWAY_URL or not settings.GATEWAY_ID:
            error_msg = "Gateway not configured. GATEWAY_URL and GATEWAY_ID are required."
            logger.error(error_msg)
            return json.dumps({"error": error_msg}, ensure_ascii=False)

        logger.info("Connecting to Gateway: %s", settings.GATEWAY_ID)

        # Create AWS SigV4 auth with httpx-aws-auth
        session = boto3.Session()
        creds = session.get_credentials()

        auth = AwsSigV4Auth(
            credentials=AwsCredentials(
                access_key=creds.access_key,
                secret_key=creds.secret_key,
                session_token=creds.token,
            ),
            region=settings.AWS_REGION,
            service="bedrock-agentcore",
        )
        logger.debug("Created SigV4 auth for Gateway authentication")

        # Create MCP client with SigV4 auth
        mcp_client = MCPClient(lambda: streamablehttp_client(settings.GATEWAY_URL, auth=auth))

        # withステートメントでライフサイクル管理
        with mcp_client:
            # MCPサーバーからツール一覧を取得
            all_tools = mcp_client.list_tools_sync()
            logger.info("Retrieved %d tools from Gateway", len(all_tools))

            # Gateway Target Prefixでフィルタリング(Tavily関連のツールのみ)
            if settings.GATEWAY_TARGET_PREFIX:
                tools = [
                    tool
                    for tool in all_tools
                    if hasattr(tool, "tool_name") and tool.tool_name.startswith(settings.GATEWAY_TARGET_PREFIX)
                ]
                logger.info(
                    "Filtered to %d tools with prefix: %s",
                    len(tools),
                    settings.GATEWAY_TARGET_PREFIX,
                )
            else:
                tools = all_tools
                logger.info("Using all %d tools (no prefix filter)", len(tools))

            # リサーチ専用エージェントを作成
            research_agent = Agent(
                model=BedrockModel(
                    model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
                    region_name=settings.AWS_REGION,
                ),
                tools=tools,
                system_prompt=(
                    "You are a research specialist agent. Your role is to search the web "
                    "for accurate, relevant information and synthesize the findings. "
                    "Focus on providing factual, well-sourced information. "
                    "Use the Tavily search tools available to you to find the best results."
                ),
            )

            # リサーチエージェントにクエリを実行
            logger.info("Starting web research: query=%s, depth=%s", query, search_depth)
            research_prompt = (
                f"Research the following topic and provide a comprehensive summary: {query}\n"
                f"Search depth: {search_depth}"
            )

            response = research_agent(research_prompt)
            response_text = str(response)

            logger.info("Web research completed successfully")
            return json.dumps(
                {
                    "query": query,
                    "search_depth": search_depth,
                    "results": response_text,
                },
                ensure_ascii=False,
            )

    except Exception as e:
        error_msg = f"Web research failed: {e!s}"
        logger.exception(error_msg)
        return json.dumps({"error": error_msg}, ensure_ascii=False)


def create_agent(session_id: str | None = None, actor_id: str | None = None) -> Agent:
    """Strands Agent を作成する(Memory統合対応)

    Args:
        session_id: セッションID(指定しない場合はデフォルト値を使用)
        actor_id: アクターID(指定しない場合はデフォルト値を使用)

    Returns:
        Agent: 初期化されたStrands Agent

    """
    # MEMORY_IDが設定されている場合はSessionManagerを作成
    session_manager = None
    if settings.MEMORY_ID:
        memory_config = AgentCoreMemoryConfig(
            memory_id=settings.MEMORY_ID,
            session_id=session_id or settings.DEFAULT_SESSION_ID,
            actor_id=actor_id or settings.DEFAULT_ACTOR_ID,
        )

        session_manager = AgentCoreMemorySessionManager(
            agentcore_memory_config=memory_config,
            region_name=settings.AWS_REGION,
        )
        logger.info(
            "Memory統合有効: memory_id=%s, session_id=%s, actor_id=%s",
            settings.MEMORY_ID,
            memory_config.session_id,
            memory_config.actor_id,
        )

    # Strands Agent を作成
    return Agent(
        model=BedrockModel(
            model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
            region_name=settings.AWS_REGION,
        ),
        tools=[execute_python, browse_web, web_research],
        session_manager=session_manager,
    )


@app.entrypoint
def invoke(payload: dict) -> dict:
    """AgentCore Runtimeのエントリーポイント

    Code Interpreter と Browser ツールを統合したAIエージェントとして動作します。
    MEMORY_IDが設定されている場合、会話履歴が保存されます。

    Args:
        payload: 入力データ(prompt, session_id, actor_idを含む)

    Returns:
        dict: レスポンスデータ(responseを含む)

    """
    prompt = payload.get("prompt", "")
    session_id = payload.get("session_id")
    actor_id = payload.get("actor_id")

    logger.info(
        "リクエストを受信: prompt=%s, session_id=%s, actor_id=%s",
        prompt,
        session_id,
        actor_id,
    )

    try:
        # session_idとactor_idを使用してAgentを作成
        current_agent = create_agent(
            session_id=session_id,
            actor_id=actor_id,
        )

        # Strands Agent で処理
        response = current_agent(prompt)
        response_text = str(response)

        logger.info("Agent実行完了")
    except Exception as e:
        logger.exception("Agent 実行中にエラーが発生")
        return {"response": f"エラーが発生しました: {e!s}"}
    else:
        return {"response": response_text}


if __name__ == "__main__":
    # AgentCore Runtime でアプリケーションを起動
    app.run()
