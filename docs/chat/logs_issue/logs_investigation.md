# AgentCore Memory ログ出力量が少ない問題の調査

## 問題の概要

AgentCore Runtime (`agentcore_hands_on_my_agent_runtime`) のCloudWatchログ出力量が、参考実装の `medurance_agent` と比較して極端に少ない。

## 現状の確認

### CloudWatch ログストレージ比較

| Runtime | ログサイズ | 比率 |
|---------|-----------|------|
| agentcore_hands_on | 144,600 bytes (約141 KB) | 1x |
| medurance_agent | 19,344,041 bytes (約18.4 MB) | 約130倍 |

### ログストリームの違い

**agentcore_hands_on:**
```
- otel-rt-logs (lastEventTime: None, storedBytes: 0)
```

**medurance_agent:**
```
- otel-rt-logs
- 2025/10/20/[runtime-logs]274bdf01-9a87-47ec-93be-4cb31b19cbfe
- 2025/10/20/[runtime-logs]e6d87e52-7c5f-48e0-8818-5688bb8d2aa9
- 2025/10/20/[runtime-logs]11654437-0a23-42ac-8c8d-0ce4ead58cfe
- 2025/10/20/[runtime-logs]2327cabf-3d22-4050-88e0-19a039b1522d
```

**重要な違い**: `medurance_agent` には日付ベースの `runtime-logs` ログストリームが複数存在するが、`agentcore_hands_on` には存在しない。

## 原因分析

### 1. IAM権限の不足（最も可能性が高い）

**現在のファイル:** `infrastructure/modules/iam/main.tf` (Line 25-157)

AWS公式ドキュメントと現在の実装(`main.tf`)を詳細に比較した結果、以下の権限が不足していることが判明：

#### 不足している権限の詳細比較

##### a. CloudWatch Logs関連（部分的に不足）

**現在の実装 (main.tf:48-60):**
```hcl
statement {
  sid    = "CloudWatchLogs"
  effect = "Allow"
  actions = [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
    "logs:DescribeLogStreams"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*"
  ]
}
```

**AWS公式推奨との差分:**

1. ❌ **logs:DescribeLogGroups が欠落**
   ```json
   {
       "Effect": "Allow",
       "Action": ["logs:DescribeLogGroups"],
       "Resource": ["arn:aws:logs:us-east-1:123456789012:log-group:*"]
   }
   ```

2. ❌ **ログストリームレベルの明示的なResource指定が欠落**
   ```json
   {
       "Effect": "Allow",
       "Action": [
           "logs:CreateLogStream",
           "logs:PutLogEvents"
       ],
       "Resource": [
           "arn:aws:logs:us-east-1:123456789012:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"
       ]
   }
   ```

**影響:**
- OpenTelemetryがログループの存在確認に失敗
- ログストリームへの書き込み権限が曖昧で、送信が制限される可能性

##### b. X-Ray関連（重要な権限が欠落）

**現在の実装 (main.tf:63-71):**
```hcl
statement {
  sid    = "XRayAccess"
  effect = "Allow"
  actions = [
    "xray:PutTraceSegments",
    "xray:PutTelemetryRecords"
  ]
  resources = ["*"]
}
```

**AWS公式推奨との差分:**

❌ **サンプリング関連の2つの権限が欠落:**
```json
{
    "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",      // ❌ 欠落
        "xray:GetSamplingTargets"     // ❌ 欠落
    ],
    "Resource": "*"
}
```

**影響:**
- X-Rayサンプリング設定を取得できない
- OpenTelemetryが適切なトレース/ログサンプリングを実行できず、ログ送信が制限される
- **これが主要な原因の可能性が高い**

##### c. Workload Identity関連（完全に欠落）★最重要★

**現在の実装:**
❌ **該当するstatementが存在しない**

**AWS公式推奨（完全に不足）:**
```json
{
    "Sid": "GetAgentAccessToken",
    "Effect": "Allow",
    "Action": [
        "bedrock-agentcore:GetWorkloadAccessToken",
        "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
        "bedrock-agentcore:GetWorkloadAccessTokenForUserId"
    ],
    "Resource": [
        "arn:aws:bedrock-agentcore:us-east-1:123456789012:workload-identity-directory/default",
        "arn:aws:bedrock-agentcore:us-east-1:123456789012:workload-identity-directory/default/workload-identity/agentName-*"
    ]
}
```

