# Terraform configuration for AWS Bedrock AgentCore infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.18.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "agentcore-hands-on"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Get current AWS account and region info
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Local variables
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Agent Runtime名とEndpoint名はアンダースコアのみ使用可能（ハイフン不可）
  agent_runtime_name        = replace("${var.project_name}_${var.agent_name}_runtime", "-", "_")
  endpoint_name             = replace("${var.project_name}_${var.agent_name}_endpoint", "-", "_")
  code_interpreter_name     = replace("${var.project_name}_${var.agent_name}_code_interpreter", "-", "_")
  code_interpreter_role     = "${var.project_name}-code-interpreter-role"
  code_interpreter_policy   = "${var.project_name}-code-interpreter-policy"
  browser_name              = replace("${var.project_name}_${var.agent_name}_browser", "-", "_")
  browser_role              = "${var.project_name}-browser-role"
  browser_policy            = "${var.project_name}-browser-policy"
  memory_name               = replace("${var.project_name}_${var.agent_name}_memory", "-", "_")
  memory_execution_role     = "${var.project_name}-memory-execution-role"
}

# ECR Module
module "ecr" {
  source = "./modules/ecr"

  repository_name = "${var.project_name}-${var.agent_name}"
  force_delete    = true

  tags = local.common_tags
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  role_name   = "${var.project_name}-agent-runtime-role"
  policy_name = "${var.project_name}-agent-runtime-policy"

  ecr_repository_arns   = [module.ecr.repository_arn]
  enable_bedrock_invoke = true
  bedrock_model_arns = [
    "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*",
    "arn:${data.aws_partition.current.partition}:bedrock:*:*:inference-profile/*"
  ]

  # Code Interpreter IAM Role
  create_code_interpreter_role = true
  code_interpreter_role_name   = local.code_interpreter_role
  code_interpreter_policy_name = local.code_interpreter_policy

  # Browser IAM Role
  create_browser_role = true
  browser_role_name   = local.browser_role
  browser_policy_name = local.browser_policy

  # Memory Execution IAM Role
  create_memory_execution_role = true
  memory_execution_role_name   = local.memory_execution_role

  tags = local.common_tags
}

# Agent Runtime Module
module "agent_runtime" {
  source = "./modules/agent_runtime"

  agent_runtime_name = local.agent_runtime_name
  description        = "Agent runtime for ${var.agent_name}"
  role_arn           = module.iam.role_arn
  container_uri      = var.container_image_uri != "" ? var.container_image_uri : "${module.ecr.repository_url}:${var.image_tag}"

  environment_variables = merge(
    {
      # 既存の環境変数
      LOG_LEVEL   = var.log_level
      ENVIRONMENT = var.environment

      # Code Interpreter ID
      CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id

      # Browser ID
      BROWSER_ID = module.browser.browser_id

      # AgentCore Observability設定
      AGENT_OBSERVABILITY_ENABLED = "true"

      # OpenTelemetry基本設定
      OTEL_PYTHON_DISTRO       = "aws_distro"
      OTEL_PYTHON_CONFIGURATOR = "aws_configurator"

      # リソース属性（サービス名、ロググループ、リソースID）
      # runtime_idはtfvarsから取得（2段階デプロイ後）
      OTEL_RESOURCE_ATTRIBUTES = var.agent_runtime_id != "" ? "service.name=${var.agent_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id},cloud.resource_id=${var.agent_runtime_id}" : "service.name=${var.agent_name}"

      # OTLPエクスポーター設定（ロググループ、ログストリーム、メトリクスネームスペース）
      OTEL_EXPORTER_OTLP_LOGS_HEADERS = var.agent_runtime_id != "" ? "x-aws-log-group=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id},x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore" : "x-aws-metric-namespace=bedrock-agentcore"

      # プロトコルとエクスポーター設定
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
      OTEL_TRACES_EXPORTER        = "otlp"

      # サンプリング設定（開発環境なので100%）
      OTEL_TRACES_SAMPLER = "always_on"
    },
    # Memory ID
    {
      MEMORY_ID = module.memory.memory_id
    }
  )

  network_mode    = "PUBLIC"
  server_protocol = "HTTP"

  create_endpoint      = false
  endpoint_name        = ""
  endpoint_description = ""

  tags = local.common_tags
}

# Code Interpreter Module
module "code_interpreter" {
  source = "./modules/code_interpreter"

  name               = local.code_interpreter_name
  description        = "Code interpreter for ${var.agent_name} with sandboxed Python execution"
  execution_role_arn = module.iam.code_interpreter_role_arn
  network_mode       = "SANDBOX"

  tags = local.common_tags
}

# Browser Module
module "browser" {
  source = "./modules/browser"

  name               = local.browser_name
  description        = "Browser for ${var.agent_name} with web browsing capabilities"
  execution_role_arn = module.iam.browser_role_arn
  network_mode       = "PUBLIC"

  tags = local.common_tags
}

# Memory Module
module "memory" {
  source = "./modules/memory"

  name                      = local.memory_name
  description               = "Memory for ${var.agent_name} with conversation history and knowledge extraction"
  event_expiry_duration     = var.memory_retention_days
  memory_execution_role_arn = module.iam.memory_execution_role_arn

  # Strategy configuration
  create_semantic_strategy        = var.memory_enable_semantic
  semantic_strategy_name          = "${replace(var.project_name, "-", "_")}_semantic_strategy"
  semantic_strategy_description   = "Extract technical knowledge and facts from conversations"
  semantic_namespaces             = ["${var.project_name}/knowledge/{actorId}"]

  create_user_preference_strategy        = var.memory_enable_user_preference
  user_preference_strategy_name          = "${replace(var.project_name, "-", "_")}_preference_strategy"
  user_preference_strategy_description   = "Track user preferences and behavioral patterns"
  user_preference_namespaces             = ["${var.project_name}/preferences/{actorId}"]

  create_summarization_strategy        = var.memory_enable_summarization
  summarization_strategy_name          = "${replace(var.project_name, "-", "_")}_summary_strategy"
  summarization_strategy_description   = "Generate session summaries with key insights"
  summarization_namespaces             = ["${var.project_name}/summaries/{actorId}/{sessionId}"]

  tags = local.common_tags
}
