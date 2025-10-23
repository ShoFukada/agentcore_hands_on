output "role_arn" {
  description = "ARN of the IAM role for agent runtime"
  value       = aws_iam_role.agent_runtime.arn
}

output "role_id" {
  description = "ID of the IAM role for agent runtime"
  value       = aws_iam_role.agent_runtime.id
}

output "role_name" {
  description = "Name of the IAM role for agent runtime"
  value       = aws_iam_role.agent_runtime.name
}

output "policy_id" {
  description = "ID of the IAM policy for agent runtime"
  value       = aws_iam_role_policy.agent_runtime.id
}
