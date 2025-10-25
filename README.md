# AgentCore Hands-on

AWS Bedrock AgentCore Runtime with Strands and OpenTelemetry.

## Overview

This project demonstrates:
- AWS Bedrock AgentCore Runtime deployment
- Strands AI agent framework with OpenTelemetry support
- **AgentCore Memory integration for conversation persistence**
- Code Interpreter and Browser tools integration
- Infrastructure as Code with Terraform
- Observability with CloudWatch

## Quick Start

### Installation

```bash
# Install dependencies
uv sync

# Copy environment file and configure
cp .env.example .env
# Edit .env with your AWS credentials and AgentCore resource IDs
```

### Configuration

Get your AgentCore resource IDs from Terraform outputs:

```bash
cd infrastructure
terraform output
```

Add the following to your `.env` file:
```env
CODE_INTERPRETER_ID=<from terraform output>
BROWSER_ID=<from terraform output>
MEMORY_ID=<from terraform output>  # Set to enable Memory integration
```

### Local Testing

Agent をローカルで実行してテストする:

```bash
# Agent サーバーを起動
uv run uvicorn agentcore_hands_on.agent:app --host 0.0.0.0 --port 8080

# 別のターミナルで動作確認
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"input": {"prompt": "Hello, Agent!"}, "session_id": "test-session", "actor_id": "user-123"}'

# Memory統合のテスト（複数回のやり取りで会話が保存される）
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"input": {"prompt": "My name is Alice"}, "session_id": "conversation-1", "actor_id": "user-123"}'

curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"input": {"prompt": "What is my name?"}, "session_id": "conversation-1", "actor_id": "user-123"}'

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

## Features

### AgentCore Memory Integration

The agent supports conversation memory persistence using AWS Bedrock AgentCore Memory:

- **Session-based memory**: Conversations are tracked by `session_id`
- **User-based memory**: User context is tracked by `actor_id`
- **Automatic persistence**: All conversations are automatically saved when `MEMORY_ID` is set
- **Memory strategies**: Supports SEMANTIC, SUMMARIZATION, and USER_PREFERENCE strategies

**Memory Configuration:**
- Set `MEMORY_ID` in `.env` to enable (leave empty to disable)
- Use `session_id` to group related conversations
- Use `actor_id` to identify different users
- Memory is shared across sessions for the same actor

**Example:**
```json
{
  "input": {"prompt": "Remember that I like Python"},
  "session_id": "chat-001",
  "actor_id": "user-alice"
}
```

### Code Interpreter

Execute Python code in a sandboxed environment:
- Data analysis and calculations
- File processing
- Code execution with safety

### Browser

Automate web browsing tasks:
- Visit URLs and extract content
- Get page titles and text
- Interact with web pages

## Project Structure

```
.
├── src/
│   └── agentcore_hands_on/
│       ├── __init__.py
│       ├── agent.py           # Main agent with Memory integration
│       ├── config.py           # Configuration with Memory settings
│       └── invoke_agent.py
├── infrastructure/
│   ├── modules/
│   │   ├── memory/            # AgentCore Memory Terraform module
│   │   ├── agent_runtime/
│   │   ├── code_interpreter/
│   │   └── browser/
│   └── main.tf
├── docs/
│   ├── chat/memory/           # Memory IAM documentation
│   └── terraform_docs/        # Terraform resource docs
├── tests/
├── pyproject.toml
└── .env.example
```

## Requirements

- Python >= 3.12
- uv package manager

## License

MIT License
