# AgentCore RuntimeにつけるMemory関連IAM権限

## 概要

Agent Runtimeが AgentCore Memory を使用するために必要なIAM権限をまとめます。
これらの権限は **Agent RuntimeのIAMロール** (`role_arn`) に付与します。

## 参考リンク

- [IAMアクション完全リスト](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonbedrockagentcore.html)
- [Runtime IAM権限](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-permissions.html)

---

## 必要なIAMアクション

### 最小権限（推奨）

会話の保存と検索のみを行う場合：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AgentRuntimeMemoryMinimal",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:GetMemory",
        "bedrock-agentcore:CreateEvent",
        "bedrock-agentcore:RetrieveMemoryRecords"
      ],
      "Resource": "arn:aws:bedrock-agentcore:*:*:memory/*"
    }
  ]
}
```

### 標準権限

Memory レコードの操作も含める場合：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AgentRuntimeMemoryStandard",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:GetMemory",
        "bedrock-agentcore:CreateEvent",
        "bedrock-agentcore:RetrieveMemoryRecords",
        "bedrock-agentcore:GetMemoryRecord",
        "bedrock-agentcore:ListMemoryRecords",
        "bedrock-agentcore:BatchCreateMemoryRecords"
      ],
      "Resource": "arn:aws:bedrock-agentcore:*:*:memory/*"
    }
  ]
}
```

### フル権限

Memory の完全な管理が必要な場合：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AgentRuntimeMemoryFull",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:GetMemory",
        "bedrock-agentcore:CreateEvent",
        "bedrock-agentcore:GetEvent",
        "bedrock-agentcore:ListEvents",
        "bedrock-agentcore:DeleteEvent",
        "bedrock-agentcore:RetrieveMemoryRecords",
        "bedrock-agentcore:GetMemoryRecord",
        "bedrock-agentcore:ListMemoryRecords",
        "bedrock-agentcore:BatchCreateMemoryRecords",
        "bedrock-agentcore:BatchUpdateMemoryRecords",
        "bedrock-agentcore:BatchDeleteMemoryRecords",
        "bedrock-agentcore:DeleteMemoryRecord",
        "bedrock-agentcore:ListActors",
        "bedrock-agentcore:ListSessions"
      ],
      "Resource": "arn:aws:bedrock-agentcore:*:*:memory/*"
    }
  ]
}
```

---

## アクション詳細

| アクション | 用途 | 必要性 |
|-----------|------|--------|
| `GetMemory` | Memoryリソースの詳細取得 | **必須** |
| `CreateEvent` | 会話イベントをMemoryに保存 | **必須** |
| `RetrieveMemoryRecords` | セマンティック検索でMemory取得 | **必須** |
| `GetMemoryRecord` | 個別のMemoryレコード取得 | 推奨 |
| `ListMemoryRecords` | Memoryレコード一覧取得 | 推奨 |
| `BatchCreateMemoryRecords` | 複数のMemoryレコードを一括作成 | オプション |
| `BatchUpdateMemoryRecords` | 複数のMemoryレコードを一括更新 | オプション |
| `BatchDeleteMemoryRecords` | 複数のMemoryレコードを一括削除 | オプション |
| `GetEvent` | イベント詳細取得 | オプション |
| `ListEvents` | イベント一覧取得 | オプション |
| `DeleteEvent` | イベント削除 | オプション |
| `ListActors` | アクター一覧取得 | オプション |
| `ListSessions` | セッション一覧取得 | オプション |

---

## Terraform設定例

### 最小権限版

```hcl
# Runtimeロール用のMemory権限ポリシー
data "aws_iam_policy_document" "runtime_memory" {
  statement {
    sid    = "AgentRuntimeMemoryAccess"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetMemory",
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:RetrieveMemoryRecords",
    ]
    resources = [
      "arn:aws:bedrock-agentcore:${var.region}:${data.aws_caller_identity.current.account_id}:memory/${aws_bedrockagentcore_memory.example.id}"
    ]
  }
}

