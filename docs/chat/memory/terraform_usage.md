# AgentCore Memory Terraform 使い方

## 概要

TerraformでAgentCore Memoryを構築するための完全なガイドです。

## 構成

### モジュール構造

```
infrastructure/
├── main.tf
├── variables.tf
├── outputs.tf
├── example.tfvars
└── modules/
    ├── iam/          # Memory実行ロール + Runtime Memory権限
    └── memory/       # Memory本体 + Strategies
```

## 1. 設定ファイルの準備

### terraform.tfvars または example.tfvars

```hcl
# 基本設定
aws_region       = "us-east-1"
environment      = "dev"
project_name     = "agentcore-hands-on"
agent_name       = "my-agent"

# Memory configuration
enable_memory                  = true
memory_retention_days          = 90  # Short-term Memoryの保持期間（日）
memory_enable_semantic         = true
memory_enable_user_preference  = true
memory_enable_summarization    = true
```

### パラメータ詳細

| パラメータ | 説明 | デフォルト |
|-----------|------|-----------|
| `enable_memory` | Memory機能の有効化 | `false` |
| `memory_retention_days` | Short-term Memoryの保持期間（日） | `90` |
| `memory_enable_semantic` | SEMANTIC戦略を有効化 | `true` |
| `memory_enable_user_preference` | USER_PREFERENCE戦略を有効化 | `true` |
| `memory_enable_summarization` | SUMMARIZATION戦略を有効化 | `true` |

## 2. デプロイ

### 初回デプロイ

```bash
cd infrastructure

# 初期化
terraform init

# プラン確認
terraform plan

# 適用
terraform apply
```

### Memory IDの取得

デプロイ後、Memory IDを取得して`.env`に追加：

```bash
# Memory IDを表示
terraform output memory_id

# .envに追加
echo "MEMORY_ID=$(terraform output -raw memory_id)" >> ../.env
```

## 3. 作成されるリソース

### IAMリソース

#### 1. Memory実行ロール

Memory自体がBedrockモデルを呼び出すために使用：

```hcl
resource "aws_iam_role" "memory_execution"
  # AWS管理ポリシーをアタッチ
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
```

**権限:**
- `bedrock:InvokeModel`
- `bedrock:InvokeModelWithResponseStream`

#### 2. Runtime用Memory権限

Agent RuntimeがMemoryにアクセスするための権限：

```hcl
# agent_runtime_permissions に追加
actions = [
  "bedrock-agentcore:GetMemory",
  "bedrock-agentcore:CreateEvent",
  "bedrock-agentcore:RetrieveMemoryRecords",
  "bedrock-agentcore:GetMemoryRecord",
  "bedrock-agentcore:ListMemoryRecords",
  "bedrock-agentcore:BatchCreateMemoryRecords"
]
```

### Memoryリソース

#### 1. Memory本体

```hcl
resource "aws_bedrockagentcore_memory" "this"
  name                      = "agentcore_hands_on_my_agent_memory"
  event_expiry_duration     = 90  # 日数
  memory_execution_role_arn = <Memory実行ロールARN>
```

#### 2. SEMANTIC Strategy

知識抽出戦略：

```hcl
resource "aws_bedrockagentcore_memory_strategy" "semantic"
  type        = "SEMANTIC"
  namespaces  = ["agentcore-hands-on/knowledge/{actorId}"]
```

#### 3. USER_PREFERENCE Strategy

ユーザー好み記録戦略：

```hcl
resource "aws_bedrockagentcore_memory_strategy" "user_preference"
  type        = "USER_PREFERENCE"
  namespaces  = ["agentcore-hands-on/preferences/{actorId}"]
```

#### 4. SUMMARIZATION Strategy

要約生成戦略：

```hcl
resource "aws_bedrockagentcore_memory_strategy" "summarization"
  type        = "SUMMARIZATION"
  namespaces  = ["agentcore-hands-on/summaries/{actorId}/{sessionId}"]
```

## 4. Outputs

デプロイ後、以下の情報が出力されます：

