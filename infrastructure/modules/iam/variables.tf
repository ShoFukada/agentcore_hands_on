variable "role_name" {
  description = "Name of the IAM role for agent runtime"
  type        = string
}

variable "policy_name" {
  description = "Name of the IAM policy for agent runtime"
  type        = string
}

variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs that the agent runtime can access"
  type        = list(string)
}

variable "enable_bedrock_invoke" {
  description = "Enable Bedrock model invocation permissions"
  type        = bool
  default     = true
}

variable "bedrock_model_arns" {
  description = "List of Bedrock model ARNs that the agent runtime can invoke"
  type        = list(string)
  default     = []
}

variable "additional_policy_statements" {
  description = "Additional IAM policy statements to add to the agent runtime role"
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to the IAM role"
  type        = map(string)
  default     = {}
}
