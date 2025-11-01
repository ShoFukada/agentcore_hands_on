# AgentCore CloudWatch Logs配信 - Terraform実装例

このドキュメントでは、Gateway、Memory、Code Interpreter、BrowserそれぞれにCloudWatch Logsの配信を設定するための完全なTerraform設定例を提供します。

## 前提条件

### 必要なデータソース

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
```

### 変数定義（オプション）

```hcl
variable "enable_cloudwatch_logs" {
  description = "CloudWatch Logsへのログ配信を有効化"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logsの保持期間（日数）"
  type        = number
  default     = 7
}

variable "project_name" {
  description = "プロジェクト名"
  type        = string
  default     = "agentcore-hands-on"
}

variable "environment" {
  description = "環境名"
  type        = string
  default     = "dev"
}
```

## 1. Gateway用ログ配信設定

```hcl
# ========================
# Gateway リソース（既存）
# ========================
resource "aws_bedrockagentcore_gateway" "example" {
  name     = "${var.project_name}-gateway"
  role_arn = aws_iam_role.gateway.arn

  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ========================
# CloudWatch Logs配信設定
# ========================

# 1. ログ配信ソース
resource "aws_cloudwatch_log_delivery_source" "gateway" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name         = "bedrock-agentcore-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_gateway.example.gateway_arn
}

# 2. ロググループ
resource "aws_cloudwatch_log_group" "gateway" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/${aws_bedrockagentcore_gateway.example.gateway_id}"
  retention_in_days = var.log_retention_days

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    ResourceType = "gateway"
  }
}

# 3. リソースポリシー
resource "aws_cloudwatch_log_resource_policy" "gateway" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  policy_name = "${var.project_name}-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.gateway[0].arn}:log-stream:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

# 4. ログ配信先
resource "aws_cloudwatch_log_delivery_destination" "gateway" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name = "${var.project_name}-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}-cloudwatch"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.gateway[0].arn
  }

  depends_on = [aws_cloudwatch_log_resource_policy.gateway]
}

# 5. ログ配信（ソースと配信先のリンク）
resource "aws_cloudwatch_log_delivery" "gateway" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway[0].arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway[0].name
}
```

## 2. Memory用ログ配信設定

```hcl
# ========================
# Memory リソース（既存）
# ========================
resource "aws_bedrockagentcore_memory" "example" {
  name                  = "${var.project_name}-memory"
  event_expiry_duration = 30

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ========================
# CloudWatch Logs配信設定
# ========================

# 1. ログ配信ソース
resource "aws_cloudwatch_log_delivery_source" "memory" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name         = "bedrock-agentcore-memory-${aws_bedrockagentcore_memory.example.id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_memory.example.arn
}

# 2. ロググループ
resource "aws_cloudwatch_log_group" "memory" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/vendedlogs/bedrock-agentcore/memory/APPLICATION_LOGS/${aws_bedrockagentcore_memory.example.id}"
  retention_in_days = var.log_retention_days

  tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    ResourceType = "memory"
  }
}

# 3. リソースポリシー
resource "aws_cloudwatch_log_resource_policy" "memory" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  policy_name = "${var.project_name}-memory-${aws_bedrockagentcore_memory.example.id}-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.memory[0].arn}:log-stream:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

# 4. ログ配信先
resource "aws_cloudwatch_log_delivery_destination" "memory" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name = "${var.project_name}-memory-${aws_bedrockagentcore_memory.example.id}-cloudwatch"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.memory[0].arn
  }

  depends_on = [aws_cloudwatch_log_resource_policy.memory]
}

