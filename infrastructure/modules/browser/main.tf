# AWS Bedrock AgentCore Browser resource

resource "aws_bedrockagentcore_browser" "main" {
  name               = var.name
  description        = var.description
  execution_role_arn = var.execution_role_arn

  network_configuration {
    network_mode = var.network_mode
  }

  tags = var.tags
}
