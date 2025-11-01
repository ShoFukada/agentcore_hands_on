aws_region       = "us-east-1"
environment      = "dev"
project_name     = "agentcore-hands-on"
agent_name       = "my-agent"

# agent update時に更新
image_tag        = "v1.1.4"

# 初回デプロイ後に付与
agent_runtime_id = ""
agent_runtime_endpoint_qualifier = "DEFAULT"

# Memory configuration
memory_retention_days          = 90
memory_enable_semantic         = true
memory_enable_user_preference  = true
memory_enable_summarization    = true

# Gateway configuration
tavily_api_key = "your-tavily-api-key-here"