# 5. ログ配信（ソースと配信先のリンク）
resource "aws_cloudwatch_log_delivery" "memory" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.memory[0].arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.memory[0].name
}
```

## 3. Code Interpreter用ログ配信設定

```hcl
# ========================
# Code Interpreter リソース（既存）
# ========================
resource "aws_bedrockagentcore_code_interpreter" "example" {
  name        = "${var.project_name}-code-interpreter"
  description = "Code interpreter for data analysis"

  network_configuration {
    network_mode = "PUBLIC"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ========================
# CloudWatch Logs配信設定
# ========================

# 1. ログ配信ソース
resource "aws_cloudwatch_log_delivery_source" "code_interpreter" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name         = "bedrock-agentcore-code-interpreter-${aws_bedrockagentcore_code_interpreter.example.code_interpreter_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_code_interpreter.example.code_interpreter_arn
}

# 2. ロググループ
resource "aws_cloudwatch_log_group" "code_interpreter" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/vendedlogs/bedrock-agentcore/code-interpreter/APPLICATION_LOGS/${aws_bedrockagentcore_code_interpreter.example.code_interpreter_id}"
  retention_in_days = var.log_retention_days

  tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    ResourceType = "code-interpreter"
  }
}

# 3. リソースポリシー
resource "aws_cloudwatch_log_resource_policy" "code_interpreter" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  policy_name = "${var.project_name}-code-interpreter-${aws_bedrockagentcore_code_interpreter.example.code_interpreter_id}-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.code_interpreter[0].arn}:log-stream:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

# 4. ログ配信先
resource "aws_cloudwatch_log_delivery_destination" "code_interpreter" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name = "${var.project_name}-code-interpreter-${aws_bedrockagentcore_code_interpreter.example.code_interpreter_id}-cloudwatch"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.code_interpreter[0].arn
  }

  depends_on = [aws_cloudwatch_log_resource_policy.code_interpreter]
}

# 5. ログ配信（ソースと配信先のリンク）
resource "aws_cloudwatch_log_delivery" "code_interpreter" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.code_interpreter[0].arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.code_interpreter[0].name
}
```

## 4. Browser用ログ配信設定

```hcl
# ========================
# Browser リソース（既存）
# ========================
resource "aws_bedrockagentcore_browser" "example" {
  name        = "${var.project_name}-browser"
  description = "Browser for web data extraction"

  network_configuration {
    network_mode = "PUBLIC"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ========================
# CloudWatch Logs配信設定
# ========================

# 1. ログ配信ソース
resource "aws_cloudwatch_log_delivery_source" "browser" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name         = "bedrock-agentcore-browser-${aws_bedrockagentcore_browser.example.browser_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_browser.example.browser_arn
}

# 2. ロググループ
resource "aws_cloudwatch_log_group" "browser" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/vendedlogs/bedrock-agentcore/browser/APPLICATION_LOGS/${aws_bedrockagentcore_browser.example.browser_id}"
  retention_in_days = var.log_retention_days

  tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    ResourceType = "browser"
  }
}

# 3. リソースポリシー
resource "aws_cloudwatch_log_resource_policy" "browser" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  policy_name = "${var.project_name}-browser-${aws_bedrockagentcore_browser.example.browser_id}-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.browser[0].arn}:log-stream:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

# 4. ログ配信先
resource "aws_cloudwatch_log_delivery_destination" "browser" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name = "${var.project_name}-browser-${aws_bedrockagentcore_browser.example.browser_id}-cloudwatch"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.browser[0].arn
  }

  depends_on = [aws_cloudwatch_log_resource_policy.browser]
}

# 5. ログ配信（ソースと配信先のリンク）
resource "aws_cloudwatch_log_delivery" "browser" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.browser[0].arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.browser[0].name
}
```

## 5. まとめて設定するモジュール例

すべてのリソースのログ配信を一括で管理するモジュールの例：

### modules/agentcore_logs/main.tf

```hcl
variable "resource_type" {
  description = "AgentCoreリソースタイプ（gateway, memory, code-interpreter, browser）"
  type        = string
}

variable "resource_id" {
  description = "AgentCoreリソースID"
  type        = string
}

variable "resource_arn" {
  description = "AgentCoreリソースARN"
  type        = string
}

variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境名"
  type        = string
}

variable "log_retention_days" {
  description = "ログ保持期間（日数）"
  type        = number
  default     = 7
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ログ配信ソース
resource "aws_cloudwatch_log_delivery_source" "this" {
  name         = "bedrock-agentcore-${var.resource_type}-${var.resource_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = var.resource_arn
}

# ロググループ
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/vendedlogs/bedrock-agentcore/${var.resource_type}/APPLICATION_LOGS/${var.resource_id}"
  retention_in_days = var.log_retention_days

  tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    ResourceType = var.resource_type
  }
}

