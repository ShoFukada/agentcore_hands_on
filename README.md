# AgentCore Hands-on

AWS Bedrock AgentCore Runtime with Strands and OpenTelemetry.

## Overview

This project demonstrates:
- AWS Bedrock AgentCore Runtime deployment
- Strands AI agent framework with OpenTelemetry support
- Infrastructure as Code with Terraform
- Observability with CloudWatch

## Quick Start

### Installation

```bash
# Install dependencies
uv sync
```

### Local Testing

Agent をローカルで実行してテストする:

```bash
# Agent サーバーを起動
uv run uvicorn agentcore_hands_on.agent:app --host 0.0.0.0 --port 8080

# 別のターミナルで動作確認
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"input": {"prompt": "Hello, Agent!"}, "session_id": "test-session"}'

# ヘルスチェック
curl http://localhost:8080/ping
```

### Development

```bash
# Run tests
uv run pytest

# Run linting
uv run ruff check .

# Run type checking
uv run pyright

# Format code
uv run ruff format .
```

## Project Structure

```
.
├── src/
│   └── uv_python_starter_template/
│       ├── __init__.py
│       ├── calculator.py
│       └── config.py
├── tests/
├── pyproject.toml
└── uv.lock
```

## Requirements

- Python >= 3.12
- uv package manager

## License

MIT License
