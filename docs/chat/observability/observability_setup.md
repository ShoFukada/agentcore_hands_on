# AgentCore Runtime の Observability を有効にする方法

## 概要

AWS Bedrock AgentCore の Observability 機能を使用すると、エージェントのトレース、デバッグ、パフォーマンス監視が可能になります。このドキュメントでは、現在の Terraform 構成で Observability を有効にする方法を説明します。

## 重要な注意事項

**現時点（2025年1月）では、Terraform の `aws_bedrockagentcore_agent_runtime` リソースに `observability` ブロックはサポートされていません。**

関連 Issue: https://github.com/hashicorp/terraform-provider-aws/issues/44742

そのため、Observability を有効にするには以下の2つのアプローチがあります：
1. **手動で環境変数を設定する**（一時的な回避策）
2. **AWS CLI/API で設定する**（推奨）

## 前提条件

### 1. CloudWatch Transaction Search を有効化

**アカウントごとに1回のみ実行**が必要です。

#### Option A: AWS CLI で有効化

```bash
# 1. CloudWatch Logs にスパンを取り込むポリシーを作成
aws logs put-resource-policy \
  --policy-name MyResourcePolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "TransactionSearchXRayAccess",
        "Effect": "Allow",
        "Principal": {
          "Service": "xray.amazonaws.com"
        },
        "Action": "logs:PutLogEvents",
        "Resource": [
          "arn:aws:logs:us-east-1:YOUR-ACCOUNT-ID:log-group:aws/spans:*",
          "arn:aws:logs:us-east-1:YOUR-ACCOUNT-ID:log-group:/aws/application-signals/data:*"
        ],
        "Condition": {
          "ArnLike": {
            "aws:SourceArn": "arn:aws:xray:us-east-1:YOUR-ACCOUNT-ID:*"
          },
          "StringEquals": {
            "aws:SourceAccount": "YOUR-ACCOUNT-ID"
          }
        }
      }
    ]
  }'

# 2. トレースセグメントの送信先を CloudWatch Logs に設定
aws xray update-trace-segment-destination \
  --destination CloudWatchLogs \
  --region us-east-1

# 3. (オプション) スパンのサンプリング率を設定（例: 1%）
aws xray update-indexing-rule \
  --name "Default" \
  --rule '{"Probabilistic": {"DesiredSamplingPercentage": 1}}' \
  --region us-east-1
```

#### Option B: CloudWatch コンソールで有効化

