# AgentCore Observability セットアップガイド

## 概要

AWS Bedrock AgentCore Observabilityは、本番環境でエージェントのパフォーマンスを追跡、デバッグ、監視するためのサービスです。このガイドでは、Terraformを使用した設定方法を中心に、Observabilityの有効化手順を説明します。

## 前提条件

- Python 3.10以上
- AWS CLI設定済み
- Terraform 1.0以上
- `aws-opentelemetry-distro` (ADOT) ライブラリ（pyproject.tomlに既に含まれています）
- 適切なIAM権限（CloudWatch、X-Ray、Bedrock AgentCore）

## アーキテクチャ

```
AgentCore Runtime
  ↓ (OpenTelemetry)
CloudWatch Logs/Metrics
  ↓
CloudWatch Transaction Search (X-Ray)
  ↓
CloudWatch Dashboard
```

## セットアップ手順

### Step 1: CloudWatch Transaction Searchの有効化

CloudWatch Transaction Searchを有効化します。これは初回のみ約10分かかります。

#### 1.1 AWS CLIでの有効化

```bash
# リソースポリシーの設定
aws logs put-resource-policy \
  --policy-name AWSLogDeliveryWrite20150319 \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AWSLogDeliveryWrite",
        "Effect": "Allow",
        "Principal": {
          "Service": "delivery.logs.amazonaws.com"
        },
        "Action": [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "*"
      }
    ]
  }'

# Transaction Searchの有効化
aws cloudwatch update-trace-segment-destination \
  --arn arn:aws:logs:us-east-1:YOUR_ACCOUNT_ID:log-group:/aws/bedrock/agentcore/traces
```

**注意**: `YOUR_ACCOUNT_ID`は実際のAWSアカウントIDに置き換えてください。

#### 1.2 CloudWatch Consoleでの確認

1. CloudWatch Consoleにログイン
2. 左メニューから「Transaction Search」を選択
3. 「Enable Transaction Search」ボタンをクリック
4. 約10分待機

### Step 2: IAM権限の追加（Terraform）

AgentCore RuntimeのIAMロールにCloudWatchとX-Rayへのアクセス権限を追加します。

#### 2.1 `infrastructure/modules/iam/main.tf`の更新

現在のIAMポリシーに以下の権限を追加する必要があります：

```hcl
# CloudWatch Logs & X-Rayの権限を追加
data "aws_iam_policy_document" "observability" {
  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/bedrock-agentcore/runtimes/*"
    ]
  }

  statement {
    sid = "XRayAccess"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords"
    ]
    resources = ["*"]
  }

  statement {
    sid = "CloudWatchMetrics"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["bedrock-agentcore"]
    }
  }
}
```

#### 2.2 新しい変数の追加

`infrastructure/modules/iam/variables.tf`に追加：

```hcl
variable "enable_observability" {
  description = "Enable CloudWatch observability for agent runtime"
  type        = bool
  default     = false
}
```

### Step 3: Agent Runtimeの環境変数設定（Terraform）

#### 3.1 `infrastructure/modules/agent_runtime/variables.tf`に追加

```hcl
variable "enable_observability" {
  description = "Enable observability for the agent runtime"
  type        = bool
  default     = false
}

variable "agent_name" {
  description = "Name of the agent (for observability tagging)"
  type        = string
  default     = ""
}
```

#### 3.2 `infrastructure/modules/agent_runtime/main.tf`の更新

環境変数ブロックを動的に設定：

