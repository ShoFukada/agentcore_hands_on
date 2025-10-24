variable "name" {
  description = "Name of the Browser"
  type        = string
}

variable "description" {
  description = "Description of the Browser"
  type        = string
  default     = ""
}

variable "execution_role_arn" {
  description = "ARN of the IAM role for Browser execution"
  type        = string
}

variable "network_mode" {
  description = "Network mode for the Browser (PUBLIC or SANDBOX)"
  type        = string
  default     = "PUBLIC"

  validation {
    condition     = contains(["PUBLIC", "SANDBOX"], var.network_mode)
    error_message = "Network mode must be either PUBLIC or SANDBOX"
  }
}

variable "tags" {
  description = "Tags to apply to the Browser"
  type        = map(string)
  default     = {}
}
