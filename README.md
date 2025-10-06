# uv-python-starter-template

A modern Python project template using uv package manager with development best practices.

## Overview

This is a starter template for Python projects that includes:
- Modern dependency management with uv
- Pre-configured development tools (ruff, pyright, pytest)
- Pydantic settings for configuration management
- Pre-commit hooks for code quality
- Testing setup with pytest and coverage

## Usage

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd uv-python-starter-template

# Install dependencies
uv sync

# Install development dependencies
uv sync --dev
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

### Running the application

```bash
uv run uv-python-starter-template
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