1. CloudWatch コンソール (https://console.aws.amazon.com/cloudwatch/) を開く
2. ナビゲーションペインで **Application Signals** > **Transaction Search** を選択
3. **Enable Transaction Search** をクリック
4. スパンを構造化ログとして取り込むボックスを選択し、インデックス化するスパンの割合を入力（無料で1%まで）

## 現在の制限と回避策

### Terraform では直接サポートされていない

現在の `infrastructure/modules/agent_runtime/main.tf` では、以下のような `observability` ブロックは**まだサポートされていません**：

```hcl
# ❌ 現時点では動作しません
resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = var.agent_runtime_name

  # この observability ブロックは未サポート
  observability {
    enable = true
  }
}
```

### 回避策: 環境変数で設定

Agent Runtime が作成された後、以下の環境変数を追加する必要があります：

```bash
# Agent Runtime の環境変数に以下を追加
AGENT_OBSERVABILITY_ENABLED=true
OTEL_PYTHON_DISTRO=aws_distro
OTEL_PYTHON_CONFIGURATOR=aws_configurator
OTEL_RESOURCE_ATTRIBUTES=service.name=<agent-name>,aws.log.group.names=/aws/bedrock-agentcore/runtimes/<agent-id>
OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=/aws/bedrock-agentcore/runtimes/<agent-id>,x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_EXPORTER=otlp
```

**問題点**: これらの環境変数には Agent Runtime ID が必要ですが、Runtime が作成されるまで ID は分かりません。

### 推奨される手動設定手順

1. **Terraform で Agent Runtime を作成**（現在のまま）

```bash
cd infrastructure
terraform apply
```

2. **Agent Runtime ID を取得**

```bash
RUNTIME_ID=$(terraform output -raw agent_runtime_id)
echo "Runtime ID: ${RUNTIME_ID}"
```

3. **AWS Console または AWS CLI で環境変数を更新**

現時点では、AWS Console から手動で環境変数を追加するか、AWS CLI で `update-agent-runtime` を実行する必要があります。

```bash
# ⚠️ 注意: この API はまだ完全にサポートされていない可能性があります
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id "${RUNTIME_ID}" \
  --environment-variables \
    AGENT_OBSERVABILITY_ENABLED=true \
    OTEL_PYTHON_DISTRO=aws_distro \
    OTEL_PYTHON_CONFIGURATOR=aws_configurator \
    OTEL_RESOURCE_ATTRIBUTES="service.name=my-agent,aws.log.group.names=/aws/bedrock-agentcore/runtimes/${RUNTIME_ID}" \
    OTEL_EXPORTER_OTLP_LOGS_HEADERS="x-aws-log-group=/aws/bedrock-agentcore/runtimes/${RUNTIME_ID},x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore" \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
    OTEL_TRACES_EXPORTER=otlp
```

## Observability データの確認

### CloudWatch での確認

#### 1. ログの確認

```bash
# Runtime のログを確認
aws logs tail "/aws/bedrock-agentcore/runtimes/${RUNTIME_ID}" \
  --follow \
  --region us-east-1
```

ログの場所:
- 標準ログ: `/aws/bedrock-agentcore/runtimes/<agent_id>-<endpoint_name>/[runtime-logs] <UUID>`
- OTEL 構造化ログ: `/aws/bedrock-agentcore/runtimes/<agent_id>-<endpoint_name>/runtime-logs`

#### 2. トレースとスパンの確認

1. CloudWatch コンソールを開く
2. **Transaction Search** を選択
3. スパンの場所: `/aws/spans/default`
4. サービス名やその他の条件でフィルタリング
5. トレースを選択して詳細な実行グラフを表示

#### 3. メトリクスの確認

1. CloudWatch コンソールを開く
2. **Metrics** を選択
3. `bedrock-agentcore` ネームスペースを参照

#### 4. GenAI Observability ダッシュボード

1. CloudWatch コンソールで **GenAI Observability** を開く
2. **Bedrock AgentCore** タブを選択
3. 以下のビューを確認:
   - **Agents View**: すべてのエージェントのリスト
   - **Sessions View**: エージェントに関連するすべてのセッション
   - **Trace View**: トレースとスパン情報

## 今後の対応

Terraform Provider の Issue #44742 が解決されると、以下のような構成が可能になる予定です：

```hcl
resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = var.agent_runtime_name

  observability {
    enable = true
  }
}
```

この機能が追加されるまでは、上記の回避策を使用する必要があります。

## ベストプラクティス

1. **シンプルから始める**: デフォルトの Observability で大部分の重要なメトリクス（モデル呼び出し、トークン使用量、ツール実行）が自動的にキャプチャされます

2. **開発段階に応じて設定**: 開発フェーズに合わせて Observability 設定を調整します

3. **一貫した命名規則**: サービス、スパン、属性に対して最初から命名規則を確立します

4. **機密データのフィルタリング**: Observability 属性とペイロードから機密情報が漏洩しないようにフィルタリングします

5. **アラートの設定**: CloudWatch アラームを設定して、ユーザーに影響を与える前に潜在的な問題を通知します

## 参考リンク

- [AWS Documentation: Get started with AgentCore Observability](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-get-started.html)
- [Terraform Provider Issue #44742](https://github.com/hashicorp/terraform-provider-aws/issues/44742)
- [CloudWatch Transaction Search](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search.html)