```hcl
resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = var.agent_runtime_name
  description        = var.description
  role_arn           = var.role_arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_uri
    }
  }

  # Observability環境変数を含む
  environment_variables = merge(
    var.environment_variables,
    var.enable_observability ? {
      # AgentCore Observabilityの有効化
      AGENT_OBSERVABILITY_ENABLED            = "true"

      # OpenTelemetry基本設定
      OTEL_PYTHON_DISTRO                     = "aws_distro"
      OTEL_PYTHON_CONFIGURATOR               = "aws_configurator"

      # リソース属性（サービス名、ロググループ、リソースID）
      OTEL_RESOURCE_ATTRIBUTES               = "service.name=${var.agent_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id},cloud.resource_id=${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}"

      # OTLPエクスポーター設定（ロググループ、ログストリーム、メトリクスネームスペース）
      OTEL_EXPORTER_OTLP_LOGS_HEADERS        = "x-aws-log-group=/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id},x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore"

      # プロトコルとエクスポーター設定
      OTEL_EXPORTER_OTLP_PROTOCOL            = "http/protobuf"
      OTEL_TRACES_EXPORTER                   = "otlp"
    } : {}
  )

  network_configuration {
    network_mode = var.network_mode
  }

  protocol_configuration {
    server_protocol = var.server_protocol
  }

  tags = var.tags
}
```

#### 3.3 `infrastructure/main.tf`の更新

```hcl
# Agent Runtime Module
module "agent_runtime" {
  source = "./modules/agent_runtime"

  agent_runtime_name    = local.agent_runtime_name
  description           = "Agent runtime for ${var.agent_name}"
  role_arn              = module.iam.role_arn
  container_uri         = var.container_image_uri != "" ? var.container_image_uri : "${module.ecr.repository_url}:${var.image_tag}"

  # Observabilityを有効化
  enable_observability  = true
  agent_name            = var.agent_name

  environment_variables = {
    LOG_LEVEL   = var.log_level
    ENVIRONMENT = var.environment
  }

  network_mode    = "PUBLIC"
  server_protocol = "HTTP"

  create_endpoint      = false
  endpoint_name        = ""
  endpoint_description = ""

  tags = local.common_tags
}
```

### Step 4: 環境変数の詳細説明

上記のTerraform設定で自動的に設定される環境変数について説明します。

#### 4.1 必須環境変数の詳細

| 環境変数 | 値 | 説明 |
|---------|-----|------|
| `AGENT_OBSERVABILITY_ENABLED` | `true` | AgentCore Observabilityの有効化フラグ |
| `OTEL_PYTHON_DISTRO` | `aws_distro` | AWS Distro for OpenTelemetryを使用 |
| `OTEL_PYTHON_CONFIGURATOR` | `aws_configurator` | AWS固有の設定を自動適用 |
| `OTEL_RESOURCE_ATTRIBUTES` | `service.name=<agent-name>,aws.log.group.names=/aws/bedrock-agentcore/runtimes/<runtime-id>,cloud.resource_id=<runtime-id>` | サービス名、ロググループ名、リソースIDを指定 |
| `OTEL_EXPORTER_OTLP_LOGS_HEADERS` | `x-aws-log-group=/aws/bedrock-agentcore/runtimes/<runtime-id>,x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore` | CloudWatch Logsのロググループ、ログストリーム、メトリクスネームスペースを指定 |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` | OTLPプロトコルの形式 |
| `OTEL_TRACES_EXPORTER` | `otlp` | トレースのエクスポーター |

**重要**: `<runtime-id>`は`aws_bedrockagentcore_agent_runtime.main.agent_runtime_id`で自動的に解決されます。

#### 4.2 依存関係の確認

`pyproject.toml`で既に設定済み：

```toml
dependencies = [
    "aws-opentelemetry-distro>=0.10.0",
    # ... その他
]
```

#### 4.3 アプリケーションコードの準備

環境変数が正しく設定されていれば、**自動的に計装されます**。追加のコード変更は不要です。

```python
# src/agentcore_hands_on/main.py
from fastapi import FastAPI

# 以下の環境変数が設定されていれば自動計装される:
# - AGENT_OBSERVABILITY_ENABLED=true
# - OTEL_PYTHON_DISTRO=aws_distro
# - OTEL_PYTHON_CONFIGURATOR=aws_configurator

app = FastAPI()

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

