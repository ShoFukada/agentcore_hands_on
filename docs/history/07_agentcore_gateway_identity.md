# Gateway & Identity統合実装

## 概要

AgentCore GatewayとIdentity（Credential Provider）を統合し、TavilyのウェブサーチAPIをエージェントから利用できる機能を実装。AWS_IAM認証とWorkload Identityを使用した安全なAPI Key管理を実現。

## 1. Terraformインフラ構築

### 1.1 Gateway Module作成 (コミット ebb1e08)

#### Gateway Moduleの新規作成

`infrastructure/modules/gateway/`ディレクトリを作成し、以下のリソースを定義：

**infrastructure/modules/gateway/main.tf**:

##### 1. API Key Credential Provider

```hcl
resource "aws_bedrockagentcore_api_key_credential_provider" "tavily" {
  name    = var.tavily_credential_provider_name
  api_key = var.tavily_api_key
}
```

**ポイント**:
- Tavily API KeyをAWS Secrets Managerで安全に管理
- AgentCore Identity機能を利用

##### 2. Gateway Resource

```hcl
resource "aws_bedrockagentcore_gateway" "main" {
  name        = var.gateway_name
  description = var.description
  role_arn    = var.gateway_role_arn

  authorizer_type = var.authorizer_type  # "AWS_IAM"
  protocol_type   = var.protocol_type    # "MCP"

  tags = var.tags
}
```

**ポイント**:
- MCP (Model Context Protocol) をサポート
- AWS_IAM 認証でセキュアなアクセス制御

##### 3. Tavily OpenAPI Schema定義

```hcl
locals {
  tavily_openapi_schema = jsonencode({
    openapi = "3.0.0"
    info = {
      title   = "Tavily Search API"
      version = "1.0.0"
    }
    servers = [{
      url = "https://api.tavily.com"
    }]
    paths = {
      "/search" = {
        post = {
          operationId = "TavilySearchPost"
          summary     = "Execute a search query using Tavily Search"
          # ... パラメータ定義 (query, search_depth, max_resultsなど)
        }
      }
      "/extract" = {
        post = {
          operationId = "TavilyExtractPost"
          summary     = "Extract content from specified URLs"
          # ... パラメータ定義
        }
      }
    }
    components = {
      securitySchemes = {
        ApiKeyAuth = {
          type = "apiKey"
          in   = "header"
          name = "Authorization"
        }
      }
    }
  })
}
```

**ポイント**:
- OpenAPI 3.0形式でTavily APIを定義
- `/search`と`/extract`の2つのエンドポイント
- 詳細なパラメータとレスポンススキーマ

##### 4. Gateway Target

```hcl
resource "aws_bedrockagentcore_gateway_target" "tavily" {
  name               = var.tavily_target_name
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = var.tavily_target_description

  # API Key認証設定
  credential_provider_configuration {
    api_key {
      provider_arn              = aws_bedrockagentcore_api_key_credential_provider.tavily.credential_provider_arn
      credential_location       = "HEADER"
      credential_parameter_name = "Authorization"
      credential_prefix         = "Bearer "
    }
  }

  # OpenAPI schemaベースのターゲット設定
  target_configuration {
    mcp {
      open_api_schema {
        inline_payload {
          payload = local.tavily_openapi_schema
        }
      }
    }
  }
}
```

**ポイント**:
- Credential Providerと連携してAPI Keyを自動取得
- Authorizationヘッダーに`Bearer <API_KEY>`形式で付与
- OpenAPI schemaを使ってツール定義を自動生成

#### main.tfへのGateway Module追加

`infrastructure/main.tf`に以下を追加：

```hcl
# Gateway Module (MCP Tools Integration)
module "gateway" {
  source = "./modules/gateway"

  gateway_name     = local.gateway_name
  gateway_role_arn = module.iam.gateway_role_arn
  description      = "Gateway for integrating MCP tools with ${var.agent_name}"

  protocol_type   = "MCP"
  authorizer_type = "AWS_IAM"

  # Tavily configuration
  tavily_api_key     = var.tavily_api_key
  tavily_target_name = local.gateway_target_name

  tags = local.common_tags
}
```

#### Gateway IAM Role作成

`infrastructure/modules/iam/main.tf`にGateway用IAMロールを追加（初期版）：

```hcl
# Gateway IAM Role
resource "aws_iam_role" "gateway" {
  count = var.create_gateway_role ? 1 : 0
  name  = var.gateway_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "gateway" {
  count = var.create_gateway_role ? 1 : 0
  name  = var.gateway_policy_name
  role  = aws_iam_role.gateway[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 初期バージョン（後で権限追加が必要）
      {
        Sid    = "BasicGatewayAccess"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetCredentialProvider",
          "bedrock-agentcore:ListCredentialProviders"
        ]
        Resource = "*"
      }
    ]
  })
}
```

