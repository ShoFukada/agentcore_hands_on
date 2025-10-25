# AgentCore Memory 統合戦略

## 現在のエージェント実装の分析

### 現状の構成

```
src/agentcore_hands_on/
├── config.py           # 設定管理 (Pydantic Settings)
├── agent.py            # Strandsエージェント + FastAPI
└── invoke_agent.py     # CLI呼び出しスクリプト
```

**現在の機能:**
- ✅ Code Interpreter (Python実行)
- ✅ Browser (Web閲覧)
- ✅ Strands Agentフレームワーク
- ✅ FastAPI (/ping, /invocations エンドポイント)
- ✅ OpenTelemetry対応

**欠けている機能:**
- ❌ Memory機能（Short-term / Long-term）
- ❌ Session管理
- ❌ Actor管理
- ❌ 会話履歴の永続化

## 統合アプローチ

### アプローチ1: ミニマル統合（推奨）

**概要:**
現在の実装に最小限の変更でMemory機能を追加します。

**実装手順:**

#### Step 1: 設定の拡張

`config.py` に Memory 関連の設定を追加:

```python
class Settings(BaseSettings):
    # 既存の設定
    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"
    AWS_REGION: str = "us-east-1"
    CODE_INTERPRETER_ID: str = ""
    BROWSER_ID: str = ""

    # 新規: Memory関連
    MEMORY_ID: str = ""  # AgentCore Memory ID
    MEMORY_NAMESPACE_PREFIX: str = "agent_assistant"  # Namespace prefix
    ENABLE_SHORT_TERM_MEMORY: bool = True
    ENABLE_LONG_TERM_MEMORY: bool = True
    MEMORY_RETENTION_DAYS: int = 90
```

#### Step 2: Memory クライアントの作成

新しいファイル `src/agentcore_hands_on/memory_client.py` を作成:

```python
"""AgentCore Memory Client"""

import logging
from typing import Any

import boto3
from botocore.exceptions import ClientError

from agentcore_hands_on.config import Settings

logger = logging.getLogger(__name__)


class MemoryClient:
    """AgentCore Memory操作のためのクライアント"""

    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = boto3.client(
            "bedrock-agentcore",
            region_name=settings.AWS_REGION
        )

    def store_message(
        self,
        actor_id: str,
        session_id: str,
        message: str,
        role: str = "user"
    ) -> None:
        """Short-term Memoryにメッセージを保存"""
        if not self.settings.ENABLE_SHORT_TERM_MEMORY:
            return

        try:
            namespace = f"{self.settings.MEMORY_NAMESPACE_PREFIX}/sessions/{actor_id}/{session_id}"

            self.client.put_memory(
                memoryId=self.settings.MEMORY_ID,
                actorId=actor_id,
                sessionId=session_id,
                namespace=namespace,
                content={"message": message, "role": role}
            )
            logger.info(
                "Stored message to memory: actor=%s, session=%s",
                actor_id, session_id
            )
        except ClientError as e:
            logger.exception("Failed to store message to memory: %s", e)

    def retrieve_session_history(
        self,
        actor_id: str,
        session_id: str,
        max_items: int = 10
    ) -> list[dict[str, Any]]:
        """セッションの会話履歴を取得"""
        if not self.settings.ENABLE_SHORT_TERM_MEMORY:
            return []

        try:
            namespace = f"{self.settings.MEMORY_NAMESPACE_PREFIX}/sessions/{actor_id}/{session_id}"

            response = self.client.list_memories(
                memoryId=self.settings.MEMORY_ID,
                actorId=actor_id,
                sessionId=session_id,
                namespace=namespace,
                maxResults=max_items
            )

            memories = response.get("memories", [])
            logger.info(
                "Retrieved %d memories for actor=%s, session=%s",
                len(memories), actor_id, session_id
            )
            return memories

        except ClientError as e:
            logger.exception("Failed to retrieve memories: %s", e)
            return []

    def get_user_preferences(self, actor_id: str) -> dict[str, Any]:
        """ユーザーの好みや傾向を取得（Long-term Memory）"""
        if not self.settings.ENABLE_LONG_TERM_MEMORY:
            return {}

        try:
            namespace = f"{self.settings.MEMORY_NAMESPACE_PREFIX}/preferences/{actor_id}"

            response = self.client.retrieve_memory(
                memoryId=self.settings.MEMORY_ID,
                actorId=actor_id,
                namespace=namespace
            )

            return response.get("content", {})

        except ClientError as e:
            logger.warning("Failed to retrieve user preferences: %s", e)
            return {}
```

