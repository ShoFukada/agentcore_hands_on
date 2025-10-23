# デプロイ手順

IAMの作成,ECRの作成,AgentcoreRuntimeの作成まで。
エージェントはおうむ返しのシンプルなもの

## 概要

AWS Bedrock AgentCore にエージェントをデプロイするには、以下の順序で作業を行う必要があります。

## 手順

### 1. 事前準備（Terraform で ECR と IAM を作成）

まず、Docker イメージを保存する ECR リポジトリと、Agent Runtime が使用する IAM ロールを作成します。

```bash
cd infrastructure

# AWS プロファイルを設定
export AWS_PROFILE=your-aws-profile

# login
aws sso login

# ECR と IAM のみを作成（Agent Runtime は後で作成）
terraform apply -target=module.ecr -target=module.iam
```

### 2. Docker イメージをビルドして ECR にプッシュ

ECR リポジトリが作成されたら、エージェントの Docker イメージをビルドして ECR にプッシュします。

```bash
cd ..  # プロジェクトルートへ

# ECR リポジトリ URL を取得（terraform output から）
ECR_URL=$(cd infrastructure && terraform output -raw ecr_repository_url)

# Docker イメージをビルド & プッシュ
./scripts/build_and_push.sh ${ECR_URL} latest
```

### 3. Agent Runtime と Endpoint を作成

Docker イメージが ECR にプッシュされたら、Agent Runtime と Endpoint を作成します。

```bash
cd infrastructure

# 残りのリソース（Agent Runtime と Endpoint）を作成
terraform apply
```

## なぜこの順序が必要か

1. **ECR リポジトリが先に必要**: Docker イメージをプッシュする先の ECR リポジトリが存在する必要がある
2. **Docker イメージが先に必要**: Agent Runtime を作成する際、指定した Docker イメージ（`container_uri`）が ECR に存在することを AWS が検証するため
3. **IAM ロールが先に必要**: Agent Runtime 作成時に IAM ロールの ARN を指定する必要があり、そのロールが存在し、適切な信頼ポリシーを持っている必要がある

## まとめ

```
1. terraform apply -target=module.ecr -target=module.iam  # ECR + IAM 作成
2. ./scripts/build_and_push.sh <ECR_URL> latest           # Docker イメージをプッシュ
3. terraform apply                                         # Agent Runtime 作成
```

この順序を守ることで、スムーズにデプロイできます。


# AgentCore の動作確認方法

## 概要

デプロイした Agent Runtime を Python スクリプトで呼び出して動作確認する方法です。

## 前提条件

```bash
export AWS_PROFILE=your-aws-profile
aws sso login
```

## Agent Runtime を呼び出す

Python スクリプト `invoke_agent.py` を使用してエージェントを呼び出します。

### 基本的な使い方

```bash
# Agent Runtime ARN を取得
RUNTIME_ARN=$(cd infrastructure && terraform output -raw agent_runtime_arn)

# エージェントを呼び出す（リージョンを明示的に指定）
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "${RUNTIME_ARN}" \
  --prompt "Hello, how are you?" \
  --region us-east-1
```

### 使用例

```bash
# シンプルな呼び出し
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/my-agent-xxx \
  --prompt "こんにちは" \
  --region us-east-1

# 別のリージョンで実行
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn arn:aws:bedrock-agentcore:us-west-2:123456789012:runtime/my-agent-xxx \
  --prompt "Hello" \
  --region us-west-2
```

### ワンライナーで実行

```bash
# terraform output から直接 ARN を取得して実行
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "$(cd infrastructure && terraform output -raw agent_runtime_arn)" \
  --prompt "テストメッセージ" \
  --region us-east-1
```

## 期待される結果

エージェントが正常に動作している場合、以下のようなレスポンスが返ります：

```json
{
  "output": {
    "response": "受信したメッセージ: Hello, how are you?"
  },
  "sessionId": "session_abc123..."
}
```

