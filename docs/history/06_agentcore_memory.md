# Memory実装

## 概要

AgentCore Memoryを統合し、エージェントが会話履歴を永続化して、セッション間で情報を記憶できる機能を実装。

## 1. Terraformインフラ構築

### Memoryモジュール作成

`infrastructure/modules/memory/`を作成：

- **main.tf**: Memory リソース定義（SEMANTIC、SUMMARIZATION、USER_PREFERENCE戦略）
- **variables.tf**: 名前、保持期間、実行ロール、戦略設定の変数
- **outputs.tf**: ARN、ID、名前、戦略情報を出力

### IAMロール設定

#### Memory専用実行IAMロール

`infrastructure/modules/iam/main.tf`に追加：

- Memory自体がBedrock モデルを呼び出すための実行ロール
- AWS管理ポリシー `AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy` をアタッチ

```hcl
resource "aws_iam_role" "memory_execution" {
  count = var.create_memory_execution_role ? 1 : 0

  name               = var.memory_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.memory_execution_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "memory_bedrock_inference" {
  count = var.create_memory_execution_role ? 1 : 0

  role       = aws_iam_role.memory_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}
```

#### Agent Runtime IAMロール権限追加

Runtime がMemoryにアクセスするための権限を追加：

```hcl
statement {
  sid    = "BedrockAgentCoreMemory"
  effect = "Allow"
  actions = [
    "bedrock-agentcore:GetMemory",
    "bedrock-agentcore:CreateEvent",
    "bedrock-agentcore:GetEvent",
    "bedrock-agentcore:ListEvents",
    "bedrock-agentcore:RetrieveMemoryRecords",
    "bedrock-agentcore:GetMemoryRecord",
    "bedrock-agentcore:ListMemoryRecords",
    "bedrock-agentcore:BatchCreateMemoryRecords",
    "bedrock-agentcore:ListActors",
    "bedrock-agentcore:ListSessions"
  ]
  resources = ["*"]
}
```

### main.tf更新

#### Memoryモジュール追加

```hcl
module "memory" {
  source = "./modules/memory"

  name                      = local.memory_name
  description               = "Memory for ${var.agent_name} with conversation history and knowledge extraction"
  event_expiry_duration     = var.memory_retention_days
  memory_execution_role_arn = module.iam.memory_execution_role_arn

  # Strategy configuration
  create_semantic_strategy        = var.memory_enable_semantic
  semantic_strategy_name          = "${replace(var.project_name, "-", "_")}_semantic_strategy"
  semantic_strategy_description   = "Extract technical knowledge and facts from conversations"
  semantic_namespaces             = ["${var.project_name}/knowledge/{actorId}"]

  create_user_preference_strategy = var.memory_enable_user_preference
  user_preference_strategy_name   = "${replace(var.project_name, "-", "_")}_preference_strategy"
  user_preference_strategy_description = "Track user preferences and behavioral patterns"
  user_preference_namespaces      = ["${var.project_name}/preferences/{actorId}"]

  create_summarization_strategy   = var.memory_enable_summarization
  summarization_strategy_name     = "${replace(var.project_name, "-", "_")}_summary_strategy"
  summarization_strategy_description = "Summarize long conversations into key points"

  tags = local.common_tags
}
```

#### Agent Runtime環境変数設定

`module.agent_runtime`の`environment_variables`にMemory IDを追加：

```hcl
environment_variables = {
  # 既存の環境変数
  LOG_LEVEL   = var.log_level
  ENVIRONMENT = var.environment

  # Code Interpreter ID
  CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id

  # Browser ID
  BROWSER_ID = module.browser.browser_id

  # Memory ID
  MEMORY_ID = module.memory.memory_id

  # ... その他の環境変数 ...
}
```

### デプロイ

```bash
cd infrastructure

export AWS_PROFILE=239339588912_AdministratorAccess

# 検証
terraform validate

# 計画確認
terraform plan

# 適用
terraform apply
```

### デプロイされるリソース

- `aws_bedrockagentcore_memory` - 会話履歴を保持するMemory
- `aws_bedrockagentcore_memory_strategy` - SEMANTIC、SUMMARIZATION、USER_PREFERENCE戦略
- `aws_iam_role.memory_execution` - Memory専用実行IAMロール
- Agent Runtime IAMロールにMemory操作権限追加

### デプロイ結果

```
memory_id   = agentcore_hands_on_my_agent_memory-0Eqy08AGax
memory_arn  = arn:aws:bedrock-agentcore:us-east-1:239339588912:memory/agentcore_hands_on_my_agent_memory-0Eqy08AGax
memory_name = agentcore_hands_on_my_agent_memory
```

