output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.agent.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.agent.arn
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.agent.name
}

output "registry_id" {
  description = "Registry ID where the repository was created"
  value       = aws_ecr_repository.agent.registry_id
}
