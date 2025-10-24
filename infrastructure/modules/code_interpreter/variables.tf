variable "name" {
  description = "Name of the code interpreter"
  type        = string
}

variable "description" {
  description = "Description of the code interpreter"
  type        = string
  default     = ""
}

variable "execution_role_arn" {
  description = "ARN of the IAM role for code interpreter execution (required for SANDBOX mode)"
  type        = string
}

variable "network_mode" {
  description = "Network mode for the code interpreter (PUBLIC, SANDBOX, or VPC)"
  type        = string
  default     = "SANDBOX"

  validation {
    condition     = contains(["PUBLIC", "SANDBOX", "VPC"], var.network_mode)
    error_message = "Network mode must be one of: PUBLIC, SANDBOX, VPC"
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
