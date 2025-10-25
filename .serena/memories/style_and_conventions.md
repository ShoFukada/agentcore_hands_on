## Style and Conventions
- Python 3.12 project managed with `uv`; package source under `src/` using standard package/module layout.
- Ruff enforces linting (`select = ["ALL"]`) with line length 120; docstring, TODO, and some exception rules ignored. Ruff format used for code formatting.
- Type checking via Pyright in standard mode; tests may omit annotations (`ANN` ignored).
- Uses Pydantic Settings for configuration; environment variables loaded in `Settings` class.
- Logging configured via standard library logging; JSON handling aims to preserve non-ASCII text with `ensure_ascii=False`.