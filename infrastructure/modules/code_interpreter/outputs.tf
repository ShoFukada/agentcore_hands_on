output "code_interpreter_arn" {
  description = "ARN of the code interpreter"
  value       = aws_bedrockagentcore_code_interpreter.main.code_interpreter_arn
}

output "code_interpreter_id" {
  description = "Unique identifier of the code interpreter"
  value       = aws_bedrockagentcore_code_interpreter.main.code_interpreter_id
}

output "name" {
  description = "Name of the code interpreter"
  value       = aws_bedrockagentcore_code_interpreter.main.name
}