**注意**: この初期バージョンでは権限が不足しており、後続のコミットで追加権限が必要になります。

### 1.2 Gateway IAMロール権限追加

`infrastructure/modules/iam/main.tf`のGateway IAMポリシーに以下を追加：

#### Identity (Credential Provider) アクセス権限

```hcl
statement {
  sid    = "IdentityCredentialAccess"
  effect = "Allow"
  actions = [
    "bedrock-agentcore:GetCredentialProvider",
    "bedrock-agentcore:ListCredentialProviders",
    "bedrock-agentcore:GetResourceApiKey"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:credential-provider/*",
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:token-vault/*",
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/*"
  ]
}
```

**ポイント**:
- `GetResourceApiKey` - Credential ProviderからAPI Keyを取得
- 3つのリソースARNパターンで広範なアクセスをカバー

#### Workload Identity Token権限

```hcl
statement {
  sid    = "GetWorkloadAccessToken"
  effect = "Allow"
  actions = [
    "bedrock-agentcore:GetWorkloadAccessToken"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/*"
  ]
}
```

**ポイント**:
- Workload Identityトークンを取得する権限
- `/default`と`/default/workload-identity/*`の両方をカバー

#### Secrets Manager アクセス権限（動的参照）

```hcl
# 動的ステートメント - gateway_secrets_arnsが設定されている場合のみ作成
dynamic "statement" {
  for_each = length(var.gateway_secrets_arns) > 0 ? [1] : []
  content {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = var.gateway_secrets_arns
  }
}
```

**ポイント**:
- ハードコードではなく、Credential Providerから動的にSecretsManager ARNを参照
- `gateway_secrets_arns`変数を`infrastructure/modules/iam/variables.tf`に追加

### 1.3 Gateway OutputにSecretsManager ARN追加

`infrastructure/modules/gateway/outputs.tf`に追加：

```hcl
output "tavily_api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret for Tavily API Key"
  value       = aws_bedrockagentcore_api_key_credential_provider.tavily.api_key_secret_arn[0].secret_arn
}
```

### 1.4 main.tfでIAMモジュールにSecretsManager ARN渡す

`infrastructure/main.tf`のIAMモジュール呼び出しに追加：

```hcl
module "iam" {
  # ... 既存の設定 ...

  # Gateway IAM Role
  create_gateway_role  = true
  gateway_role_name    = "${var.project_name}-gateway-role"
  gateway_policy_name  = "${var.project_name}-gateway-policy"
  lambda_function_arns = []
  gateway_secrets_arns = [module.gateway.tavily_api_key_secret_arn]  # ← 追加

  tags = local.common_tags
}
```

**ポイント**:
- Gateway moduleのoutputから実際のSecretsManager ARNを参照
- Terraformの依存関係で正しい値が渡される

### 1.5 デプロイ

```bash
cd infrastructure

export AWS_PROFILE=239339588912_AdministratorAccess

# 検証
terraform validate

# 計画確認
terraform plan

# 適用
terraform apply -auto-approve
```

### 1.6 デプロイされるリソース

- Gateway IAMロールに3つの権限ステートメント追加
  - `IdentityCredentialAccess` - Credential Provider/Token Vault/Workload Identity Directory
  - `GetWorkloadAccessToken` - Workload Identityトークン取得
  - `SecretsManagerAccess` - 動的に参照されたSecretsManager ARN

## 2. Agent側の実装

### 依存関係追加

```bash
uv add httpx-aws-auth
```

**httpx-aws-auth**: AWS SigV4署名をhttpxで扱うためのライブラリ

### 設定の追加

**.env**に追加：
```bash
# AgentCore Gateway Configuration
GATEWAY_URL=https://agentcore-hands-on-gateway-gxaburshtd.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp
GATEWAY_ID=agentcore-hands-on-gateway-gxaburshtd
GATEWAY_TARGET_PREFIX=agentcore-hands-on-tavily-target___
```

**src/agentcore_hands_on/config.py**に追加：
```python
class Settings(BaseSettings):
    # ... 既存の設定 ...

    # Gateway settings
    GATEWAY_URL: str = ""
    GATEWAY_ID: str = ""
    GATEWAY_TARGET_PREFIX: str = ""
```

### web_researchツール実装

**src/agentcore_hands_on/agent.py**に追加：

