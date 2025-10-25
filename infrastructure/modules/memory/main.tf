# AgentCore Memory Resource

resource "aws_bedrockagentcore_memory" "this" {
  name                      = var.name
  description               = var.description
  event_expiry_duration     = var.event_expiry_duration
  memory_execution_role_arn = var.memory_execution_role_arn

  tags = var.tags
}

# Memory Strategy - SEMANTIC
resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  count = var.create_semantic_strategy ? 1 : 0

  name        = var.semantic_strategy_name
  memory_id   = aws_bedrockagentcore_memory.this.id
  type        = "SEMANTIC"
  description = var.semantic_strategy_description

  namespaces = var.semantic_namespaces

  depends_on = [aws_bedrockagentcore_memory.this]
}

# Memory Strategy - USER_PREFERENCE
resource "aws_bedrockagentcore_memory_strategy" "user_preference" {
  count = var.create_user_preference_strategy ? 1 : 0

  name        = var.user_preference_strategy_name
  memory_id   = aws_bedrockagentcore_memory.this.id
  type        = "USER_PREFERENCE"
  description = var.user_preference_strategy_description

  namespaces = var.user_preference_namespaces

  depends_on = [aws_bedrockagentcore_memory.this]
}

# Memory Strategy - SUMMARIZATION
resource "aws_bedrockagentcore_memory_strategy" "summarization" {
  count = var.create_summarization_strategy ? 1 : 0

  name        = var.summarization_strategy_name
  memory_id   = aws_bedrockagentcore_memory.this.id
  type        = "SUMMARIZATION"
  description = var.summarization_strategy_description

  namespaces = var.summarization_namespaces

  depends_on = [aws_bedrockagentcore_memory.this]
}