## 2. Agent側の実装

### 依存関係追加

```bash
uv add bedrock-agentcore
```

### 設定の追加

**.env**に追加：
```bash
# AgentCore Memory Configuration
MEMORY_ID=agentcore_hands_on_my_agent_memory-0Eqy08AGax

# Memory Session Configuration (optional)
DEFAULT_SESSION_ID=default-session
DEFAULT_ACTOR_ID=default-user
```

**src/agentcore_hands_on/config.py**に追加：
```python
class Settings(BaseSettings):
    # ... 既存の設定 ...

    # AgentCore Memory settings
    MEMORY_ID: str = ""
    DEFAULT_SESSION_ID: str = "default-session"
    DEFAULT_ACTOR_ID: str = "default-user"
```

### Memory統合実装

**src/agentcore_hands_on/agent.py**に追加：

```python
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import (
    AgentCoreMemorySessionManager,
)

def create_agent(session_id: str | None = None, actor_id: str | None = None) -> Agent:
    """Create an agent instance with optional memory integration.

    Args:
        session_id: Session identifier for memory context (optional)
        actor_id: User/actor identifier for memory context (optional)

    Returns:
        Configured agent instance
    """
    session_manager = None
    if settings.MEMORY_ID:
        # Memory統合が有効な場合、AgentCoreMemorySessionManagerを作成
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
            "Memory enabled: session_id=%s, actor_id=%s",
            memory_config.session_id,
            memory_config.actor_id,
        )

    return Agent(
        model=BedrockModel(
            model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
            region_name=settings.AWS_REGION,
        ),
        tools=[execute_python, browse_web],
        session_manager=session_manager,
    )


class InvocationRequest(BaseModel):
    """Agent invocation request."""
    input: dict[str, Any]
    session_id: str | None = None
    actor_id: str | None = None


@app.post("/invocations")
async def invoke_agent(request: InvocationRequest) -> dict[str, Any]:
    """Invoke the agent with the given input."""
    try:
        # リクエストごとにエージェントを作成（session_id、actor_id付き）
        agent = create_agent(
            session_id=request.session_id,
            actor_id=request.actor_id,
        )

        prompt = request.input.get("prompt", "")
        logger.info("Received invocation request: %s", prompt)

        response = agent.run(prompt)
        logger.info("Agent response: %s", response)

        return {"output": {"response": response}}

    except Exception as e:
        logger.exception("Agent invocation failed")
        raise HTTPException(status_code=500, detail=str(e)) from e
```

### 実装のポイント

1. `AgentCoreMemoryConfig`でMemory ID、session_id、actor_idを指定
2. `AgentCoreMemorySessionManager`でMemoryセッション管理
3. `MEMORY_ID`が設定されている場合のみMemory統合を有効化
4. リクエストごとにエージェントを作成し、session_id/actor_idを渡す
5. Memoryは自動的に会話を保存・取得

## 3. デプロイとテスト

### バージョン更新

`infrastructure/terraform.tfvars`のimage_tagを更新：

```hcl
image_tag = "v1.0.8"
```

### Dockerイメージのビルドとプッシュ

```bash
cd /Users/fukadasho/individual_development/agentcore_hands_on
export AWS_PROFILE=239339588912_AdministratorAccess
./scripts/build_and_push.sh 239339588912.dkr.ecr.us-east-1.amazonaws.com/agentcore-hands-on-my-agent v1.0.8
```

### Terraform Apply

```bash
cd infrastructure
terraform apply
```

### IAM権限エラーと修正

初回デプロイ時に以下のエラーが発生：

```
AccessDeniedException: User is not authorized to perform: bedrock-agentcore:ListEvents
```

**原因**: Agent Runtime IAMロールにMemory操作権限が不足

**修正**: `infrastructure/modules/iam/main.tf`にMemory権限を追加（上記参照）し、再度`terraform apply`

### Agent実行テスト

#### テスト1: 名前を記憶

```bash
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{
    "input": {"prompt": "My name is Alice"},
    "session_id": "conversation-1",
    "actor_id": "user-123"
  }'
```

**実行結果**:
```json
{
  "output": {
    "response": "Nice to meet you, Alice! How can I help you today?"
  }
}
```

#### テスト2: 記憶を取得

```bash
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{
    "input": {"prompt": "What is my name?"},
    "session_id": "conversation-1",
    "actor_id": "user-123"
  }'
```

**実行結果**:
```json
{
  "output": {
    "response": "Your name is Alice!"
  }
}
```

✅ **Memory統合成功**: エージェントが正しく会話履歴を記憶し、別のリクエストで名前を思い出すことができた。