```python
import boto3
from httpx_aws_auth import AwsCredentials, AwsSigV4Auth
from mcp.client.streamable_http import streamablehttp_client
from strands.tools.mcp.mcp_client import MCPClient

@tool
def web_research(query: str, search_depth: str = "basic") -> str:
    """Perform web research using Tavily search engine via AgentCore Gateway.

    This tool uses a dedicated research agent to search the web for information
    using the Tavily API through AWS Bedrock AgentCore Gateway with AWS_IAM authentication.
    """
    try:
        # Gateway設定の検証
        if not settings.GATEWAY_URL or not settings.GATEWAY_ID:
            error_msg = "Gateway not configured."
            logger.error(error_msg)
            return json.dumps({"error": error_msg}, ensure_ascii=False)

        # AWS SigV4 auth作成
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

        # MCP client作成
        mcp_client = MCPClient(
            lambda: streamablehttp_client(settings.GATEWAY_URL, auth=auth)
        )

        with mcp_client:
            # ツール一覧取得
            all_tools = mcp_client.list_tools_sync()

            # Target Prefixでフィルタリング
            tools = [
                tool
                for tool in all_tools
                if hasattr(tool, "tool_name")
                and tool.tool_name.startswith(settings.GATEWAY_TARGET_PREFIX)
            ]

            # リサーチ専用エージェント作成
            research_agent = Agent(
                model=BedrockModel(
                    model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
                    region_name=settings.AWS_REGION,
                ),
                tools=tools,
                system_prompt=(
                    "You are a research specialist agent. "
                    "Use the Tavily search tools to find accurate information."
                ),
            )

            # リサーチ実行
            response = research_agent(
                f"Research the following topic: {query}\n"
                f"Search depth: {search_depth}"
            )

            return json.dumps({
                "query": query,
                "search_depth": search_depth,
                "results": str(response),
            }, ensure_ascii=False)

    except Exception as e:
        error_msg = f"Web research failed: {e!s}"
        logger.exception(error_msg)
        return json.dumps({"error": error_msg}, ensure_ascii=False)
```

### create_agentにweb_researchツールを追加

```python
def create_agent(session_id: str | None = None, actor_id: str | None = None) -> Agent:
    # ... Memory設定 ...

    return Agent(
        model=BedrockModel(
            model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
            region_name=settings.AWS_REGION,
        ),
        tools=[execute_python, browse_web, web_research],  # ← web_research追加
        session_manager=session_manager,
    )
```

### 実装のポイント

1. **AWS SigV4認証**: `httpx-aws-auth`でGatewayへの認証を実装
2. **MCP Client**: Strands SDKの`MCPClient`でGatewayと通信
3. **ツールフィルタリング**: `GATEWAY_TARGET_PREFIX`でTavilyツールのみ取得
4. **研究専用エージェント**: Tavilyツールを持つ専用エージェントを動的生成
5. **エラーハンドリング**: Gateway未設定時やAPI呼び出し失敗時の適切なエラー返却

## 3. デプロイとテスト

### バージョン更新

`infrastructure/terraform.tfvars`のimage_tagを更新：

```hcl
image_tag = "v1.1.4"
```

### Dockerイメージのビルドとプッシュ

```bash
cd /Users/fukadasho/individual_development/agentcore_hands_on
export AWS_PROFILE=239339588912_AdministratorAccess
./scripts/build_and_push.sh 239339588912.dkr.ecr.us-east-1.amazonaws.com/agentcore-hands-on-my-agent v1.1.4
```

### Terraform Apply

```bash
cd infrastructure
terraform apply -auto-approve
```

**結果**: Runtime version 26 → 27 に更新

### IAM権限エラーと修正

#### エラー1: GetWorkloadAccessToken権限不足

**エラーログ** (CloudWatch Gateway Application Logs):
```
User: arn:aws:sts::239339588912:assumed-role/agentcore-hands-on-gateway-role/gateway-session
is not authorized to perform: bedrock-agentcore:GetWorkloadAccessToken
on resource: arn:aws:bedrock-agentcore:us-east-1:239339588912:workload-identity-directory/default
```

**原因**: Gateway RoleにWorkload Identityトークン取得権限がない

**修正**: `GetWorkloadAccessToken`ステートメントを追加（上記参照）し、再度`terraform apply`

#### エラー2: GetResourceApiKey権限不足

**エラーログ**:
```
User is not authorized to perform: bedrock-agentcore:GetResourceApiKey
on resource: arn:aws:bedrock-agentcore:us-east-1:239339588912:token-vault/default/apikeycredentialprovider/tavily-api-key-provider
```

**原因**: `IdentityCredentialAccess`に`GetResourceApiKey`権限がない

**修正**: `GetResourceApiKey`を`IdentityCredentialAccess`のactionsに追加

#### エラー3: リソースARNパターン不足

**エラーログ**:
```
User is not authorized to perform: bedrock-agentcore:GetResourceApiKey
on resource: arn:aws:bedrock-agentcore:us-east-1:239339588912:workload-identity-directory/default/workload-identity/agentcore-hands-on-gateway-gxaburshtd
```

**原因**: `credential-provider/*`のみでは`token-vault/*`や`workload-identity-directory/*`をカバーできない

**修正**: 3つのリソースARNパターンを追加（上記参照）

#### エラー4: SecretsManager ARN不一致

