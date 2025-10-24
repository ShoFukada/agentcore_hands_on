variable "agent_runtime_name" {
  description = "Name of the agent runtime"
  type        = string
}

variable "description" {
  description = "Description of the agent runtime"
  type        = string
  default     = ""
}

variable "role_arn" {
  description = "ARN of the IAM role that the agent runtime assumes"
  type        = string
}

variable "container_uri" {
  description = "URI of the container image in ECR"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables for the agent runtime container"
  type        = map(string)
  default     = {}
}

variable "network_mode" {
  description = "Network mode for the agent runtime (PUBLIC or VPC)"
  type        = string
  default     = "PUBLIC"
}

variable "server_protocol" {
  description = "Server protocol for the agent runtime"
  type        = string
  default     = "HTTP"
}

variable "create_endpoint" {
  description = "Whether to create an agent runtime endpoint"
  type        = bool
  default     = true
}

variable "endpoint_name" {
  description = "Name of the agent runtime endpoint"
  type        = string
  default     = ""
}

variable "endpoint_description" {
  description = "Description of the agent runtime endpoint"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "code_interpreter_id" {
  description = "Code Interpreter ID to set as environment variable"
  type        = string
  default     = ""
}
