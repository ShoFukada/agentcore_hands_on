# Outputs for AgentCore infrastructure

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# ECR outputs
output "ecr_repository_url" {
  description = "ECR repository URL for agent container images"
  value       = module.ecr.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = module.ecr.repository_arn
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = module.ecr.repository_name
}

# Agent Runtime outputs
output "agent_runtime_id" {
  description = "Agent Runtime ID"
  value       = module.agent_runtime.agent_runtime_id
}

output "agent_runtime_arn" {
  description = "Agent Runtime ARN"
  value       = module.agent_runtime.agent_runtime_arn
}

output "agent_runtime_version" {
  description = "Agent Runtime version"
  value       = module.agent_runtime.agent_runtime_version
}

output "workload_identity_arn" {
  description = "Workload Identity ARN"
  value       = module.agent_runtime.workload_identity_arn
}

# IAM outputs
output "agent_runtime_role_arn" {
  description = "IAM role ARN for agent runtime"
  value       = module.iam.role_arn
}

output "agent_runtime_role_name" {
  description = "IAM role name for agent runtime"
  value       = module.iam.role_name
}

output "code_interpreter_role_arn" {
  description = "IAM role ARN for code interpreter"
  value       = module.iam.code_interpreter_role_arn
}

# Code Interpreter outputs
output "code_interpreter_id" {
  description = "Code Interpreter ID"
  value       = module.code_interpreter.code_interpreter_id
}

output "code_interpreter_arn" {
  description = "Code Interpreter ARN"
  value       = module.code_interpreter.code_interpreter_arn
}

output "code_interpreter_name" {
  description = "Code Interpreter name"
  value       = module.code_interpreter.name
}

# Browser outputs
output "browser_id" {
  description = "Browser ID"
  value       = module.browser.browser_id
}

output "browser_arn" {
  description = "Browser ARN"
  value       = module.browser.browser_arn
}

output "browser_name" {
  description = "Browser name"
  value       = module.browser.browser_name
}

output "browser_role_arn" {
  description = "IAM role ARN for browser"
  value       = module.iam.browser_role_arn
}

# Memory outputs
output "memory_id" {
  description = "Memory ID"
  value       = module.memory.memory_id
}

output "memory_arn" {
  description = "Memory ARN"
  value       = module.memory.memory_arn
}

output "memory_name" {
  description = "Memory name"
  value       = module.memory.memory_name
}

output "memory_execution_role_arn" {
  description = "IAM role ARN for memory execution"
  value       = module.iam.memory_execution_role_arn
}

output "semantic_strategy_id" {
  description = "SEMANTIC strategy ID"
  value       = module.memory.semantic_strategy_id
}

output "user_preference_strategy_id" {
  description = "USER_PREFERENCE strategy ID"
  value       = module.memory.user_preference_strategy_id
}

output "summarization_strategy_id" {
  description = "SUMMARIZATION strategy ID"
  value       = module.memory.summarization_strategy_id
}

# Gateway outputs
output "gateway_id" {
  description = "Gateway ID"
  value       = module.gateway.gateway_id
}

output "gateway_arn" {
  description = "Gateway ARN"
  value       = module.gateway.gateway_arn
}

output "gateway_url" {
  description = "Gateway URL endpoint"
  value       = module.gateway.gateway_url
}

output "gateway_role_arn" {
  description = "IAM role ARN for gateway"
  value       = module.iam.gateway_role_arn
}

output "tavily_target_id" {
  description = "Tavily Gateway Target ID"
  value       = module.gateway.tavily_target_id
}

output "tavily_credential_provider_arn" {
  description = "Tavily API Key Credential Provider ARN"
  value       = module.gateway.tavily_credential_provider_arn
}

# Instructions for next steps
output "next_steps" {
  description = "Instructions for deploying your agent"
  value       = <<-EOT
    Next steps to deploy your agent:

    1. Build and push your container image:
       cd ../agent
       ./build_and_push.sh ${module.ecr.repository_url}

    2. Update the agent runtime with the new image (if needed):
       terraform apply -var="container_image_uri=${module.ecr.repository_url}:v1.0.0"

    3. Invoke your agent using AWS SDK:
       aws bedrock-agent-runtime invoke-agent-runtime \
         --agent-runtime-id ${module.agent_runtime.agent_runtime_id} \
         --session-id $(uuidgen) \
         --input-text "Your prompt here"

    4. Add to .env file:
       MEMORY_ID=${module.memory.memory_id}
       TAVILY_GATEWAY_URL=${module.gateway.gateway_url}

    AWS CLI Login command:
       aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.repository_url}
  EOT
}
