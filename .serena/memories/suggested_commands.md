## Suggested Commands
- `uv sync` — install project and dev dependencies.
- `uv run uvicorn agentcore_hands_on.agent:app --host 0.0.0.0 --port 8080` — start the FastAPI agent locally.
- `uv run pytest` — execute test suite (configured via Pytest with coverage settings).
- `uv run ruff check .` — lint codebase.
- `uv run ruff format .` — apply formatting.
- `uv run pyright` — run static type checks.
- `cd infrastructure && terraform init` — initialize Terraform modules.
- `cd infrastructure && terraform apply` — deploy/update AWS resources.
- `scripts/build_and_push.sh` — build and push images/artifacts (custom script; review before running).