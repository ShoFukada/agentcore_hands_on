# Amazon Bedrock AgentCore デプロイガイド

## 概要

AgentCore Runtimeへのデプロイには2つの方法があります:

1. **Starter Toolkit使用**: 自動化されたデプロイプロセス（推奨）
2. **カスタムデプロイ**: 手動での詳細な制御が可能

このドキュメントでは、両方のアプローチと作成されるAWSリソースについて説明します。

---

## 方法1: Starter Toolkitを使用したデプロイ

### 概要

AgentCore Starter Toolkitは、AIエージェントのデプロイプロセスを自動化し、必要なインフラストラクチャを自動的に作成・設定します。

### 前提条件

- AWSアカウント
- Python 3.10以上
- AWS認証情報の設定済み
- Boto3インストール済み
- モデルアクセス有効化（例: Anthropic Claude Sonnet 4.0）

### インストール

```bash
pip install bedrock-agentcore strands-agents bedrock-agentcore-starter-toolkit
```

### デプロイ手順

#### 1. エージェントコードの作成

`my_agent.py`:
```python
from strands_agents import Agent

agent = Agent(
    name="MyAssistant",
    instructions="ユーザーの質問に答えるアシスタント"
)

def run(input_text: str) -> str:
    response = agent.run(input_text)
    return response
```

`requirements.txt`:
```
strands-agents
bedrock-agentcore
```

#### 2. エージェントの設定

```bash
agentcore configure -e my_agent.py
```

このコマンドは自動的に `bedrock_agentcore.yaml` を生成します。

#### 3. デプロイ実行

```bash
agentcore launch
```

デプロイが完了すると、Agent ARNが出力されます:
```
Agent ARN: arn:aws:bedrock-agentcore:us-west-2:123456789012:agent/my-agent-id
```

#### 4. エージェントの呼び出し

```bash
agentcore invoke --agent-arn <your-agent-arn> --input "こんにちは"
```

### デプロイモード

#### デフォルトモード (推奨)
- CodeBuild + Cloud Runtime
- 本番環境向け
- Dockerのローカルインストール不要

#### ローカル開発モード
- Docker-based local deployment
- 開発・テスト向け
- ローカルでの高速イテレーション

#### ハイブリッドモード
- ローカルビルド + クラウドデプロイ
- ビルドの制御が必要な場合

### 作成されるAWSリソース

#### 1. IAM実行ロール
- **リソース名**: 自動生成（カスタマイズ可能）
- **目的**: AgentCore Runtimeでエージェントを実行する権限
- **カスタマイズ**: `--execution-role` フラグで既存ロールを指定可能

```bash
agentcore launch --execution-role arn:aws:iam::123456789012:role/MyCustomRole
```

- **付与される権限**:
  - Bedrock model invoke permissions
  - CloudWatch Logs書き込み
  - その他エージェント実行に必要な権限

#### 2. Amazon ECR リポジトリ
- **リソース名**: 自動生成
- **目的**: エージェントのコンテナイメージをホスト
- **アーキテクチャ**: ARM64
- **管理**: Starter Toolkitが自動でイメージをビルド・プッシュ

#### 3. AWS CodeBuild プロジェクト
- **リソース名**: 自動生成
- **目的**: エージェントのビルドとデプロイを管理
- **利点**:
  - ローカルにDockerが不要
  - 一貫したビルド環境
  - AWSインフラでビルド実行

#### 4. CloudWatch リソース

##### CloudWatch Logs
- **ロググループ**: エージェント実行時のログを記録
- **出力場所**: デプロイ時に表示される
- **用途**: デバッグ、監視、トラブルシューティング

##### CloudWatch Transaction Search
- **目的**: エージェントのトランザクション監視
- **有効化**: デプロイ時に自動設定
- **機能**: リクエスト/レスポンスのトレース

#### 5. AgentCore Runtime
- **リージョン**: デフォルトは us-west-2（変更可能）
- **タイプ**: サーバーレス実行環境
- **特徴**:
  - 自動スケーリング
  - セッション分離
  - 拡張ランタイムサポート
  - 高速コールドスタート
  - マルチモーダルペイロード対応

### 設定ファイル: bedrock_agentcore.yaml

自動生成される設定ファイルの例:

```yaml
agent_name: my-assistant
entry_point: my_agent.py
runtime: python3.11
requirements: requirements.txt
region: us-west-2
observability:
  cloudwatch_logs: enabled
  transaction_search: enabled
```

---

## 方法2: カスタムデプロイ（Starter Toolkit不使用）

### 概要

より詳細な制御が必要な場合、手動でエージェントをデプロイできます。FastAPIを使用してカスタムエンドポイントを実装します。

### 前提条件

- Python 3.11
- FastAPI
- Docker（ARM64イメージビルド用）
- AWS CLI
- Strands Agents ライブラリ