# リソースポリシー
resource "aws_cloudwatch_log_resource_policy" "this" {
  policy_name = "${var.project_name}-${var.resource_type}-${var.resource_id}-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.this.arn}:log-stream:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

# ログ配信先
resource "aws_cloudwatch_log_delivery_destination" "this" {
  name = "${var.project_name}-${var.resource_type}-${var.resource_id}-cloudwatch"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.this.arn
  }

  depends_on = [aws_cloudwatch_log_resource_policy.this]
}

# ログ配信
resource "aws_cloudwatch_log_delivery" "this" {
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this.arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.this.name
}

output "log_group_name" {
  description = "作成されたロググループ名"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "作成されたロググループのARN"
  value       = aws_cloudwatch_log_group.this.arn
}
```

### モジュールの使用例

```hcl
# Gateway用
module "gateway_logs" {
  source = "./modules/agentcore_logs"

  resource_type       = "gateway"
  resource_id         = aws_bedrockagentcore_gateway.example.gateway_id
  resource_arn        = aws_bedrockagentcore_gateway.example.gateway_arn
  project_name        = var.project_name
  environment         = var.environment
  log_retention_days  = 7
}

# Memory用
module "memory_logs" {
  source = "./modules/agentcore_logs"

  resource_type       = "memory"
  resource_id         = aws_bedrockagentcore_memory.example.id
  resource_arn        = aws_bedrockagentcore_memory.example.arn
  project_name        = var.project_name
  environment         = var.environment
  log_retention_days  = 7
}

# Code Interpreter用
module "code_interpreter_logs" {
  source = "./modules/agentcore_logs"

  resource_type       = "code-interpreter"
  resource_id         = aws_bedrockagentcore_code_interpreter.example.code_interpreter_id
  resource_arn        = aws_bedrockagentcore_code_interpreter.example.code_interpreter_arn
  project_name        = var.project_name
  environment         = var.environment
  log_retention_days  = 7
}

# Browser用
module "browser_logs" {
  source = "./modules/agentcore_logs"

  resource_type       = "browser"
  resource_id         = aws_bedrockagentcore_browser.example.browser_id
  resource_arn        = aws_bedrockagentcore_browser.example.browser_arn
  project_name        = var.project_name
  environment         = var.environment
  log_retention_days  = 7
}
```

## 実装時の注意点

### 1. リソース作成順序

AgentCoreリソース本体を先に作成してから、ログ配信設定を追加してください：

```bash
# 1. 既存のAgentCoreリソースをデプロイ
terraform apply -target=aws_bedrockagentcore_gateway.example

# 2. ログ配信設定を追加
terraform apply
```

### 2. ロググループ名の制約

- `/aws/vendedlogs/`で始まる必要があります
- リソースタイプとリソースIDを含める必要があります

### 3. IAMポリシーの確認

`delivery.logs.amazonaws.com`サービスがロググループにログを書き込めるように、リソースポリシーを正しく設定してください。

### 4. 複数配信先の設定

複数のログ配信先（CloudWatch LogsとS3の両方など）を設定する場合は、`depends_on`で依存関係を明示してください。

### 5. タグ付け

リソースの管理を容易にするため、一貫したタグ付けを行ってください。

## トラブルシューティング

### ログが出力されない場合

1. **リソースポリシーの確認**
   ```bash
   aws logs describe-resource-policies
   ```

2. **ログ配信の状態確認**
   ```bash
   aws logs describe-deliveries
   ```

3. **ログ配信ソースの確認**
   ```bash
   aws logs describe-delivery-sources
   ```

4. **ログ配信先の確認**
   ```bash
   aws logs describe-delivery-destinations
   ```

### Terraform適用エラー

- AgentCoreリソースが完全に作成される前にログ配信設定を作成しようとするとエラーになる場合があります
- `depends_on`を使用して明示的に依存関係を設定してください

### リソースポリシーの競合

- 同じロググループに複数のリソースポリシーを設定しようとすると競合します
- ポリシー名を一意にし、適切な`count`条件を設定してください