## 4. Invoke Agent Runtime でのテスト

### スクリプト修正

`src/agentcore_hands_on/invoke_agent.py`に`--session-id`と`--actor-id`のオプションを追加：

```python
parser.add_argument("--session-id", help="セッションID（指定しない場合は自動生成）")
parser.add_argument("--actor-id", help="アクターID（Memory機能で使用）")

# セッションID生成（指定がない場合のみ）
if args.session_id:
    session_id = args.session_id
else:
    session_id = f"dfmeoagmreaklgmrkleafremoigrmtesogmtrskhmtkrlshmt{uuid.uuid4().hex[:10]}"

# ペイロード
payload_data = {"input": {"prompt": args.prompt}}
if args.actor_id:
    payload_data["actorId"] = args.actor_id
payload = json.dumps(payload_data)
```

### テスト1: 初回会話（名前と好きなものを記憶）

```bash
export AWS_PROFILE=239339588912_AdministratorAccess
uv run python -m agentcore_hands_on.invoke_agent \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "My name is Alice and I love Python programming" \
  --session-id "memory-test-session-001-xxxxxxxxx" \
  --actor-id "user-alice"
```

**実行結果**:
```json
{
  "output": {
    "response": "That's great to know, Alice! Python is an excellent programming language with a lot to offer. It's widely used for:\n\n- **Data analysis and visualization**\n- **Web development**\n- **Machine learning and AI**\n- **Automation and scripting**\n- **Scientific computing**\n- **General-purpose programming**\n\nSince you love Python programming, you might find it useful that I can help you by:\n- Writing and executing Python code\n- Debugging or testing code snippets\n- Performing calculations and data analysis\n- Processing files\n- And much more!\n\nFeel free to share any Python code you'd like to work on or any problems you'd like to solve. I'm here to help! 🐍\n"
  },
  "session_id": null
}
```

### テスト2: 同じセッションで記憶を確認

```bash
uv run python -m agentcore_hands_on.invoke_agent \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "What is my name?" \
  --session-id "memory-test-session-001-xxxxxxxxx" \
  --actor-id "user-alice"
```

**実行結果**:
```json
{
  "output": {
    "response": "Your name is Alice! 😊\n\nYou've told me that you're Alice and that you love Python programming.\n"
  },
  "session_id": null
}
```

✅ **短期記憶成功**: 同じセッション内で名前と好みを正しく記憶している。

### テスト3: Long-term Memory（異なるセッションIDで同じactor_id）

```bash
uv run python -m agentcore_hands_on.invoke_agent \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "Do you remember my name and what I like?" \
  --session-id "memory-test-session-002-yyyyyyyyy" \
  --actor-id "user-alice"
```

**実行結果**:
```json
{
  "output": {
    "response": "Yes, I do! 😊\n\n**Your name:** Alice\n\n**What you like:** Python programming\n\nYou shared both of these things with me at the beginning of our conversation, and I've retained that information throughout our chat.\n"
  },
  "session_id": null
}
```

✅ **Long-term Memory成功**: 異なるセッションIDでも同じactor_idであれば、以前の会話内容を記憶している。

### Memory動作の確認ポイント

1. **Short-term Memory**: 同じsession_id内での会話履歴は即座に参照可能
2. **Long-term Memory**: 異なるsession_idでも同じactor_idであれば、SEMANTIC/USER_PREFERENCE戦略により過去の情報を記憶
3. **Memory Strategy**: 3つの戦略（SEMANTIC、SUMMARIZATION、USER_PREFERENCE）が自動的に動作し、重要な情報を抽出・保存

## まとめ

- AgentCore Memoryリソースを3つの戦略（SEMANTIC、SUMMARIZATION、USER_PREFERENCE）で構築
- Memory専用実行IAMロールとRuntime権限を適切に設定
- Strands SDKの`AgentCoreMemorySessionManager`を使用して自動的に会話を永続化
- session_id/actor_idでセッション管理を実装
- v1.0.8でデプロイし、会話記憶機能の動作を確認
- ローカルHTTPエンドポイントとInvoke Agent Runtime両方でMemory機能の動作を検証
- Short-term Memory（同一セッション）とLong-term Memory（異なるセッション、同一アクター）の両方が正常に動作することを確認

## 参考ドキュメント

- [Runtime Memory IAM](/docs/chat/memory/runtime-memory-iam.md)
- [Memory Execution IAM](/docs/chat/memory/memory-execution-iam.md)
- [Terraform Memory Resource](/docs/terraform_docs/memory.md)
- [Terraform Memory Strategy](/docs/terraform_docs/memory_strategy.md)
