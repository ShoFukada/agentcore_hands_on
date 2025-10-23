# Infrastructure Guide

このガイドでは、AWS Bedrock AgentCore のインフラストラクチャコードの構成と設計について説明します。

## 目次

- [概要](#概要)
- [アーキテクチャ](#アーキテクチャ)
- [ディレクトリ構成](#ディレクトリ構成)
- [モジュール詳細](#モジュール詳細)
  - [ECR モジュール](#ecr-モジュール)
  - [IAM モジュール](#iam-モジュール)
  - [Agent Runtime モジュール](#agent-runtime-モジュール)
- [変数とカスタマイズ](#変数とカスタマイズ)
- [出力値](#出力値)
- [命名規則](#命名規則)

## 概要

`infrastructure/` ディレクトリには、AWS Bedrock AgentCore を使用したカスタムエージェントのインフラストラクチャを構築するための Terraform コードが含まれています。

このインフラストラクチャは、以下のコンポーネントで構成されています：

- **ECR リポジトリ**: エージェントのコンテナイメージを保存
- **IAM ロール/ポリシー**: Agent Runtime が必要な AWS サービスにアクセスするための権限
- **Agent Runtime**: エージェントのコンテナを実行する環境
- **Agent Runtime Endpoint**: エージェントを呼び出すためのエンドポイント

## アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│                  AWS Account                        │
│                                                     │
│  ┌────────────────┐                                │
│  │  ECR           │                                │
│  │  Repository    │◄──────┐                        │
│  └────────────────┘       │                        │
│                           │                        │
│  ┌────────────────┐       │                        │
│  │  IAM Role      │       │                        │
│  │  + Policy      │       │                        │
│  └────────┬───────┘       │                        │
│           │               │                        │
│           │ AssumeRole    │ Pull Image             │
│           │               │                        │
│  ┌────────▼────────┐      │                        │
│  │  Agent Runtime  ├──────┘                        │
│  │  (Container)    │                               │
│  └────────┬────────┘                               │
│           │                                        │
│           │ Exposes                                │
│           │                                        │
│  ┌────────▼────────┐                               │
│  │  Runtime        │                               │
│  │  Endpoint       │◄─── Invoke Agent              │
│  └─────────────────┘                               │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## ディレクトリ構成

```
infrastructure/
├── main.tf                    # メインの設定とモジュール呼び出し
├── variables.tf               # 入力変数の定義
├── outputs.tf                 # 出力値の定義
├── example.tfvars            # 変数の設定例
├── terraform.tfvars          # 実際の変数の設定（gitignore対象）
├── .terraform.lock.hcl       # プロバイダーのバージョンロック
└── modules/
    ├── ecr/                  # ECRリポジトリモジュール
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── iam/                  # IAMロール/ポリシーモジュール
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── agent_runtime/        # Agent Runtimeモジュール
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## モジュール詳細

### ECR モジュール

**場所**: `infrastructure/modules/ecr/`

**目的**: エージェントのコンテナイメージを保存するための ECR リポジトリを管理します。

#### 主要リソース

1. **ECR Repository** (`infrastructure/modules/ecr/main.tf:3`)
   - コンテナイメージを保存
   - プッシュ時に自動イメージスキャンを実行

2. **Lifecycle Policy** (`infrastructure/modules/ecr/main.tf:14`)
   - 最新の 5 イメージのみを保持
   - 古いイメージを自動削除してストレージコストを削減

#### 変数

| 変数 | 型 | デフォルト | 説明 |
|------|------|------------|------|
| `repository_name` | string | - | ECR リポジトリの名前 |
| `force_delete` | bool | `true` | イメージが含まれていても強制削除 |
| `tags` | map(string) | `{}` | リソースに適用するタグ |

#### 出力

- `repository_url`: ECR リポジトリの URL（イメージプッシュに使用）
- `repository_arn`: ECR リポジトリの ARN
- `repository_name`: ECR リポジトリの名前

### IAM モジュール

**場所**: `infrastructure/modules/iam/`

**目的**: Agent Runtime が必要な AWS サービスにアクセスするための IAM ロールとポリシーを管理します。

#### 主要リソース

1. **Trust Policy** (`infrastructure/modules/iam/main.tf:7`)
   - Bedrock AgentCore サービスが AssumeRole できるように設定
   - アカウント ID と ARN による条件付きアクセス制御

2. **Permissions Policy** (`infrastructure/modules/iam/main.tf:33`)
   以下の権限を付与：
   - **ECR 権限**: コンテナイメージの取得
   - **CloudWatch Logs 権限**: ログの記録
   - **Bedrock 権限**: モデルの呼び出し（オプション）
   - **カスタム権限**: 追加のポリシーステートメント（オプション）

#### 権限の詳細

**ECR 権限**:
```hcl
- ecr:GetAuthorizationToken          # ECR認証トークンの取得
- ecr:BatchGetImage                  # イメージの取得
- ecr:GetDownloadUrlForLayer         # レイヤーのダウンロード
- ecr:BatchCheckLayerAvailability    # レイヤーの可用性確認
```

**CloudWatch Logs 権限**:
```hcl
- logs:CreateLogGroup     # ロググループの作成
- logs:CreateLogStream    # ログストリームの作成
- logs:PutLogEvents       # ログイベントの送信
```

**Bedrock 権限**（オプション）:
```hcl
- bedrock:InvokeModel                      # モデルの呼び出し
- bedrock:InvokeModelWithResponseStream    # ストリーミングモデルの呼び出し
```

#### 変数

| 変数 | 型 | デフォルト | 説明 |
|------|------|------------|------|
| `role_name` | string | - | IAM ロールの名前 |
| `policy_name` | string | - | IAM ポリシーの名前 |
| `ecr_repository_arns` | list(string) | - | アクセス可能な ECR リポジトリの ARN リスト |
| `enable_bedrock_invoke` | bool | `true` | Bedrock モデル呼び出し権限を有効化 |
| `bedrock_model_arns` | list(string) | `[]` | 呼び出し可能な Bedrock モデルの ARN リスト |
| `additional_policy_statements` | list(object) | `[]` | 追加の IAM ポリシーステートメント |
| `tags` | map(string) | `{}` | リソースに適用するタグ |

#### 出力

- `role_arn`: IAM ロールの ARN
- `role_name`: IAM ロールの名前

### Agent Runtime モジュール

**場所**: `infrastructure/modules/agent_runtime/`

**目的**: エージェントのコンテナを実行し、外部からアクセス可能にするための Agent Runtime と Endpoint を管理します。

#### 主要リソース

1. **Agent Runtime** (`infrastructure/modules/agent_runtime/main.tf:3`)
   - コンテナイメージの URI を指定
   - IAM ロールを関連付け
   - 環境変数の設定
   - ネットワーク設定（PUBLIC または VPC）
   - プロトコル設定（HTTP）

2. **Agent Runtime Endpoint** (`infrastructure/modules/agent_runtime/main.tf:28`)
   - Agent Runtime への外部アクセスを提供
   - セッション管理とリクエストルーティング

#### 設定オプション

**ネットワーク設定**:
- `PUBLIC`: インターネットから直接アクセス可能（デフォルト）
- `VPC`: VPC 内からのみアクセス可能

**プロトコル設定**:
- `HTTP`: HTTP プロトコルを使用（デフォルト）

#### 変数

| 変数 | 型 | デフォルト | 説明 |
|------|------|------------|------|
| `agent_runtime_name` | string | - | Agent Runtime の名前（アンダースコアのみ使用可） |
| `description` | string | `""` | Agent Runtime の説明 |
| `role_arn` | string | - | Agent Runtime が使用する IAM ロールの ARN |
| `container_uri` | string | - | ECR 内のコンテナイメージの URI |
| `environment_variables` | map(string) | `{}` | コンテナの環境変数 |
| `network_mode` | string | `"PUBLIC"` | ネットワークモード（PUBLIC または VPC） |
| `server_protocol` | string | `"HTTP"` | サーバープロトコル |
| `create_endpoint` | bool | `true` | エンドポイントを作成するかどうか |
| `endpoint_name` | string | `""` | エンドポイントの名前（アンダースコアのみ使用可） |
| `endpoint_description` | string | `""` | エンドポイントの説明 |
| `tags` | map(string) | `{}` | リソースに適用するタグ |

#### 出力

- `agent_runtime_id`: Agent Runtime の ID
- `agent_runtime_arn`: Agent Runtime の ARN
- `agent_runtime_version`: Agent Runtime のバージョン
- `endpoint_arn`: Endpoint の ARN
- `workload_identity_arn`: Workload Identity の ARN

## 変数とカスタマイズ

### ルートレベルの変数

**場所**: `infrastructure/variables.tf`

| 変数 | 型 | デフォルト | 説明 |
|------|------|------------|------|
| `aws_region` | string | `"us-east-1"` | リソースをデプロイする AWS リージョン |
| `environment` | string | `"dev"` | 環境名（dev, staging, prod など） |
| `project_name` | string | `"agentcore-hands-on"` | プロジェクト名（リソース命名に使用） |
| `agent_name` | string | `"my-agent"` | エージェントの名前 |
| `container_image_uri` | string | `""` | コンテナイメージの URI（空の場合は ECR URL を使用） |
| `log_level` | string | `"INFO"` | エージェントのログレベル |

### 変数の設定方法

1. **terraform.tfvars ファイルを使用**（推奨）:
   ```hcl
   aws_region = "us-west-2"
   environment = "prod"
   project_name = "my-project"
   agent_name = "customer-support-agent"
   log_level = "DEBUG"
   ```

2. **コマンドライン引数**:
   ```bash
   terraform apply -var="agent_name=my-agent" -var="log_level=DEBUG"
   ```

3. **環境変数**:
   ```bash
   export TF_VAR_agent_name="my-agent"
   export TF_VAR_log_level="DEBUG"
   terraform apply
   ```

### デフォルトタグ

すべてのリソースには以下のタグが自動的に適用されます（`infrastructure/main.tf:21`）:

```hcl
default_tags {
  tags = {
    Project     = "agentcore-hands-on"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

## 出力値

**場所**: `infrastructure/outputs.tf`

Terraform の実行後、以下の情報が出力されます：

### 基本情報

- `region`: リソースがデプロイされた AWS リージョン
- `environment`: 環境名
- `project_name`: プロジェクト名

### ECR 関連

- `ecr_repository_url`: イメージをプッシュする際に使用する URL
- `ecr_repository_arn`: リポジトリの ARN
- `ecr_repository_name`: リポジトリの名前

### Agent Runtime 関連

- `agent_runtime_id`: エージェント呼び出し時に使用する ID
- `agent_runtime_arn`: Agent Runtime の ARN
- `agent_runtime_version`: Agent Runtime のバージョン
- `agent_runtime_endpoint_arn`: Endpoint の ARN
- `workload_identity_arn`: Workload Identity の ARN

### IAM 関連

- `agent_runtime_role_arn`: Agent Runtime が使用する IAM ロールの ARN
- `agent_runtime_role_name`: IAM ロールの名前

### Next Steps

- `next_steps`: デプロイ後の次のステップを示す詳細な手順

**出力の確認方法**:
```bash
# すべての出力を表示
terraform output

# 特定の出力を表示
terraform output ecr_repository_url
terraform output agent_runtime_id
```

## 命名規則

### リソース名のルール

Agent Runtime と Endpoint の名前には特別な制約があります（`infrastructure/main.tf:43-45`）:

- **使用可能**: アンダースコア (`_`)
- **使用不可**: ハイフン (`-`)

このため、プロジェクト名とエージェント名のハイフンは自動的にアンダースコアに変換されます：

```hcl
locals {
  # "agentcore-hands-on-my-agent-runtime" → "agentcore_hands_on_my_agent_runtime"
  agent_runtime_name = replace("${var.project_name}_${var.agent_name}_runtime", "-", "_")
  endpoint_name      = replace("${var.project_name}_${var.agent_name}_endpoint", "-", "_")
}
```

### リソース名のパターン

| リソースタイプ | 命名パターン | 例 |
|----------------|--------------|-----|
| ECR Repository | `{project_name}-{agent_name}` | `agentcore-hands-on-my-agent` |
| IAM Role | `{project_name}-agent-runtime-role` | `agentcore-hands-on-agent-runtime-role` |
| IAM Policy | `{project_name}-agent-runtime-policy` | `agentcore-hands-on-agent-runtime-policy` |
| Agent Runtime | `{project_name}_{agent_name}_runtime` | `agentcore_hands_on_my_agent_runtime` |
| Endpoint | `{project_name}_{agent_name}_endpoint` | `agentcore_hands_on_my_agent_endpoint` |

## モジュールの依存関係

モジュール間の依存関係は以下の通りです：

```
ecr → iam → agent_runtime
 ↓     ↓         ↓
 └─────┴─────────┘
```

1. **ECR モジュール**: 独立して作成可能
2. **IAM モジュール**: ECR の ARN を参照
3. **Agent Runtime モジュール**: ECR の URL と IAM の ARN を参照

Terraform が自動的にこれらの依存関係を解決し、正しい順序でリソースを作成します。

## セキュリティのベストプラクティス

1. **最小権限の原則**
   - IAM ポリシーは必要最小限の権限のみを付与
   - 特定のリソース ARN を指定（可能な場合）

2. **条件付きアクセス**
   - IAM ロールの AssumeRole ポリシーにアカウント ID と ARN の条件を設定
   - 不正なアクセスを防止

3. **イメージスキャン**
   - ECR でプッシュ時に自動イメージスキャンを有効化
   - 脆弱性を早期に検出

4. **ライフサイクル管理**
   - 古いイメージを自動削除
   - ストレージコストの削減と管理の簡素化

## カスタマイズ例

### VPC 内でのデプロイ

現在の実装は `PUBLIC` ネットワークモードを使用していますが、VPC 内にデプロイする場合は、`agent_runtime` モジュールに VPC 設定を追加する必要があります。

### 追加の IAM 権限

DynamoDB や S3 などの追加サービスへのアクセスが必要な場合：

```hcl
module "iam" {
  source = "./modules/iam"
  # ... 既存の設定 ...

  additional_policy_statements = [
    {
      sid    = "DynamoDBAccess"
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query"
      ]
      resources = ["arn:aws:dynamodb:us-east-1:123456789012:table/my-table"]
    }
  ]
}
```

### カスタム環境変数

エージェントに追加の環境変数を渡す場合：

```hcl
module "agent_runtime" {
  source = "./modules/agent_runtime"
  # ... 既存の設定 ...

  environment_variables = {
    LOG_LEVEL      = "DEBUG"
    ENVIRONMENT    = "production"
    API_ENDPOINT   = "https://api.example.com"
    MAX_RETRIES    = "3"
  }
}
```

## 関連ドキュメント

- [デプロイガイド](../DEPLOYMENT_GUIDE.md): インフラストラクチャのデプロイ手順
- [Terraform Docs](../terraform_docs/): 各リソースの詳細な Terraform ドキュメント
- [AWS Bedrock AgentCore ドキュメント](https://docs.aws.amazon.com/bedrock-agentcore/)