```bash
# Memory関連
terraform output memory_id
terraform output memory_arn
terraform output memory_name

# Strategy関連
terraform output semantic_strategy_id
terraform output user_preference_strategy_id
terraform output summarization_strategy_id

# IAM関連
terraform output memory_execution_role_arn
```

## 5. Agent Runtimeへの統合

Memory IDは自動的にAgent Runtimeの環境変数に設定されます：

```hcl
environment_variables = merge(
  {
    # 既存の環境変数...
  },
  var.enable_memory ? {
    MEMORY_ID = module.memory[0].memory_id
  } : {}
)
```

Pythonコードでの利用：

```python
from agentcore_hands_on.config import Settings

settings = Settings()
memory_id = settings.MEMORY_ID  # 環境変数から自動取得
```

## 6. カスタマイズ

### Namespace のカスタマイズ

デフォルトのNamespaceを変更したい場合：

```hcl
# main.tf のmodule "memory" セクションを編集
semantic_namespaces = ["custom_app/knowledge/{actorId}"]
user_preference_namespaces = ["custom_app/preferences/{actorId}"]
summarization_namespaces = ["custom_app/summaries/{actorId}/{sessionId}"]
```

### 保持期間の変更

```hcl
# terraform.tfvars
memory_retention_days = 30  # 30日に変更
```

### 特定のStrategyのみ有効化

```hcl
# terraform.tfvars
enable_memory                  = true
memory_enable_semantic         = true   # 有効
memory_enable_user_preference  = false  # 無効
memory_enable_summarization    = false  # 無効
```

## 7. トラブルシューティング

### エラー: "Memory execution role does not have permission"

**原因**: Memory実行ロールにBedrock権限がない

**解決方法**:
```bash
# IAMモジュールを確認
terraform state show module.iam.aws_iam_role_policy_attachment.memory_bedrock_inference

# 再適用
terraform apply
```

### エラー: "Agent runtime cannot access memory"

**原因**: RuntimeのIAMロールにMemory権限がない

**解決方法**:
```hcl
# variables.tf で enable_memory が true になっているか確認
enable_memory = true

# 再適用
terraform apply
```

### Memory IDが取得できない

**原因**: `enable_memory = false` または デプロイが失敗している

**解決方法**:
```bash
# enable_memory を確認
terraform show | grep enable_memory

# tfvars を確認
cat terraform.tfvars
```

## 8. クリーンアップ

Memory リソースを削除する場合：

```bash
# Memory無効化
terraform apply -var="enable_memory=false"

# または完全削除
terraform destroy
```

**注意**: Memory削除時は保存されたデータも削除されます。

## 9. 料金

### コスト構成

| リソース | 料金 |
|---------|------|
| Memory ストレージ | Short-term Memoryの保存量による |
| Memory 処理 | Long-term Memory抽出の頻度による |
| Bedrock モデル呼び出し | Strategy実行時のモデル使用量 |

### コスト最適化

```hcl
# 保持期間を短縮
memory_retention_days = 30

# 必要なStrategyのみ有効化
memory_enable_semantic         = true
memory_enable_user_preference  = false
memory_enable_summarization    = false
```

## 10. ベストプラクティス

### 開発環境

```hcl
enable_memory                  = true
memory_retention_days          = 30    # 短め
memory_enable_semantic         = true
memory_enable_user_preference  = true
memory_enable_summarization    = true
```

### 本番環境

```hcl
enable_memory                  = true
memory_retention_days          = 90    # 長め
memory_enable_semantic         = true
memory_enable_user_preference  = true
memory_enable_summarization    = true
```

### セキュリティ

- Memory実行ロールは最小権限
- AWS管理ポリシーを使用（推奨）
- 特定のMemory ARNに権限を限定

```hcl
# IAMモジュールで特定のMemory ARNに限定
memory_arns = [
  "arn:aws:bedrock-agentcore:us-east-1:123456789012:memory/MEMORY_ID"
]
```

## 11. 次のステップ

1. ✅ Terraformでデプロイ完了
2. ✅ Memory IDを`.env`に設定
3. 📝 Pythonコードで`memory_client.py`を実装
4. 🚀 Agent統合テスト
5. 📊 Observability設定

次は `docs/chat/memory/integration_strategy.md` を参照してPython実装を進めてください。
