# Variables for AgentCore infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "agentcore-hands-on"
}

variable "agent_name" {
  description = "Name of the agent"
  type        = string
  default     = "my-agent"
}

variable "container_image_uri" {
  description = "Container image URI (if empty, will use ECR repository URL with :latest tag)"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Log level for the agent runtime"
  type        = string
  default     = "INFO"
}

variable "image_tag" {
  description = "Container image tag (version)"
  type        = string
  default     = "v1.0.0"
}

variable "agent_runtime_id" {
  description = "Agent Runtime ID (required for Observability configuration after initial deployment)"
  type        = string
  default     = ""
}
