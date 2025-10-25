## Project Overview
- AWS Bedrock AgentCore runtime sample that integrates Strands agent framework, AgentCore Memory, Code Interpreter, Browser tool, and OpenTelemetry.
- FastAPI-based service exposing `/ping` and `/invocations` to run the agent locally or in AWS AgentCore runtime.
- Infrastructure managed via Terraform modules under `infrastructure/` for runtime, memory, code interpreter, and browser resources.
- Observability targets CloudWatch (logs, metrics) via aws-opentelemetry-distro.
- Python package located in `src/agentcore_hands_on`; docs, scripts, and Terraform support directories provided.