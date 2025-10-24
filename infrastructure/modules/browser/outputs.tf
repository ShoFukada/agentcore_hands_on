output "browser_arn" {
  description = "ARN of the Browser"
  value       = aws_bedrockagentcore_browser.main.browser_arn
}

output "browser_id" {
  description = "ID of the Browser"
  value       = aws_bedrockagentcore_browser.main.browser_id
}

output "browser_name" {
  description = "Name of the Browser"
  value       = aws_bedrockagentcore_browser.main.name
}
