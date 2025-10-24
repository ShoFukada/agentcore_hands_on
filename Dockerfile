# ARM64用のDockerfile (uv対応)

FROM --platform=linux/arm64 ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

# uvの環境変数設定
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# 依存関係ファイルをコピー
COPY pyproject.toml uv.lock ./

# 依存関係のみをインストール（キャッシュ効率化）
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

# ソースコードをコピー
COPY . .

# プロジェクト自体をインストール
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# 実行用の最小イメージ
FROM --platform=linux/arm64 python:3.12-slim

# 実行時に必要な最小限のパッケージ
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ビルドステージから仮想環境をコピー
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src /app/src

# PATH に仮想環境を追加
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# ポート8080を公開
EXPOSE 8080

# アプリケーションの起動
# opentelemetry-instrument で起動して CloudWatch Logs にログを送信
CMD ["opentelemetry-instrument", "uvicorn", "agentcore_hands_on.agent:app", "--host", "0.0.0.0", "--port", "8080", "--log-level", "info"]