### デプロイ手順

#### 1. プロジェクト構造の作成

```
my-custom-agent/
├── agent.py           # FastAPIアプリケーション
├── Dockerfile         # コンテナ定義
├── requirements.txt   # 依存パッケージ
├── deploy_agent.py    # デプロイスクリプト
└── invoke_agent.py    # 呼び出しスクリプト
```

#### 2. エージェント実装 (agent.py)

AgentCore Runtimeの契約に従い、必須エンドポイントを実装:

```python
from fastapi import FastAPI, Request
from strands_agents import Agent

app = FastAPI()

agent = Agent(
    name="CustomAgent",
    instructions="カスタムエージェント"
)

@app.post("/invocations")
async def invocations(request: Request):
    """
    必須エンドポイント: エージェントの実行
    """
    body = await request.json()
    input_text = body.get("input", "")

    response = agent.run(input_text)

    return {
        "output": response,
        "status": "success"
    }

@app.get("/ping")
async def ping():
    """
    必須エンドポイント: ヘルスチェック
    """
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

**重要な要件**:
- `/invocations` エンドポイント: エージェント実行用
- `/ping` エンドポイント: ヘルスチェック用
- ポート 8080 でリッスン
- ARM64 アーキテクチャ

#### 3. Dockerfileの作成

```dockerfile
FROM --platform=linux/arm64 public.ecr.aws/docker/library/python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY agent.py .

EXPOSE 8080

CMD ["python", "agent.py"]
```

#### 4. requirements.txt

```
fastapi
uvicorn[standard]
strands-agents
bedrock-agentcore
boto3
```

#### 5. ECRリポジトリの作成

```bash
aws ecr create-repository \
    --repository-name my-strands-agent \
    --region us-west-2
```

**出力例**:
```json
{
    "repository": {
        "repositoryArn": "arn:aws:ecr:us-west-2:123456789012:repository/my-strands-agent",
        "repositoryUri": "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-strands-agent"
    }
}
```

#### 6. Dockerイメージのビルドとプッシュ

```bash
# ECR認証
aws ecr get-login-password --region us-west-2 | \
    docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-west-2.amazonaws.com

# ARM64イメージのビルド
docker buildx build --platform linux/arm64 \
    -t my-strands-agent:latest .

# タグ付け
docker tag my-strands-agent:latest \
    123456789012.dkr.ecr.us-west-2.amazonaws.com/my-strands-agent:latest

# プッシュ
docker push 123456789012.dkr.ecr.us-west-2.amazonaws.com/my-strands-agent:latest
```

#### 7. IAMロールの作成

```bash
# 信頼ポリシー (trust-policy.json)
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock-agentcore.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# ロール作成
aws iam create-role \
    --role-name AgentRuntimeRole \
    --assume-role-policy-document file://trust-policy.json

# 必要なポリシーをアタッチ
aws iam attach-role-policy \
    --role-name AgentRuntimeRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess

aws iam attach-role-policy \
    --role-name AgentRuntimeRole \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
```

#### 8. Agent Runtimeのデプロイ (deploy_agent.py)

```python
import boto3

client = boto3.client('bedrock-agentcore', region_name='us-west-2')

response = client.create_agent_runtime(
    agentRuntimeName='my-custom-agent',
    image='123456789012.dkr.ecr.us-west-2.amazonaws.com/my-strands-agent:latest',
    roleArn='arn:aws:iam::123456789012:role/AgentRuntimeRole',
    networkConfig={
        'type': 'PUBLIC'  # または 'PRIVATE'
    }
)

print(f"Agent ARN: {response['agentRuntimeArn']}")
print(f"Status: {response['status']}")
```

実行:
```bash
python deploy_agent.py
```

#### 9. エージェントの呼び出し (invoke_agent.py)

```python
import boto3
import json

client = boto3.client('bedrock-agentcore', region_name='us-west-2')

response = client.invoke_agent(
    agentRuntimeArn='arn:aws:bedrock-agentcore:us-west-2:123456789012:agent/my-agent-id',
    inputText='こんにちは、元気ですか？'
)

