# Terraform で Observability を有効にする方法

## 結論

**はい、できます！** `environment_variables` に追加すれば OK です。

## 問題点と解決策

### 問題点

Agent Runtime ID は作成されるまでわからないため、以下のような環境変数が必要です：

```
OTEL_RESOURCE_ATTRIBUTES=...aws.log.group.names=/aws/bedrock-agentcore/runtimes/<RUNTIME_ID>
OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=/aws/bedrock-agentcore/runtimes/<RUNTIME_ID>...
```

### 解決策

Terraform の **`self`** 参照を使って、作成中のリソース自身の属性を参照できます！

## 修正方法

### 1. `infrastructure/main.tf` を編集

```hcl
# Agent Runtime Module
module "agent_runtime" {
  source = "./modules/agent_runtime"

  agent_runtime_name = local.agent_runtime_name
  description        = "Agent runtime for ${var.agent_name}"
  role_arn           = module.iam.role_arn
  container_uri      = var.container_image_uri != "" ? var.container_image_uri : "${module.ecr.repository_url}:latest"

  environment_variables = {
    LOG_LEVEL   = var.log_level
    ENVIRONMENT = var.environment

    # Observability 設定を追加
    AGENT_OBSERVABILITY_ENABLED              = "true"
    OTEL_PYTHON_DISTRO                       = "aws_distro"
    OTEL_PYTHON_CONFIGURATOR                 = "aws_configurator"
    OTEL_EXPORTER_OTLP_PROTOCOL              = "http/protobuf"
    OTEL_TRACES_EXPORTER                     = "otlp"
  }

  # 動的に環境変数を追加（Runtime ID が必要な変数）
  enable_observability = var.enable_observability  # 新しい変数

  network_mode    = "PUBLIC"
  server_protocol = "HTTP"

  create_endpoint      = true
  endpoint_name        = local.endpoint_name
  endpoint_description = "Endpoint for ${var.agent_name}"

  tags = local.common_tags
}
```

### 2. `infrastructure/variables.tf` に新しい変数を追加

```hcl
variable "enable_observability" {
  description = "Enable observability for the agent runtime"
  type        = bool
  default     = false
}
```

### 3. `infrastructure/modules/agent_runtime/variables.tf` を編集

```hcl
variable "enable_observability" {
  description = "Enable observability for the agent runtime"
  type        = bool
  default     = false
}
```

### 4. `infrastructure/modules/agent_runtime/main.tf` を編集

```hcl
# Simple Agent Runtime resource

locals {
  # 基本的な環境変数
  base_env_vars = var.environment_variables

  # Observability が有効な場合に追加する環境変数
  observability_env_vars = var.enable_observability ? {
    OTEL_RESOURCE_ATTRIBUTES = "service.name=${var.agent_runtime_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}"
    OTEL_EXPORTER_OTLP_LOGS_HEADERS = "x-aws-log-group=/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id},x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore"
  } : {}

  # 統合した環境変数
  merged_env_vars = merge(local.base_env_vars, local.observability_env_vars)
}

resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = var.agent_runtime_name
  description        = var.description
  role_arn           = var.role_arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_uri
    }
  }

  environment_variables = local.merged_env_vars

  network_configuration {
    network_mode = var.network_mode
  }

  protocol_configuration {
    server_protocol = var.server_protocol
  }

  tags = var.tags
}

# Agent Runtime Endpoint
resource "aws_bedrockagentcore_agent_runtime_endpoint" "main" {
  count = var.create_endpoint ? 1 : 0

  name             = var.endpoint_name
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.main.agent_runtime_id
  description      = var.endpoint_description

  tags = var.tags
}
```

## ⚠️ 重要な注意点

### Terraform の循環参照問題

上記の方法には**問題**があります：

```hcl
environment_variables = {
  OTEL_RESOURCE_ATTRIBUTES = "...${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}"
}
```

この書き方は、リソース作成時に自分自身の ID を参照しようとするため、**循環参照エラー**になる可能性があります。