**影響:**
- AgentCore Runtimeがワークロード認証トークンを取得できない
- 認証エラーによりCloudWatch Logsへのログ送信が完全に失敗
- **これがログが出ない最大の原因である可能性が極めて高い**

##### d. 既に実装されている権限（問題なし）

以下は既に正しく実装されており、問題ありません：

✅ ECR関連 (main.tf:27-45)
✅ CloudWatch Metrics (main.tf:74-86)
✅ Bedrock Model Invocation (main.tf:89-100)
✅ Code Interpreter (main.tf:103-112)
✅ Browser (main.tf:115-126)
✅ Memory (main.tf:129-145)

### 2. OpenTelemetry設定

#### 現在の設定（main.tf）

```hcl
environment_variables = {
  AGENT_OBSERVABILITY_ENABLED = "true"
  OTEL_PYTHON_DISTRO       = "aws_distro"
  OTEL_PYTHON_CONFIGURATOR = "aws_configurator"

  OTEL_RESOURCE_ATTRIBUTES = "service.name=my-agent,aws.log.group.names=/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr,cloud.resource_id=agentcore_hands_on_my_agent_runtime-VNBQgh67mr"

  OTEL_EXPORTER_OTLP_LOGS_HEADERS = "x-aws-log-group=/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr,x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore"

  OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
  OTEL_TRACES_EXPORTER        = "otlp"
  OTEL_TRACES_SAMPLER = "always_on"
}
```

**評価:**
- OpenTelemetry環境変数は適切に設定されている
- `aws-opentelemetry-distro>=0.12.1` が pyproject.toml に含まれている
- Dockerfile で `opentelemetry-instrument` を使用している

**問題点:**
- 設定自体は正しいが、IAM権限不足により実際のログ送信が失敗している可能性

### 3. 信頼ポリシーの確認

**現在の実装:**
```json
{
    "Effect": "Allow",
    "Principal": {
        "Service": "bedrock-agentcore.amazonaws.com"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
        "StringEquals": {
            "aws:SourceAccount": "239339588912"
        }
    }
}
```

**AWS公式推奨:**
```json
{
    "Effect": "Allow",
    "Principal": {
        "Service": "bedrock-agentcore.amazonaws.com"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
        "StringEquals": {
            "aws:SourceAccount": "123456789012"
        },
        "ArnLike": {
            "aws:SourceArn": "arn:aws:bedrock-agentcore:us-east-1:123456789012:*"
        }
    }
}
```

**問題点:**
- `aws:SourceArn` の条件が欠落
- セキュリティベストプラクティスではあるが、ログ出力量には直接影響しない可能性が高い

## 優先順位付きの修正提案

### 🔴 優先度: 高（即座に修正が必要）

#### 1. X-Ray サンプリング権限の追加

**ファイル:** `infrastructure/modules/iam/main.tf`

**修正箇所:**
```hcl
# X-Ray permissions for Observability
statement {
  sid    = "XRayAccess"
  effect = "Allow"
  actions = [
    "xray:PutTraceSegments",
    "xray:PutTelemetryRecords",
    "xray:GetSamplingRules",      # 追加
    "xray:GetSamplingTargets"     # 追加
  ]
  resources = ["*"]
}
```

**理由:** OpenTelemetryがサンプリング設定を取得できないため、ログ送信が制限されている可能性が高い。

#### 2. Workload Identity Token取得権限の追加

**ファイル:** `infrastructure/modules/iam/main.tf`

**新規追加:**
```hcl
# Workload Identity Token permissions
statement {
  sid    = "GetAgentAccessToken"
  effect = "Allow"
  actions = [
    "bedrock-agentcore:GetWorkloadAccessToken",
    "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
    "bedrock-agentcore:GetWorkloadAccessTokenForUserId"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/${local.agent_runtime_name}-*"
  ]
}
```

**理由:** この権限が完全に欠落しており、認証エラーによりログ送信が失敗している可能性が最も高い。

### 🟡 優先度: 中（推奨される修正）

#### 3. CloudWatch Logs権限の詳細化

**ファイル:** `infrastructure/modules/iam/main.tf`

**修正案:**

現在の単一のstatementを、AWS公式推奨の複数statementに分割：