#### Step 3: エージェントへの統合

`agent.py` を修正してMemoryクライアントを組み込む:

```python
from agentcore_hands_on.memory_client import MemoryClient

# グローバルにMemoryClientを初期化
memory_client = MemoryClient(settings)


@app.post("/invocations")
def invoke(request: InvocationRequest) -> InvocationResponse:
    """メインの呼び出しエンドポイント - Memory統合版"""
    prompt = request.input.get("prompt", "")
    session_id = request.session_id or f"session_{uuid.uuid4().hex[:10]}"

    # Actor IDの取得（リクエストから、またはデフォルト値）
    actor_id = request.input.get("actor_id", "default_user")

    logger.info(
        "リクエストを受信: prompt=%s, actor_id=%s, session_id=%s",
        prompt, actor_id, session_id
    )

    try:
        # 1. 過去の会話履歴を取得
        history = memory_client.retrieve_session_history(actor_id, session_id)

        # 2. ユーザーの好みを取得（Long-term Memory）
        preferences = memory_client.get_user_preferences(actor_id)

        # 3. プロンプトに履歴と好みを組み込む
        enhanced_prompt = build_prompt_with_context(prompt, history, preferences)

        # 4. ユーザーメッセージをメモリに保存
        memory_client.store_message(actor_id, session_id, prompt, role="user")

        # 5. Strands Agent で処理
        response = agent(enhanced_prompt)
        response_text = str(response)

        # 6. アシスタントの応答をメモリに保存
        memory_client.store_message(
            actor_id, session_id, response_text, role="assistant"
        )

        return InvocationResponse(
            output={"response": response_text},
            session_id=session_id,
        )
    except Exception as e:
        logger.exception("Agent 実行中にエラーが発生")
        return InvocationResponse(
            output={"response": f"エラーが発生しました: {e!s}"},
            session_id=session_id,
        )


def build_prompt_with_context(
    prompt: str,
    history: list[dict],
    preferences: dict
) -> str:
    """会話履歴とユーザー好みを組み込んだプロンプトを生成"""
    context_parts = []

    # ユーザー好みの追加
    if preferences:
        context_parts.append("## ユーザーの好み")
        for key, value in preferences.items():
            context_parts.append(f"- {key}: {value}")

    # 会話履歴の追加
    if history:
        context_parts.append("\n## 過去の会話")
        for msg in history[-5:]:  # 最新5件のみ
            role = msg.get("role", "unknown")
            content = msg.get("message", "")
            context_parts.append(f"[{role}]: {content}")

    # 現在のプロンプト
    context_parts.append(f"\n## 現在の質問\n{prompt}")

    return "\n".join(context_parts)
```

#### Step 4: リクエストモデルの拡張

```python
class InvocationRequest(BaseModel):
    """リクエストモデル（Memory対応）"""

    input: dict  # prompt, actor_id を含む
    session_id: str | None = None
```

### アプローチ2: カスタムツール追加（高度）

Memory機能を直接ツールとして公開し、エージェント自身が記憶を操作できるようにします。

```python
@tool
def retrieve_past_conversations(actor_id: str, topic: str = "") -> str:
    """過去の会話からトピックに関連する情報を検索"""
    # Long-term Memoryから検索
    memories = memory_client.search_memories(
        actor_id=actor_id,
        query=topic,
        namespace=f"{settings.MEMORY_NAMESPACE_PREFIX}/knowledge"
    )

    return json.dumps(memories, ensure_ascii=False)


@tool
def remember_user_preference(actor_id: str, key: str, value: str) -> str:
    """ユーザーの好みを記録"""
    memory_client.store_preference(actor_id, key, value)
    return f"記録しました: {key} = {value}"


# Agentに追加
agent = Agent(
    model=BedrockModel(...),
    tools=[
        execute_python,
        browse_web,
        retrieve_past_conversations,  # 新規
        remember_user_preference,      # 新規
    ],
)
```