# ログ、メトリクス、トレースは自動的に収集され、
# CloudWatchに送信されます
```

### Step 5: Dockerfileの更新（オプション）

OpenTelemetryの自動計装を有効にする場合：

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# 依存関係のインストール
COPY pyproject.toml uv.lock ./
RUN pip install uv && \
    uv sync --frozen --no-dev

# アプリケーションコードのコピー
COPY src ./src

# OpenTelemetry自動計装の起動
CMD ["opentelemetry-instrument", "uvicorn", "agentcore_hands_on.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Step 6: デプロイ

#### 6.1 Terraformでのデプロイ

```bash
cd infrastructure

# 初期化（初回のみ）
terraform init

# プラン確認
terraform plan

# 適用
terraform apply
```

#### 6.2 Dockerイメージのビルドとプッシュ

```bash
# ビルドとプッシュスクリプトの実行
./scripts/build_and_push.sh
```

### Step 7: CloudWatchでの確認

#### 7.1 CloudWatch Logsの確認

1. CloudWatch Consoleを開く
2. 「Log groups」から`/aws/bedrock-agentcore/runtimes/`で始まるロググループを探す
3. ログストリーム`runtime-logs`を確認

#### 7.2 CloudWatch Metricsの確認

1. CloudWatch Consoleの「Metrics」を開く
2. 「bedrock-agentcore」ネームスペースを選択
3. 以下のメトリクスが確認できます：
   - Request count
   - Latency
   - Error rate
   - Token usage（モデル呼び出しがある場合）

#### 7.3 Transaction Searchの確認

1. CloudWatch Consoleの「Transaction Search」を開く
2. トレースIDやサービス名でフィルタリング
3. エンドツーエンドのトレースを確認

#### 7.4 CloudWatch Dashboardの作成（推奨）

```bash
# ダッシュボードのサンプルJSONを適用
aws cloudwatch put-dashboard \
  --dashboard-name AgentCoreObservability \
  --dashboard-body file://dashboard.json
```

## トラブルシューティング

### ログが表示されない

1. IAM権限を確認
   ```bash
   aws iam get-role-policy --role-name your-role-name --policy-name your-policy-name
   ```

2. 環境変数を確認
   ```bash
   # Agent Runtimeの環境変数を確認
   terraform state show module.agent_runtime.aws_bedrockagentcore_agent_runtime.main
   ```

3. CloudWatch Logs Insightsでクエリ
   ```
   fields @timestamp, @message
   | filter @message like /ERROR/
   | sort @timestamp desc
   | limit 20
   ```

### メトリクスが表示されない

1. `OTEL_METRICS_EXPORTER=otlp`が設定されているか確認
2. CloudWatchのネームスペース`bedrock-agentcore`を確認
3. IAMロールに`cloudwatch:PutMetricData`権限があるか確認

### トレースが表示されない

1. CloudWatch Transaction Searchが有効化されているか確認
2. X-Ray権限（`xray:PutTraceSegments`）があるか確認
3. `OTEL_TRACES_EXPORTER=otlp`が設定されているか確認

## ベストプラクティス

1. **ログレベルの設定**: 本番環境では`LOG_LEVEL=INFO`、デバッグ時は`DEBUG`
2. **サンプリング**: 高トラフィック環境では`OTEL_TRACES_SAMPLER=parentbased_traceidratio`でサンプリング率を調整
3. **アラート設定**: CloudWatch Alarmsでエラー率やレイテンシーの閾値を設定
4. **コスト最適化**: 不要なログは出力しない、ログ保持期間を適切に設定

## 参考リンク

- [AWS Bedrock AgentCore Observability公式ドキュメント](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-get-started.html)
- [OpenTelemetry Python](https://opentelemetry.io/docs/languages/python/)
- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)
- [Terraform AWS Provider Issue #44742](https://github.com/hashicorp/terraform-provider-aws/issues/44742)

## 次のステップ

1. カスタムメトリクスの追加
2. 分散トレーシングの詳細分析
3. CloudWatch Dashboardのカスタマイズ
4. アラートとSNS通知の設定
5. ログベースメトリクスの作成
