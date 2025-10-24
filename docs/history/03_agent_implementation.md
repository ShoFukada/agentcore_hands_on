# Strands Agent Implementation

## 1. Install dependencies

```bash
uv add "strands-agents[otel]"
```

## 2. Update agent code

`src/agentcore_hands_on/agent.py` edit:

- Import: `from strands import Agent`, `from strands.models.bedrock import BedrockModel`
- Initialize Agent with BedrockModel
- Model: `global.anthropic.claude-haiku-4-5-20251001-v1:0`

## 3. Local test

### Start server

```bash
uv run uvicorn agentcore_hands_on.agent:app --host 0.0.0.0 --port 8080
```

### Health check

```bash
curl http://localhost:8080/ping
```

### Invoke agent

```bash
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"input": {"prompt": "Hello!"}, "session_id": "test"}'
```

## Troubleshooting

### AWS credentials

```bash
export AWS_PROFILE=239339588912_AdministratorAccess
aws sts get-caller-identity
```

### Reinstall

```bash
uv sync
```

## Next steps

1. Build Docker image
2. Push to ECR
3. Deploy with Terraform
4. Check CloudWatch logs
