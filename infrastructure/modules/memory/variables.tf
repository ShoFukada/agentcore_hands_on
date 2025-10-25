# Memory variables

variable "name" {
  description = "Name of the memory resource"
  type        = string
}

variable "description" {
  description = "Description of the memory resource"
  type        = string
  default     = ""
}

variable "event_expiry_duration" {
  description = "Number of days after which memory events expire (Short-term memory retention)"
  type        = number
  default     = 90
}

variable "memory_execution_role_arn" {
  description = "ARN of the IAM role that the memory service uses for model inference"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the memory resource"
  type        = map(string)
  default     = {}
}

# SEMANTIC Strategy
variable "create_semantic_strategy" {
  description = "Whether to create a SEMANTIC memory strategy"
  type        = bool
  default     = true
}

variable "semantic_strategy_name" {
  description = "Name of the SEMANTIC strategy"
  type        = string
  default     = "semantic_builtin"
}

variable "semantic_strategy_description" {
  description = "Description of the SEMANTIC strategy"
  type        = string
  default     = "Extract technical knowledge and facts from conversations"
}

variable "semantic_namespaces" {
  description = "Namespaces for SEMANTIC strategy"
  type        = list(string)
  default     = ["agent_assistant/knowledge/{actorId}"]
}

# USER_PREFERENCE Strategy
variable "create_user_preference_strategy" {
  description = "Whether to create a USER_PREFERENCE memory strategy"
  type        = bool
  default     = true
}

variable "user_preference_strategy_name" {
  description = "Name of the USER_PREFERENCE strategy"
  type        = string
  default     = "preference_builtin"
}

variable "user_preference_strategy_description" {
  description = "Description of the USER_PREFERENCE strategy"
  type        = string
  default     = "Track user preferences and behavioral patterns"
}

variable "user_preference_namespaces" {
  description = "Namespaces for USER_PREFERENCE strategy"
  type        = list(string)
  default     = ["agent_assistant/preferences/{actorId}"]
}

# SUMMARIZATION Strategy
variable "create_summarization_strategy" {
  description = "Whether to create a SUMMARIZATION memory strategy"
  type        = bool
  default     = true
}

variable "summarization_strategy_name" {
  description = "Name of the SUMMARIZATION strategy"
  type        = string
  default     = "summary_builtin"
}

variable "summarization_strategy_description" {
  description = "Description of the SUMMARIZATION strategy"
  type        = string
  default     = "Generate session summaries with key insights"
}

variable "summarization_namespaces" {
  description = "Namespaces for SUMMARIZATION strategy"
  type        = list(string)
  default     = ["agent_assistant/summaries/{actorId}/{sessionId}"]
}
