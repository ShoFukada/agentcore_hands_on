# AgentCore Observability セットアップ手順

## 前提条件
- Agent Runtime が既にデプロイ済み
- AWS CLI と Terraform がインストール済み
- AWS 認証情報が設定済み

## 手順

### 1. CloudWatch Transaction Search の有効化

CloudWatch Console で Transaction Search を有効化します。

#### CloudWatch Console での手順:

1. CloudWatch Console にログイン
2. 左メニューから「Transaction Search」を選択
3. 「Enable Transaction Search」ボタンをクリック
4. 「Ingest spans as structured logs」をチェック
5. X-Ray trace indexing は 1% のまま（デフォルト）
6. 約10分待機

### 2. Agent Runtime ID の取得

既にデプロイ済みの Agent Runtime の ID を取得します。

```bash
# infrastructure ディレクトリに移動
cd infrastructure

# AWS プロファイルを設定
export AWS_PROFILE=239339588912_AdministratorAccess

# Terraform outputs から取得
terraform output agent_runtime_id
```

**取得した値の例**: `agentcore_hands_on_my_agent_runtime-VNBQgh67mr`

### 3. IAM ロールに Observability 権限を追加

`infrastructure/modules/iam/main.tf` を編集して、以下の権限を追加します:
- CloudWatch Logs: `logs:DescribeLogStreams`
- X-Ray: `xray:PutTraceSegments`, `xray:PutTelemetryRecords`
- CloudWatch Metrics: `cloudwatch:PutMetricData` (namespace 条件付き)

### 4. Terraform 変数の設定

#### 4-1. variables.tf に変数を追加

`infrastructure/variables.tf` に `agent_runtime_id` 変数を追加します。

#### 4-2. terraform.tfvars に runtime ID を設定

`infrastructure/terraform.tfvars` を編集:

```hcl
aws_region        = "us-east-1"
environment       = "dev"
project_name      = "agentcore-hands-on"
agent_name        = "my-agent"
image_tag         = "v1.0.2"
agent_runtime_id  = "agentcore_hands_on_my_agent_runtime-VNBQgh67mr"  # 手順2で取得した値
```

### 5. main.tf の環境変数を更新

`infrastructure/main.tf` の `environment_variables` に Observability 設定を追加します。
tfvars から `var.agent_runtime_id` を参照する形で設定します。

### 6. Terraform でデプロイ

```bash
# AWS プロファイルを設定
export AWS_PROFILE=239339588912_AdministratorAccess

# プランの確認
terraform plan

# 適用
terraform apply
```


## 参考リンク
- [AWS Bedrock AgentCore Observability](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-get-started.html)
- [Terraform AWS Provider Issue #44742](https://github.com/hashicorp/terraform-provider-aws/issues/44742)
