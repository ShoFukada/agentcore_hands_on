# Gateway Outputs
output "gateway_id" {
  description = "Unique identifier of the Gateway"
  value       = aws_bedrockagentcore_gateway.main.gateway_id
}

output "gateway_arn" {
  description = "ARN of the Gateway"
  value       = aws_bedrockagentcore_gateway.main.gateway_arn
}

output "gateway_url" {
  description = "URL endpoint for the Gateway"
  value       = aws_bedrockagentcore_gateway.main.gateway_url
}

output "gateway_name" {
  description = "Name of the Gateway"
  value       = aws_bedrockagentcore_gateway.main.name
}

# Gateway Target Outputs
output "tavily_target_id" {
  description = "Unique identifier of the Tavily Gateway Target"
  value       = aws_bedrockagentcore_gateway_target.tavily.target_id
}

output "tavily_target_name" {
  description = "Name of the Tavily Gateway Target"
  value       = aws_bedrockagentcore_gateway_target.tavily.name
}

# Credential Provider Outputs
output "tavily_credential_provider_arn" {
  description = "ARN of the Tavily API Key Credential Provider"
  value       = aws_bedrockagentcore_api_key_credential_provider.tavily.credential_provider_arn
}

output "tavily_credential_provider_name" {
  description = "Name of the Tavily API Key Credential Provider"
  value       = aws_bedrockagentcore_api_key_credential_provider.tavily.name
}

output "tavily_api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret for Tavily API Key"
  value       = aws_bedrockagentcore_api_key_credential_provider.tavily.api_key_secret_arn[0].secret_arn
}
