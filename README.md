# AgentCore Hands-on

AWS Bedrock AgentCore Runtime with Strands AI framework.

## Overview

Bedrock AgentCore の主要機能を実装したハンズオンプロジェクト:

- **Agent Runtime**: Strands AI エージェントフレームワークとの統合
- **Code Interpreter**: Python コード実行環境
- **Browser**: Web ブラウザ自動化
- **Memory**: セッション・ユーザー単位の会話記憶
- **Gateway + Identity**: Tavily API を使った Web 検索（AWS_IAM 認証）
- **Observability**: CloudWatch による監視

## Dependencies

- Python >= 3.12
- uv (パッケージマネージャー)
- Docker
- Terraform
- AWS CLI

主要な Python パッケージ:
- `bedrock-agentcore>=1.0.4`
- `strands-agents[otel]>=0.1.0`
- `boto3`
- `fastapi>=0.120.0`
- `httpx-aws-auth>=4.1.1`

## Setup

```bash
# 依存関係のインストール
uv sync

# 環境変数ファイルの作成
cp .env.sample .env
```

## Infrastructure Deploy

### 初回デプロイ

```bash
cd infrastructure

# tfvars ファイルを編集
cp example.tfvars terraform.tfvars
# terraform.tfvars を編集して設定

# デプロイ
terraform init
terraform plan
terraform apply
```

**注意**: Observability 機能を使う場合、事前に AWS コンソールから Transaction Search を ON にしておく必要があります。

### インフラ更新

```bash
cd infrastructure
terraform plan
terraform apply
```

デプロイ後、`.env` ファイルに以下を設定:

```bash
# Terraform の出力値を取得
terraform output

# .env に設定
CODE_INTERPRETER_ID=<terraform output から>
BROWSER_ID=<terraform output から>
MEMORY_ID=<terraform output から>
GATEWAY_URL=<terraform output から>
GATEWAY_ID=<terraform output から>
GATEWAY_TARGET_PREFIX=<terraform output から>
```

## Application Deploy

アプリケーションコードを更新してデプロイする手順:

### 1. バージョンを変更

`infrastructure/terraform.tfvars` の `image_tag` を更新:

```hcl
image_tag = "v1.1.4"  # バージョンを変更
```

### 2. コンテナのビルド & プッシュ

```bash
# AWS プロファイルを設定
export AWS_PROFILE=<your-aws-profile>

# ECR にビルド & プッシュ
./scripts/build_and_push.sh <ECR_REPOSITORY_URL> <TAG>

# 例:
./scripts/build_and_push.sh 123456789012.dkr.ecr.us-east-1.amazonaws.com/agentcore-hands-on-my-agent v1.1.4
```

### 3. Terraform でデプロイ

```bash
cd infrastructure
terraform apply
```

## Local Execution

ローカルで Agent サーバーを起動してテスト:

```bash
# サーバー起動
uv run -m agentcore_hands_on.agent

# 別ターミナルで動作確認
curl http://localhost:8080/ping

# Agent の実行
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Hello!",
    "session_id": "test-session",
    "actor_id": "user-123"
  }'
```

## AgentCore Runtime Execution

デプロイされた AgentCore Runtime を実行:

```bash
export AWS_PROFILE=<your-aws-profile>

uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/your-runtime-id" \
  --prompt "Search the web for latest AI news" \
  --session-id "my-session-123" \
  --actor-id "user-alice" \
  --region us-east-1
```

## Features

### Code Interpreter
Python コードをサンドボックス環境で実行。データ分析やファイル処理に使用。

### Browser
Web ページの自動操作。URL へのアクセス、コンテンツ抽出、ページ操作。

### Memory
- **Session Memory**: `session_id` で会話をグループ化
- **User Memory**: `actor_id` でユーザーを識別
- **Memory Strategies**: SEMANTIC、SUMMARIZATION、USER_PREFERENCE

### Gateway + Identity (Tavily Web Search)
- Tavily API を使った Web 検索
- AWS_IAM 認証による Gateway アクセス
- API キーは AgentCore Identity (Credential Provider) に保存

## Project Structure

```
.
├── src/
│   └── agentcore_hands_on/
│       ├── agent.py           # メインエージェント実装
│       ├── config.py           # 設定管理
│       └── invoke_agent.py    # Runtime 実行スクリプト
├── infrastructure/
│   ├── modules/               # Terraform モジュール
│   │   ├── agent_runtime/
│   │   ├── code_interpreter/
│   │   ├── browser/
│   │   ├── memory/
│   │   ├── gateway/
│   │   └── iam/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── example.tfvars
├── scripts/
│   └── build_and_push.sh      # Docker ビルド & プッシュ
├── tests/
├── docs/                      # ドキュメント
├── pyproject.toml
├── .env.sample
└── README.md
```

## Development

```bash
# テスト実行
uv run pytest

# Linting
uv run ruff check .

# 型チェック
uv run pyright

# フォーマット
uv run ruff format .
```

## License

MIT License