### 実際に動作するかテストが必要

Terraform が以下のどちらの動作をするか不明です：
1. ✅ リソース作成後に環境変数を更新してくれる
2. ❌ 循環参照エラーで失敗する

## より確実な方法：2段階デプロイ

### Option A: lifecycle で ignore_changes を使う

```hcl
resource "aws_bedrockagentcore_agent_runtime" "main" {
  # ... 既存の設定 ...

  environment_variables = var.environment_variables

  lifecycle {
    ignore_changes = [environment_variables]
  }
}

# 別リソースで環境変数を更新
resource "terraform_data" "update_observability" {
  count = var.enable_observability ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agentcore-control update-agent-runtime \
        --agent-runtime-id ${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id} \
        --environment-variables \
          OTEL_RESOURCE_ATTRIBUTES="service.name=${var.agent_runtime_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}" \
          OTEL_EXPORTER_OTLP_LOGS_HEADERS="x-aws-log-group=/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id},x-aws-log-stream=runtime-logs"
    EOT
  }
}
```

### Option B: null_resource で更新（推奨）

```hcl
resource "null_resource" "enable_observability" {
  count = var.enable_observability ? 1 : 0

  depends_on = [aws_bedrockagentcore_agent_runtime.main]

  triggers = {
    runtime_id = aws_bedrockagentcore_agent_runtime.main.agent_runtime_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Runtime ID を使った環境変数を設定
      echo "Setting observability for ${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}"
      # ⚠️ AWS CLI コマンドがまだ完全にサポートされていない可能性があります
    EOT
  }
}
```

## 最もシンプルな実装方法

循環参照を避けるため、**Runtime ID を使わない形で基本的な Observability 設定だけを追加**する：

### `infrastructure/main.tf` を編集

```hcl
module "agent_runtime" {
  source = "./modules/agent_runtime"

  agent_runtime_name = local.agent_runtime_name
  description        = "Agent runtime for ${var.agent_name}"
  role_arn           = module.iam.role_arn
  container_uri      = var.container_image_uri != "" ? var.container_image_uri : "${module.ecr.repository_url}:latest"

  environment_variables = merge(
    {
      LOG_LEVEL   = var.log_level
      ENVIRONMENT = var.environment
    },
    var.enable_observability ? {
      AGENT_OBSERVABILITY_ENABLED = "true"
      OTEL_PYTHON_DISTRO          = "aws_distro"
      OTEL_PYTHON_CONFIGURATOR    = "aws_configurator"
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
      OTEL_TRACES_EXPORTER        = "otlp"
    } : {}
  )

  network_mode    = "PUBLIC"
  server_protocol = "HTTP"

  create_endpoint      = true
  endpoint_name        = local.endpoint_name
  endpoint_description = "Endpoint for ${var.agent_name}"

  tags = local.common_tags
}
```

この方法なら：
- ✅ 循環参照なし
- ✅ Terraform だけで完結
- ⚠️ ただし、Runtime ID を含む環境変数（ログの送信先など）は設定できない

## 推奨する実装方法

**段階的アプローチ**:

1. **まずは基本的な Observability 設定を Terraform に追加**（上記のシンプルな方法）
2. **Runtime ID が必要な環境変数は、作成後に手動または別スクリプトで追加**

## terraform.tfvars に追加

```hcl
enable_observability = true
```

## まとめ

| 方法 | メリット | デメリット |
|------|----------|------------|
| 基本設定のみ Terraform に追加 | ✅ シンプル<br>✅ 循環参照なし | ⚠️ ログ送信先は手動設定が必要 |
| null_resource で更新 | ✅ 完全自動化 | ❌ 複雑<br>❌ AWS CLI サポート不明 |
| 手動で追加 | ✅ 確実 | ❌ 手作業が必要 |

**推奨**: まずは基本設定のみを Terraform に追加し、必要に応じて手動で完全な設定を行う。

GitHub Issue #44742 が解決されれば、すべて Terraform で完結できるようになります。
