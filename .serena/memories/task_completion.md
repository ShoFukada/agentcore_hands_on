## Task Completion Checklist
- Run applicable quality gates (`uv run pytest`, `uv run ruff check .`, `uv run pyright`) before handing off changes.
- For features impacting infrastructure, run or plan Terraform (`terraform plan`) and capture expected diffs.
- Update documentation in `docs/` or `README.md` when behavior or configuration changes.
- Ensure `.env` example values remain accurate after configuration changes.
- When observability or AWS integrations are touched, confirm CloudWatch/X-Ray outputs as part of validation.