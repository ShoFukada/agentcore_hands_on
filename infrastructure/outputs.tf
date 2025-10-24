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

    AWS CLI Login command:
       aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.repository_url}
  EOT
}