```hcl
# CloudWatch Logs - Log Group operations
statement {
  sid    = "CloudWatchLogsGroup"
  effect = "Allow"
  actions = [
    "logs:DescribeLogStreams",
    "logs:CreateLogGroup"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"
  ]
}

# CloudWatch Logs - Describe all groups
statement {
  sid    = "CloudWatchLogsDescribeGroups"
  effect = "Allow"
  actions = [
    "logs:DescribeLogGroups"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"
  ]
}

# CloudWatch Logs - Log Stream operations
statement {
  sid    = "CloudWatchLogsStream"
  effect = "Allow"
  actions = [
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"
  ]
}
```

**理由:**
- ログストリームレベルの明示的な権限により、ログ送信の信頼性が向上
- `logs:DescribeLogGroups` により、OpenTelemetryがログループの存在確認を正しく行える

### 🟢 優先度: 低（セキュリティベストプラクティス）

#### 4. 信頼ポリシーにSourceArnを追加

**ファイル:** `infrastructure/modules/iam/main.tf`

**修正箇所:**
```hcl
data "aws_iam_policy_document" "agent_runtime_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    # 追加
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [
        "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"
      ]
    }
  }
}
```

**理由:** セキュリティベストプラクティスだが、ログ出力量への直接的な影響は低い。

## 検証手順

修正適用後、以下の手順で効果を確認：

### 1. Terraform Apply

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

### 2. Runtime の再起動

IAM権限の変更後、Runtimeを再起動して変更を反映：

```bash
# Runtime情報を取得
aws bedrock-agentcore list-agent-runtimes --region us-east-1

# Runtimeの更新（新しいバージョン作成により自動的に再起動される）
# または、新しいコンテナイメージをプッシュしてRuntimeを更新
```

### 3. ログの確認

```bash
# ログストリームの確認
aws logs describe-log-streams \
  --log-group-name "/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT" \
  --order-by LastEventTime \
  --descending \
  --max-items 10

# 最新ログの取得
aws logs tail "/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT" \
  --follow
```

### 4. エージェントの実行テスト

```bash
export AWS_PROFILE=239339588912_AdministratorAccess
uv run python -m agentcore_hands_on.invoke_agent \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "Test logging functionality" \
  --session-id "logging-test-session-xxxxxxxxxxxxxxx" \
  --actor-id "test-user"
```

### 5. ログサイズの比較

```bash
# 修正前後のログサイズを比較
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/bedrock-agentcore/runtimes/" \
  --query 'logGroups[*].[logGroupName,storedBytes]' \
  --output table
```

## 期待される結果

修正後、以下の改善が期待される：

1. **ログストリームの増加**: 日付ベースの `runtime-logs` ログストリームが生成される
2. **ログサイズの増加**: `medurance_agent` と同等レベルのログ出力量（MB単位）
3. **詳細なトレース情報**: X-Rayトレースが正しく記録される
4. **Memory動作ログ**: Memory strategyの動作ログが可視化される

## 追加調査項目

修正後もログが少ない場合、以下を確認：

### 1. GenAI Observability の有効化確認

CloudWatch コンソールで "Enable Transaction Search" が有効化されているか確認：
- CloudWatch Console → GenAI Observability → Enable Transaction Search

### 2. OpenTelemetry Collector のログ確認

コンテナ内でOpenTelemetryのログを確認：

```bash
# ECS/Fargate の場合
aws logs get-log-events \
  --log-group-name "/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT" \
  --log-stream-name "otel-rt-logs" \
  --start-from-head
```

### 3. アプリケーションログレベルの確認

`LOG_LEVEL` 環境変数が適切に設定されているか確認：
- 現在: `INFO`
- デバッグ時: `DEBUG` に変更して詳細ログを出力

## 参考資料

- [AgentCore Runtime Permissions - AWS Official](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-permissions.html)
- [Runtime Troubleshooting - Missing CloudWatch Logs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-troubleshooting.html#missing-cloudwatch-logs)
- [Amazon Bedrock AgentCore Observability (classmethod.jp)](https://dev.classmethod.jp/articles/amazon-bedrock-agentcore-observability-genai-observability/)
- [AWS OpenTelemetry Python SDK](https://aws-otel.github.io/docs/getting-started/python-sdk)

## 結論

**最も可能性が高い原因:**
1. **Workload Identity Token取得権限の完全欠落** → 認証エラーでログ送信失敗
2. **X-Rayサンプリング権限の欠落** → サンプリング設定取得失敗でトレース送信制限

**推奨される対応:**
優先度「高」の2つの権限（GetAgentAccessToken、X-Rayサンプリング）を即座に追加し、Runtimeを再起動して効果を確認する。
