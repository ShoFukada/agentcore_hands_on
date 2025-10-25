# Memory outputs

output "memory_id" {
  description = "ID of the memory resource"
  value       = aws_bedrockagentcore_memory.this.id
}

output "memory_arn" {
  description = "ARN of the memory resource"
  value       = aws_bedrockagentcore_memory.this.arn
}

output "memory_name" {
  description = "Name of the memory resource"
  value       = aws_bedrockagentcore_memory.this.name
}

output "semantic_strategy_id" {
  description = "ID of the SEMANTIC strategy"
  value       = var.create_semantic_strategy ? aws_bedrockagentcore_memory_strategy.semantic[0].memory_strategy_id : null
}

output "user_preference_strategy_id" {
  description = "ID of the USER_PREFERENCE strategy"
  value       = var.create_user_preference_strategy ? aws_bedrockagentcore_memory_strategy.user_preference[0].memory_strategy_id : null
}

output "summarization_strategy_id" {
  description = "ID of the SUMMARIZATION strategy"
  value       = var.create_summarization_strategy ? aws_bedrockagentcore_memory_strategy.summarization[0].memory_strategy_id : null
}