# Runtime IAMロールにポリシーをアタッチ
resource "aws_iam_role_policy" "runtime_memory" {
  name   = "bedrock-agentcore-runtime-memory-policy"
  role   = aws_iam_role.runtime.id
  policy = data.aws_iam_policy_document.runtime_memory.json
}

# Agent Runtime
resource "aws_bedrockagentcore_agent_runtime" "example" {
  agent_runtime_name = "example-runtime"
  role_arn           = aws_iam_role.runtime.arn
  # ...
}
```

### 特定のMemoryリソースに限定

```hcl
data "aws_iam_policy_document" "runtime_memory_scoped" {
  statement {
    sid    = "AgentRuntimeMemoryAccess"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetMemory",
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:RetrieveMemoryRecords",
      "bedrock-agentcore:GetMemoryRecord",
      "bedrock-agentcore:ListMemoryRecords",
    ]
    # 特定のMemoryのみに権限を制限
    resources = [
      aws_bedrockagentcore_memory.production.arn,
      aws_bedrockagentcore_memory.staging.arn,
    ]
  }
}
```

### ワイルドカード（全Memoryアクセス）

```hcl
data "aws_iam_policy_document" "runtime_memory_wildcard" {
  statement {
    sid    = "AgentRuntimeMemoryAccess"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetMemory",
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:RetrieveMemoryRecords",
    ]
    # 全てのMemoryにアクセス可能
    resources = ["arn:aws:bedrock-agentcore:*:*:memory/*"]
  }
}
```

---

## セキュリティベストプラクティス

### 1. 最小権限の原則

必要最小限のアクションのみを許可：

```hcl
# ❌ 避けるべき
actions = ["bedrock-agentcore:*"]

# ✅ 推奨
actions = [
  "bedrock-agentcore:GetMemory",
  "bedrock-agentcore:CreateEvent",
  "bedrock-agentcore:RetrieveMemoryRecords",
]
```

### 2. リソース範囲の制限

特定のMemoryリソースのみにアクセスを制限：

```hcl
# ❌ 避けるべき
resources = ["*"]

# ✅ 推奨
resources = [
  "arn:aws:bedrock-agentcore:${var.region}:${var.account_id}:memory/${var.memory_id}"
]
```

### 3. 条件付きアクセス

必要に応じて条件を追加：

```hcl
data "aws_iam_policy_document" "runtime_memory_conditional" {
  statement {
    sid    = "AgentRuntimeMemoryAccessConditional"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetMemory",
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:RetrieveMemoryRecords",
    ]
    resources = ["arn:aws:bedrock-agentcore:*:*:memory/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-west-2", "ap-northeast-1"]
    }
  }
}
```

---

## トラブルシューティング

### エラー: "User is not authorized to perform: bedrock-agentcore:CreateEvent"

**原因**: RuntimeのIAMロールに `CreateEvent` 権限がない

**解決方法**:
```hcl
resource "aws_iam_role_policy" "runtime_memory_fix" {
  role = aws_iam_role.runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock-agentcore:CreateEvent"]
      Resource = "arn:aws:bedrock-agentcore:*:*:memory/*"
    }]
  })
}
```

### エラー: "Access denied when retrieving memory records"

**原因**: `RetrieveMemoryRecords` 権限がない

**解決方法**:
RuntimeのIAMロールに `RetrieveMemoryRecords` アクションを追加

---

## まとめ

### 開発環境（最小構成）
```
- GetMemory
- CreateEvent
- RetrieveMemoryRecords
```

### 本番環境（推奨構成）
```
- GetMemory
- CreateEvent
- RetrieveMemoryRecords
- GetMemoryRecord
- ListMemoryRecords
- BatchCreateMemoryRecords
```

### 完全管理が必要な場合
上記 + 更新・削除系のアクション
