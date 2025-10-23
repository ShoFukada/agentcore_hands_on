output "agent_runtime_id" {
  description = "ID of the agent runtime"
  value       = aws_bedrockagentcore_agent_runtime.main.agent_runtime_id
}

output "agent_runtime_arn" {
  description = "ARN of the agent runtime"
  value       = aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn
}

output "agent_runtime_version" {
  description = "Version of the agent runtime"
  value       = aws_bedrockagentcore_agent_runtime.main.agent_runtime_version
}

output "workload_identity_arn" {
  description = "ARN of the workload identity"
  value       = try(aws_bedrockagentcore_agent_runtime.main.workload_identity_details[0].workload_identity_arn, null)
}

output "endpoint_arn" {
  description = "ARN of the agent runtime endpoint"
  value       = try(aws_bedrockagentcore_agent_runtime_endpoint.main[0].agent_runtime_endpoint_arn, null)
}

output "endpoint_agent_runtime_arn" {
  description = "ARN of the agent runtime associated with the endpoint"
  value       = try(aws_bedrockagentcore_agent_runtime_endpoint.main[0].agent_runtime_arn, null)
}