print(json.dumps(response['output'], indent=2, ensure_ascii=False))
```

### 作成が必要なAWSリソース（手動）

#### 1. IAMロール (AgentRuntimeRole)
- **目的**: AgentCore Runtimeでの実行権限
- **必須ポリシー**:
  - Bedrock model invoke
  - CloudWatch Logs書き込み
  - ECRイメージ取得
  - 必要に応じてS3、DynamoDBなど

#### 2. Amazon ECR リポジトリ
- **作成方法**: `aws ecr create-repository`
- **アーキテクチャ**: ARM64必須
- **管理**: イメージのビルド・プッシュは手動

#### 3. Agent Runtime
- **作成方法**: `create_agent_runtime` API
- **必須設定**:
  - エージェントランタイム名
  - コンテナURI（ECRから）
  - ネットワーク設定（PUBLIC/PRIVATE）
  - IAMロールARN

#### 4. ネットワーク設定（PROVATEの場合）
- VPC
- サブネット
- セキュリティグループ
- VPCエンドポイント（Bedrock用）

#### 5. AWS認証情報
- **環境変数**:
  ```bash
  export AWS_ACCESS_KEY_ID=your-access-key
  export AWS_SECRET_ACCESS_KEY=your-secret-key
  export AWS_SESSION_TOKEN=your-session-token  # 一時認証情報の場合
  export AWS_REGION=us-west-2
  ```

---

## 比較表: Starter Toolkit vs カスタムデプロイ

| 項目 | Starter Toolkit | カスタムデプロイ |
| --- | --- | --- |
| **セットアップ時間** | 5-10分 | 30-60分 |
| **自動化レベル** | 完全自動 | 手動 |
| **制御レベル** | 標準設定 | 完全制御 |
| **IAMロール作成** | 自動 | 手動 |
| **ECR管理** | 自動 | 手動 |
| **CodeBuild使用** | あり | なし |
| **Dockerのローカル要件** | 不要（デフォルト） | 必須 |
| **エンドポイント実装** | 不要 | 必須（/invocations, /ping） |
| **設定ファイル** | bedrock_agentcore.yaml | deploy_agent.py |
| **適用シーン** | 迅速なプロトタイプ、標準デプロイ | カスタムアーキテクチャ、細かい制御 |
| **学習曲線** | 低 | 中〜高 |
| **本番環境適用** | ✅ 推奨 | ✅ 高度なユースケース |

---

## 作成されるAWSリソース一覧

### 共通リソース

| リソース | Starter Toolkit | カスタムデプロイ | 説明 |
| --- | --- | --- | --- |
| **IAM実行ロール** | 自動作成 | 手動作成 | エージェント実行権限 |
| **ECRリポジトリ** | 自動作成 | 手動作成 | コンテナイメージ保存 |
| **Agent Runtime** | 自動作成 | API経由で作成 | サーバーレス実行環境 |
| **CloudWatch Logs** | 自動設定 | 手動設定 | ログ収集 |

### Starter Toolkit固有のリソース

| リソース | 説明 |
| --- | --- |
| **CodeBuild プロジェクト** | イメージビルド・デプロイ自動化 |
| **CloudWatch Transaction Search** | トランザクション監視 |
| **bedrock_agentcore.yaml** | 設定ファイル（自動生成） |

### カスタムデプロイで追加設定が必要なリソース

| リソース | 必須/任意 | 説明 |
| --- | --- | --- |
| **VPC** | 任意 | PRIVATE networkの場合 |
| **サブネット** | 任意 | PRIVATE networkの場合 |
| **セキュリティグループ** | 任意 | PRIVATE networkの場合 |
| **VPCエンドポイント** | 任意 | Bedrock等へのプライベート接続 |

---

## 推奨アプローチ

### Starter Toolkitを使うべき場合
✅ 迅速にエージェントをデプロイしたい
✅ インフラ管理を最小化したい
✅ 標準的なデプロイパターンで十分
✅ 本番環境での運用
✅ チーム開発での一貫性確保

### カスタムデプロイを使うべき場合
✅ エンドポイントの完全制御が必要
✅ カスタムミドルウェアやロジックを追加したい
✅ 既存のCI/CDパイプラインと統合
✅ 特殊なネットワーク構成（VPC、プライベートサブネット）
✅ 細かいIAM権限設定が必要

---

## トラブルシューティング

### Starter Toolkit

#### デプロイ失敗
```bash
# CloudWatch Logsで詳細確認
aws logs tail /aws/bedrock-agentcore/my-agent --follow
```

#### モデルアクセスエラー
```
エラー: Model access denied
対処: Bedrockコンソールでモデルアクセスを有効化
```

### カスタムデプロイ

#### ARM64ビルドエラー
```bash
# buildxが有効か確認
docker buildx ls

# 必要に応じてbuilder作成
docker buildx create --use
```

#### エージェントが応答しない
```python
# /pingエンドポイントのテスト
import requests
response = requests.get("http://localhost:8080/ping")
print(response.json())
```

---

## まとめ

- **Starter Toolkit**: ほとんどのユースケースで推奨。自動化されており、迅速にデプロイ可能
- **カスタムデプロイ**: 高度な制御が必要な場合に使用。完全な柔軟性を提供

どちらの方法でも、AgentCore Runtimeの強力な機能（自動スケーリング、セッション分離、組み込み監視）を活用できます。

## 参考リンク

- [AgentCore Starter Toolkit ドキュメント](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/getting-started-starter-toolkit.html)
- [カスタムデプロイガイド](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/getting-started-custom.html)
- [AgentCore Runtime API リファレンス](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/)