**エラーログ**:
```
User is not authorized to perform: secretsmanager:GetSecretValue
```

**原因**: ハードコードされたARNパターン `bedrock-agentcore/credentials/*` が、実際のARN `bedrock-agentcore-identity!default/apikey/tavily-api-key-provider-0B5KG8` と一致しない

**修正**: Terraformで動的に実際のSecretsManager ARNを参照（上記参照）

**参考**: [Qiita記事 - AgentCore Gateway IAM権限](https://qiita.com/neruneruo/items/19407f7a982d09553c22)

### Agent実行テスト

#### テスト1: 最新AI開発ニュース検索

```bash
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "Search for the latest AI developments in 2025" \
  --session-id "verify-tavily-$(uuidgen)" \
  --actor-id "test-user" \
  --region us-east-1
```

**実行結果**:
```json
{
  "response": "Based on my research of current tech news sites, here are the **latest AI developments in 2025**:\n\n## Major AI Developments in 2025:\n\n### 1. **AI Factory & Manufacturing**\n- **Samsung and Nvidia** announced a new \"AI megafactory\" powered by over 50,000 Nvidia chips...\n\n### 2. **AI Search & Browsers**\n- **AI browsers** are emerging as a major trend...\n- **Perplexity** struck a multi-year licensing deal with **Getty Images**...\n\n### 3. **AI Video & Content Creation**\n- **Adobe** released an experimental AI tool that can edit entire videos...\n\n..."
}
```

✅ **成功**: 実際のニュース結果を取得

#### テスト2: Python 3.13機能検索

```bash
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "Search for latest Python 3.13 features" \
  --session-id "secrets-fix-test-$(uuidgen)" \
  --actor-id "test-user" \
  --region us-east-1
```

**実行結果**:
```json
{
  "response": "## **Python 3.13 Key Features** (Released October 7, 2024)\n\n### 🎯 **Major Highlights**\n\n1. **New Interactive REPL**\n   - Block-level editing and history\n   - Color-enabled prompts and tracebacks\n   ...\n\n2. **Improved Error Messages**\n   - Color-coded tracebacks\n   - Smart suggestions for typos\n   ...\n\n3. **Free-Threaded Mode (Experimental)**\n   - GIL can be disabled for true parallel execution\n   ...\n\n4. **Experimental JIT Compiler**\n   - Generates machine code at runtime\n   - ~5% performance improvement\n   ..."
}
```

✅ **成功**: 詳細な技術情報を正確に取得

### CloudWatch Logsでエラー確認

```bash
aws logs tail "/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/agentcore-hands-on-gateway-gxaburshtd" \
  --since 2m --format short --region us-east-1 | grep "secretsmanager"
```

**結果**: エラーログなし（SecretsManagerエラーが完全に解消）

## まとめ

### 実装内容

- AgentCore GatewayとIdentity（Credential Provider）を統合
- AWS SigV4認証（httpx-aws-auth）でGatewayへのセキュアなアクセスを実現
- Tavily Web Search APIをエージェントから利用可能に
- 研究専用エージェントパターンで外部ツールを効果的に活用

### IAM権限の完全設定

Gateway IAMロールに3つの権限グループを追加：

1. **Identity & Credential Provider Access** (`GetResourceApiKey`)
   - `credential-provider/*`
   - `token-vault/*`
   - `workload-identity-directory/*`

2. **Workload Identity Token** (`GetWorkloadAccessToken`)
   - `/default`
   - `/default/workload-identity/*`

3. **Secrets Manager** (動的参照)
   - Credential Providerから取得した実際のSecretsManager ARN

### Terraformの改善

- Gateway moduleでSecretsManager ARNをoutput
- IAM moduleで動的に実際のARNを参照
- ハードコードを排除し、保守性向上

### 動作確認

- ✅ Tavilyウェブ検索が完全動作
- ✅ 最新AIニュース、Python 3.13詳細など実際の情報を取得
- ✅ すべてのIAM権限エラーが解消
- ✅ CloudWatch Logsでエラーなし

### v1.1.4でデプロイ完了

Runtime version 27で稼働中

## 関連コミット

- **ebb1e08** - Gateway Module初期作成（API Key Credential Provider, Gateway Resource, Tavily OpenAPI Schema, Gateway Target）
- **d382f5d** - Bedrock AgentCore Runtime SDK使用への変更、Observability event出力調整
- **bef0b52** - PR #1 マージ（Observability機能統合）

## 参考ドキュメント

- [AgentCore Gateway IAM権限（Qiita）](https://qiita.com/neruneruo/items/19407f7a982d09553c22)
- [Terraform Gateway Resource](/docs/terraform_docs/gateway.md)
- [Terraform Credential Provider](/docs/terraform_docs/credential_provider.md)
- [Strands MCP Client](https://strandsagents.com/)
