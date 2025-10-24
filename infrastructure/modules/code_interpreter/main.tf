# Code Interpreter resource for sandboxed Python code execution

resource "aws_bedrockagentcore_code_interpreter" "main" {
  name               = var.name
  description        = var.description
  execution_role_arn = var.execution_role_arn

  network_configuration {
    network_mode = var.network_mode
  }

  tags = var.tags
}