## 推奨される実装順序

### Phase 1: 基礎実装（1-2日）

1. ✅ Memory ID の作成（Terraform/AWS CLIで）
2. ✅ `config.py` の拡張
3. ✅ `memory_client.py` の実装
4. ✅ Short-term Memory の基本統合

### Phase 2: 統合とテスト（1-2日）

5. ✅ `agent.py` へのMemory統合
6. ✅ セッション管理の実装
7. ✅ ローカルテスト
8. ✅ デプロイとE2Eテスト

### Phase 3: 高度な機能（1-2日）

9. ✅ Long-term Memory の活用
10. ✅ カスタムツールの追加
11. ✅ Observability の強化（メモリ操作のトレース）
12. ✅ ドキュメント整備

## インフラ構成の変更

### Terraform 追加項目

`terraform/main.tf` に Memory リソースを追加:

```hcl
# AgentCore Memory
resource "aws_bedrock_agentcore_memory" "agent_memory" {
  name = "agent-assistant-memory"

  short_term_memory {
    retention_days = var.memory_retention_days
  }

  long_term_memory {
    enabled = true

    strategies {
      semantic_memory {
        enabled = true
      }

      user_preference_memory {
        enabled = true
      }

      summary_memory {
        enabled = true
      }
    }
  }

  tags = {
    Environment = var.environment
    Project     = "agentcore-hands-on"
  }
}

# Memory ID を出力
output "memory_id" {
  value = aws_bedrock_agentcore_memory.agent_memory.id
}
```

### 環境変数の追加

`.env` に追加:

```bash
MEMORY_ID=memory-xxxxxxxxxxxxx
MEMORY_NAMESPACE_PREFIX=agent_assistant
ENABLE_SHORT_TERM_MEMORY=true
ENABLE_LONG_TERM_MEMORY=true
MEMORY_RETENTION_DAYS=90
```

## テスト戦略

### 1. ユニットテスト

```python
# tests/test_memory_client.py
def test_store_and_retrieve_message():
    client = MemoryClient(settings)

    # メッセージ保存
    client.store_message(
        actor_id="test_user",
        session_id="test_session",
        message="Hello, AI!",
        role="user"
    )

    # 取得
    history = client.retrieve_session_history(
        actor_id="test_user",
        session_id="test_session"
    )

    assert len(history) > 0
    assert history[0]["message"] == "Hello, AI!"
```

### 2. 統合テスト

```python
# tests/test_agent_with_memory.py
def test_agent_remembers_context():
    # セッション1
    response1 = invoke_agent("私の名前は太郎です", session_id="s1")

    # セッション2（同じsession_id）
    response2 = invoke_agent("私の名前は何ですか？", session_id="s1")

    assert "太郎" in response2["response"]
```

## 監視とObservability

### メトリクス

- Memory操作の成功/失敗率
- レスポンスタイム（Memory取得時間）
- セッションあたりのメモリ使用量

### ログ

```python
logger.info(
    "Memory operation",
    extra={
        "operation": "retrieve_history",
        "actor_id": actor_id,
        "session_id": session_id,
        "memory_count": len(memories),
        "duration_ms": elapsed_time
    }
)
```

### トレース（OpenTelemetry）

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("memory.retrieve_history") as span:
    span.set_attribute("actor_id", actor_id)
    span.set_attribute("session_id", session_id)

    memories = memory_client.retrieve_session_history(actor_id, session_id)

    span.set_attribute("memory_count", len(memories))
```

## まとめ

### 推奨アプローチ: アプローチ1（ミニマル統合）

**理由:**
1. ✅ 既存コードへの影響が最小限
2. ✅ 段階的な実装が可能
3. ✅ テストとデバッグが容易
4. ✅ Phase 3でカスタムツールへの拡張も可能

**実装コスト:**
- 開発: 2-3日
- テスト: 1-2日
- デプロイ: 半日

**次のステップ:**
1. Memory ID をTerraformで作成
2. `memory_client.py` を実装
3. ローカルで動作確認
4. `agent.py` に統合
5. E2Eテスト
6. デプロイ
