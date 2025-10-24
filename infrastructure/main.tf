# Terraform configuration for AWS Bedrock AgentCore infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.17.0"
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
  agent_runtime_name = replace("${var.project_name}_${var.agent_name}_runtime", "-", "_")
  endpoint_name      = replace("${var.project_name}_${var.agent_name}_endpoint", "-", "_")
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
    "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.id}::foundation-model/*"
  ]

  tags = local.common_tags
}

# Agent Runtime Module
module "agent_runtime" {
  source = "./modules/agent_runtime"

  agent_runtime_name = local.agent_runtime_name
  description        = "Agent runtime for ${var.agent_name}"
  role_arn           = module.iam.role_arn
  container_uri      = var.container_image_uri != "" ? var.container_image_uri : "${module.ecr.repository_url}:${var.image_tag}"

  environment_variables = {
    # 既存の環境変数
    LOG_LEVEL   = var.log_level
    ENVIRONMENT = var.environment

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
  }

  network_mode    = "PUBLIC"
  server_protocol = "HTTP"

  create_endpoint      = false
  endpoint_name        = ""
  endpoint_description = ""

  tags = local.common_tags
}
