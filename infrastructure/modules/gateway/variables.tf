variable "gateway_name" {
  description = "Name of the AgentCore Gateway"
  type        = string
  default     = "agentcore-gateway"
}

variable "gateway_role_arn" {
  description = "ARN of the IAM role for the Gateway"
  type        = string
}

variable "description" {
  description = "Description of the Gateway"
  type        = string
  default     = "AgentCore Gateway for MCP tools integration"
}

variable "protocol_type" {
  description = "Protocol type for the Gateway"
  type        = string
  default     = "MCP"
}

variable "authorizer_type" {
  description = "Type of authorizer (AWS_IAM or CUSTOM_JWT)"
  type        = string
  default     = "AWS_IAM"
}

# JWT Authorizer Configuration (only for CUSTOM_JWT)
variable "jwt_discovery_url" {
  description = "Discovery URL for JWT authorizer (required when authorizer_type is CUSTOM_JWT)"
  type        = string
  default     = null
}

variable "jwt_allowed_audience" {
  description = "Allowed audience values for JWT token validation"
  type        = set(string)
  default     = null
}

variable "jwt_allowed_clients" {
  description = "Allowed client IDs for JWT token validation"
  type        = set(string)
  default     = null
}

# Tavily API Key Configuration
variable "tavily_api_key" {
  description = "Tavily API Key for search functionality"
  type        = string
  sensitive   = true
}

variable "tavily_credential_provider_name" {
  description = "Name of the Tavily API Key Credential Provider"
  type        = string
  default     = "tavily-api-key-provider"
}

# Gateway Target Configuration
variable "tavily_target_name" {
  description = "Name of the Tavily Gateway Target"
  type        = string
  default     = "tavily-search-target"
}

variable "tavily_target_description" {
  description = "Description of the Tavily Gateway Target"
  type        = string
  default     = "Tavily search API integration via OpenAPI"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
