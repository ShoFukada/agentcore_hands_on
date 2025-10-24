# Simple Agent Runtime resource

resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = var.agent_runtime_name
  description        = var.description
  role_arn           = var.role_arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_uri
    }
  }

  environment_variables = merge(
    var.environment_variables,
    var.code_interpreter_id != "" ? {
      CODE_INTERPRETER_ID = var.code_interpreter_id
    } : {}
  )

  network_configuration {
    network_mode = var.network_mode
  }

  protocol_configuration {
    server_protocol = var.server_protocol
  }

  tags = var.tags
}

# Agent Runtime Endpoint
resource "aws_bedrockagentcore_agent_runtime_endpoint" "main" {
  count = var.create_endpoint ? 1 : 0

  name             = var.endpoint_name
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.main.agent_runtime_id
  description      = var.endpoint_description

  tags = var.tags
}
