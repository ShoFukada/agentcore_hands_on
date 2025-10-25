# AgentCore Memory自体につけるIAM権限

## 概要

AgentCore Memory リソースが Memory Strategy（SEMANTIC、SUMMARIZATION等）を実行するために必要なIAM権限をまとめます。
これらの権限は **MemoryのIAMロール** (`memory_execution_role_arn`) に付与します。

## 参考リンク

- [AWS管理ポリシー一覧](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-iam-awsmanpol.html)
- [Memory入門ガイド](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-getting-started.html)

---

## AWS管理ポリシー（推奨）

### AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy

Memory Strategyを使用する場合、このAWS管理ポリシーをアタッチするのが最も簡単です。

**ARN**: `arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy`

**含まれる権限**:
- `bedrock:InvokeModel`
- `bedrock:InvokeModelWithResponseStream`

**用途**:
- セマンティック理解のためのBedrockモデル呼び出し
- 要約処理のためのBedrockモデル呼び出し
- カスタムMemory Strategyでのモデル推論

---

## 必要なIAMアクション

### Bedrock モデル推論権限（必須）

Memory Strategyが内部的にBedrockモデルを使用するため必須：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "MemoryBedrockModelInference",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/*"
    }
  ]
}
```

### KMS暗号化を使用する場合（オプション）

カスタムKMSキーで暗号化する場合に必要：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "MemoryKMSAccess",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": "arn:aws:kms:*:*:key/*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "bedrock-agentcore.*.amazonaws.com"
          ]
        }
      }
    }
  ]
}
```

---

## Terraform設定例

### 基本構成（AWS管理ポリシー使用）

```hcl
# MemoryサービスのAssume Roleポリシー
data "aws_iam_policy_document" "memory_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

# Memory実行用IAMロール
resource "aws_iam_role" "memory_execution" {
  name               = "bedrock-agentcore-memory-execution-role"
  assume_role_policy = data.aws_iam_policy_document.memory_assume_role.json
}

# AWS管理ポリシーをアタッチ（推奨）
resource "aws_iam_role_policy_attachment" "memory_bedrock_inference" {
  role       = aws_iam_role.memory_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}

# Memory リソース
resource "aws_bedrockagentcore_memory" "example" {
  name                      = "example-memory"
  event_expiry_duration     = 30
  memory_execution_role_arn = aws_iam_role.memory_execution.arn
}
```

### カスタムポリシー版

AWS管理ポリシーを使わず、必要最小限の権限のみ付与する場合：

```hcl
# カスタムポリシードキュメント
data "aws_iam_policy_document" "memory_bedrock_custom" {
  # Bedrockモデル推論権限
  statement {
    sid    = "BedrockModelInference"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
      "arn:aws:bedrock:*::foundation-model/amazon.titan-*"
    ]
  }
}

resource "aws_iam_role_policy" "memory_bedrock" {
  name   = "memory-bedrock-inference-policy"
  role   = aws_iam_role.memory_execution.id
  policy = data.aws_iam_policy_document.memory_bedrock_custom.json
}
```

### KMS暗号化を使用する場合

```hcl
# KMSキーの作成
resource "aws_kms_key" "memory" {
  description             = "KMS key for Bedrock AgentCore Memory"
  deletion_window_in_days = 7
}

# Memory用のKMS権限ポリシー
data "aws_iam_policy_document" "memory_kms" {
  statement {
    sid    = "MemoryKMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    resources = [aws_kms_key.memory.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["bedrock-agentcore.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "memory_kms" {
  name   = "memory-kms-policy"
  role   = aws_iam_role.memory_execution.id
  policy = data.aws_iam_policy_document.memory_kms.json
}

# Memoryリソース（KMS暗号化あり）
resource "aws_bedrockagentcore_memory" "encrypted" {
  name                      = "encrypted-memory"
  event_expiry_duration     = 30
  encryption_key_arn        = aws_kms_key.memory.arn
  memory_execution_role_arn = aws_iam_role.memory_execution.arn
}
```

### 完全な例（Memory + Strategy）

```hcl
# Memory実行ロール
resource "aws_iam_role" "memory_execution" {
  name               = "bedrock-agentcore-memory-execution-role"
  assume_role_policy = data.aws_iam_policy_document.memory_assume_role.json
}

# AWS管理ポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "memory_bedrock_inference" {
  role       = aws_iam_role.memory_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}

# Memory リソース
resource "aws_bedrockagentcore_memory" "example" {
  name                      = "example-memory"
  event_expiry_duration     = 30
  memory_execution_role_arn = aws_iam_role.memory_execution.arn
}

# Memory Strategy（Semantic）
resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name        = "semantic-strategy"
  memory_id   = aws_bedrockagentcore_memory.example.id
  type        = "SEMANTIC"
  description = "Semantic understanding strategy"
  namespaces  = ["default"]
}

# Memory Strategy（Custom）
resource "aws_bedrockagentcore_memory_strategy" "custom" {
  name                      = "custom-semantic-strategy"
  memory_id                 = aws_bedrockagentcore_memory.example.id
  memory_execution_role_arn = aws_iam_role.memory_execution.arn
  type                      = "CUSTOM"
  namespaces                = ["{sessionId}"]

  configuration {
    type = "SEMANTIC_OVERRIDE"

    consolidation {
      append_to_prompt = "Focus on key semantic relationships"
      model_id         = "anthropic.claude-3-sonnet-20240229-v1:0"
    }

    extraction {
      append_to_prompt = "Extract semantic information"
      model_id         = "anthropic.claude-3-haiku-20240307-v1:0"
    }
  }
}
```

---

## アクション詳細

| アクション | 用途 | 必要性 |
|-----------|------|--------|
| `bedrock:InvokeModel` | Bedrockモデルの同期呼び出し（要約・抽出） | **必須** |
| `bedrock:InvokeModelWithResponseStream` | Bedrockモデルのストリーミング呼び出し | **必須** |
| `kms:Decrypt` | KMS暗号化データの復号化 | KMS使用時のみ |
| `kms:DescribeKey` | KMSキー情報の取得 | KMS使用時のみ |
| `kms:CreateGrant` | KMSグラントの作成 | KMS使用時のみ |

---

## Memory Strategyとの関係

### Built-in Strategy

以下の組み込みStrategyを使用する場合、Bedrock推論権限が必要：

- **SEMANTIC**: セマンティック理解のためモデルを使用
- **SUMMARIZATION**: 要約生成のためモデルを使用
- **USER_PREFERENCE**: ユーザー設定抽出のためモデルを使用

### Custom Strategy

カスタムStrategyで明示的にモデルを指定する場合：

```hcl
configuration {
  type = "SEMANTIC_OVERRIDE"

  consolidation {
    model_id = "anthropic.claude-3-sonnet-20240229-v1:0"  # ← この呼び出しに権限が必要
  }

  extraction {
    model_id = "anthropic.claude-3-haiku-20240307-v1:0"   # ← この呼び出しに権限が必要
  }
}
```

---

## セキュリティベストプラクティス

### 1. 使用するモデルの制限

全てのBedrockモデルではなく、使用するモデルのみに権限を限定：

```hcl
data "aws_iam_policy_document" "memory_bedrock_restricted" {
  statement {
    sid    = "BedrockModelInferenceRestricted"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = [
      # Claudeモデルのみ許可
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-*",
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-*"
    ]
  }
}
```

### 2. リージョンの制限

特定のリージョンでのみモデル呼び出しを許可：

```hcl
data "aws_iam_policy_document" "memory_bedrock_region_restricted" {
  statement {
    sid    = "BedrockModelInferenceRegionRestricted"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = ["arn:aws:bedrock:*::foundation-model/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-west-2", "ap-northeast-1"]
    }
  }
}
```

### 3. KMSキーポリシー

カスタムKMSキーを使用する場合、キーポリシーも設定：

```hcl
resource "aws_kms_key" "memory" {
  description = "KMS key for Bedrock AgentCore Memory"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow AgentCore Memory to use the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.memory_execution.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "bedrock-agentcore.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}
```

---

## トラブルシューティング

### エラー: "Memory execution role does not have permission to invoke Bedrock model"

**原因**: Memory実行ロールに `bedrock:InvokeModel` 権限がない

**解決方法**:
```hcl
resource "aws_iam_role_policy_attachment" "fix_bedrock" {
  role       = aws_iam_role.memory_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}
```

### エラー: "KMS key access denied"

**原因**: Memory実行ロールにKMS権限がない、またはKMSキーポリシーが正しくない

**解決方法**:
1. Memory実行ロールにKMS権限を追加
2. KMSキーポリシーでMemory実行ロールを許可

```hcl
# ロールポリシー
data "aws_iam_policy_document" "memory_kms_fix" {
  statement {
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    resources = [aws_kms_key.memory.arn]
  }
}

resource "aws_iam_role_policy" "memory_kms_fix" {
  role   = aws_iam_role.memory_execution.id
  policy = data.aws_iam_policy_document.memory_kms_fix.json
}
```

---

## まとめ

### 最小構成（Built-in Strategy使用）

```
✅ AWS管理ポリシー: AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy
```

### KMS暗号化使用

```
✅ AWS管理ポリシー: AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy
✅ カスタムポリシー: KMS Decrypt/DescribeKey/CreateGrant
```

### カスタムStrategy使用

```
✅ Bedrock InvokeModel権限（使用するモデルに限定）
✅ KMS権限（暗号化使用時）
```

---

## チェックリスト

Memory作成時に確認すべき項目：

- [ ] Memory実行ロールが作成されている
- [ ] Assume Roleポリシーで `bedrock-agentcore.amazonaws.com` を信頼している
- [ ] `AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy` がアタッチされている
- [ ] KMS使用時、KMS権限が付与されている
- [ ] KMS使用時、KMSキーポリシーでロールが許可されている
- [ ] Memory Strategy使用時、必要なモデルへのアクセス権限がある
