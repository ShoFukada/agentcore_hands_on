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

output "code_interpreter_role_arn" {
  description = "ARN of the IAM role for code interpreter"
  value       = var.create_code_interpreter_role ? aws_iam_role.code_interpreter[0].arn : null
}

output "code_interpreter_role_id" {
  description = "ID of the IAM role for code interpreter"
  value       = var.create_code_interpreter_role ? aws_iam_role.code_interpreter[0].id : null
}

output "code_interpreter_role_name" {
  description = "Name of the IAM role for code interpreter"
  value       = var.create_code_interpreter_role ? aws_iam_role.code_interpreter[0].name : null
}

output "browser_role_arn" {
  description = "ARN of the IAM role for browser"
  value       = var.create_browser_role ? aws_iam_role.browser[0].arn : null
}

output "browser_role_id" {
  description = "ID of the IAM role for browser"
  value       = var.create_browser_role ? aws_iam_role.browser[0].id : null
}

output "browser_role_name" {
  description = "Name of the IAM role for browser"
  value       = var.create_browser_role ? aws_iam_role.browser[0].name : null
}

output "memory_execution_role_arn" {
  description = "ARN of the IAM role for memory execution"
  value       = var.create_memory_execution_role ? aws_iam_role.memory_execution[0].arn : null
}

output "memory_execution_role_id" {
  description = "ID of the IAM role for memory execution"
  value       = var.create_memory_execution_role ? aws_iam_role.memory_execution[0].id : null
}

output "memory_execution_role_name" {
  description = "Name of the IAM role for memory execution"
  value       = var.create_memory_execution_role ? aws_iam_role.memory_execution[0].name : null
}
