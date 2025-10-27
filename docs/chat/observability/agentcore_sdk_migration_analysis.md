# AgentCore SDK移行とObservability環境変数の分析

## 概要

本ドキュメントでは、現在のFastAPI実装からAgentCore SDKへの移行方法と、AgentCore Runtime環境におけるObservability設定（OTEL環境変数）の必要性について分析します。

## 参照ドキュメント

- [AWS Bedrock AgentCore Observability Getting Started](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-get-started.html)
- [GitHub: AgentCore Runtime with Strands Sample](https://github.com/awslabs/amazon-bedrock-agentcore-samples/blob/main/01-tutorials/06-AgentCore-observability/01-Agentcore-runtime-hosted/Strands%20Agents/runtime_with_strands_and_bedrock_models.ipynb)

## 1. AgentCore SDKへの移行

### 1.1 現在の実装（FastAPI）

```python
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="Strands Agent Runtime")

@app.get("/ping")
def health_check() -> dict[str, str]:
    return {"status": "healthy"}

@app.post("/invocations")
def invoke(request: InvocationRequest) -> InvocationResponse:
    # エージェント処理
    agent = create_agent(...)
    response = agent(prompt)
    return InvocationResponse(output={"response": response})

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

### 1.2 推奨される実装（AgentCore SDK）

```python
from bedrock_agentcore.runtime import BedrockAgentCoreApp

app = BedrockAgentCoreApp()

@app.entrypoint
def handler(input_data: dict, context: dict) -> dict:
    """AgentCore Runtimeのエントリーポイント"""
    prompt = input_data.get("prompt", "")
    session_id = input_data.get("session_id")
    actor_id = input_data.get("actor_id")

    # エージェント処理
    agent = create_agent(session_id=session_id, actor_id=actor_id)
    response = agent(prompt)

    return {"response": str(response)}

if __name__ == "__main__":
    app.run()
```

### 1.3 主な変更点

| 項目 | FastAPI実装 | AgentCore SDK実装 |
|------|------------|------------------|
| HTTPエンドポイント | 手動実装（/ping, /invocations） | 自動提供（Runtimeが管理） |
| リクエスト/レスポンス処理 | Pydanticモデルで明示的に定義 | dict型で暗黙的に処理 |
| サーバー起動 | uvicornで明示的に起動 | `app.run()`で自動起動 |
| デコレーター | `@app.get()`, `@app.post()` | `@app.entrypoint` |
| ヘルスチェック | 手動実装が必要 | Runtimeが自動提供 |

### 1.4 Dockerfileの変更

**現在：**
```dockerfile
CMD ["opentelemetry-instrument", "uvicorn", "agentcore_hands_on.agent:app", "--host", "0.0.0.0", "--port", "8080", "--log-level", "info"]
```

**推奨：**
```dockerfile
CMD ["opentelemetry-instrument", "python", "agentcore_hands_on/agent.py"]
```

## 2. Observability環境変数の分析

### 2.1 結論：手動設定は不要

**重要な発見：AgentCore Runtime-hosted agentsでは、OTEL環境変数の手動設定は不要です。**

AWS公式ドキュメントより：
> "Amazon Bedrock AgentCore Runtime-hosted agents are deployed and executed directly within the Amazon Bedrock AgentCore environment, providing automatic instrumentation with minimal configuration."
>
> "When deploying via the starter toolkit, you simply ensure that aws-opentelemetry-distro is included in your requirements.txt file. The runtime handles the OTEL pipeline automatically—no manual environment variable configuration is needed."

### 2.2 必要な設定

AgentCore Runtimeにデプロイする場合、以下のみが必要です：

1. **依存関係に`aws-opentelemetry-distro`を含める**
   ```toml
   dependencies = [
       "aws-opentelemetry-distro>=0.12.1",
       # その他の依存関係
   ]
   ```
   ✅ 現在のプロジェクトには既に含まれています（pyproject.toml:12）

2. **Dockerfileで`opentelemetry-instrument`を使用**
   ```dockerfile
   CMD ["opentelemetry-instrument", "python", "agentcore_hands_on/agent.py"]
   ```
   ✅ 現在のDockerfileで既に実装されています（Dockerfile:49）

### 2.3 現在のTerraform設定の評価

#### 不要と判断される環境変数

`infrastructure/main.tf`の以下の環境変数は、AgentCore Runtimeでは**自動的に設定される**ため、手動設定は不要です：

```hcl
# 128-150行目の以下の変数は削除可能
AGENT_OBSERVABILITY_ENABLED = "true"              # ✅ Runtime自動設定
OTEL_PYTHON_DISTRO = "aws_distro"                 # ✅ Runtime自動設定
OTEL_PYTHON_CONFIGURATOR = "aws_configurator"     # ✅ Runtime自動設定
OTEL_RESOURCE_ATTRIBUTES = "..."                  # ✅ Runtime自動設定
OTEL_EXPORTER_OTLP_LOGS_HEADERS = "..."          # ✅ Runtime自動設定
OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"    # ✅ Runtime自動設定
OTEL_TRACES_EXPORTER = "otlp"                    # ✅ Runtime自動設定
OTEL_TRACES_SAMPLER = "always_on"                # ✅ Runtime自動設定
```

#### 保持すべき環境変数

アプリケーション固有の設定は保持する必要があります：

```hcl
# アプリケーション設定（必要）
LOG_LEVEL = var.log_level
ENVIRONMENT = var.environment

# AgentCore リソースID（必要）
CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id
BROWSER_ID = module.browser.browser_id
MEMORY_ID = module.memory.memory_id

# Gateway設定（必要）
TAVILY_GATEWAY_URL = module.gateway.gateway_url
```

### 2.4 手動設定が必要なケース

OTEL環境変数の手動設定が必要なのは、以下のケースのみです：

1. **AgentCore Runtimeの外で実行する場合**
   - ローカル開発環境
   - EC2やECS等の独自コンテナ環境
   - Lambda（AgentCore Runtime以外）

2. **カスタム設定が必要な場合**
   - デフォルトと異なるロググループを使用
   - カスタムメトリクスネームスペース
   - 特定のサンプリングレート

### 2.5 CloudWatch Logs設定について

**重要：** 現在のTerraform設定では、ログストリーム名やロググループ名を環境変数で指定していますが、これも不要です。

```hcl
# 138行目 - 不要な可能性が高い
OTEL_RESOURCE_ATTRIBUTES = "service.name=${var.agent_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-${var.agent_runtime_endpoint_qualifier},cloud.resource_id=${var.agent_runtime_id}"

# 142行目 - 不要な可能性が高い
OTEL_EXPORTER_OTLP_LOGS_HEADERS = "x-aws-log-group=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-${var.agent_runtime_endpoint_qualifier},x-aws-metric-namespace=bedrock-agentcore"
```

**理由：**
- AgentCore Runtimeは自動的にロググループとログストリームを作成・管理します
- デフォルトのロググループ名は `/aws/bedrock-agentcore/runtimes/<runtime-id>` の形式
- カスタマイズが必要な場合を除き、デフォルトを使用することを推奨

## 3. 推奨される移行手順

### 3.1 コード変更

1. **agent.pyの更新**
   - FastAPIからAgentCore SDKに変更
   - `@app.entrypoint`デコレーターを使用
   - HTTPエンドポイント実装を削除（Runtimeが自動提供）

2. **Dockerfileの更新**
   - CMD行を簡略化（uvicorn削除）
   - `opentelemetry-instrument python agentcore_hands_on/agent.py`

3. **pyproject.tomlの更新**
   - `fastapi`と`uvicorn`の依存関係を削除可能
   - `bedrock-agentcore`は保持（既に含まれている）

### 3.2 Terraform変更

`infrastructure/main.tf`の`environment_variables`セクションを簡素化：

```hcl
environment_variables = merge(
  {
    # アプリケーション設定のみ
    LOG_LEVEL   = var.log_level
    ENVIRONMENT = var.environment

    # AgentCore リソース
    CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id
    BROWSER_ID = module.browser.browser_id
    MEMORY_ID = module.memory.memory_id

    # Gateway
    TAVILY_GATEWAY_URL = module.gateway.gateway_url
  }
)
```

**削除可能な設定：**
- `AGENT_OBSERVABILITY_ENABLED`
- `OTEL_PYTHON_DISTRO`
- `OTEL_PYTHON_CONFIGURATOR`
- `OTEL_RESOURCE_ATTRIBUTES`
- `OTEL_EXPORTER_OTLP_LOGS_HEADERS`
- `OTEL_EXPORTER_OTLP_PROTOCOL`
- `OTEL_TRACES_EXPORTER`
- `OTEL_TRACES_SAMPLER`

### 3.3 検証手順

1. **ローカルテスト**
   ```bash
   # 環境変数を設定せずに実行
   python src/agentcore_hands_on/agent.py
   ```

2. **コンテナビルド**
   ```bash
   docker build -t agentcore-test .
   docker run -p 8080:8080 agentcore-test
   ```

3. **AgentCore Runtimeへデプロイ**
   ```bash
   cd infrastructure
   terraform plan
   terraform apply
   ```

4. **Observability確認**
   - CloudWatch Logsで `/aws/bedrock-agentcore/runtimes/<runtime-id>` を確認
   - X-Rayでトレースが自動的に収集されていることを確認
   - CloudWatch Metricsで `bedrock-agentcore` ネームスペースを確認

## 4. まとめ

### 4.1 FastAPIからAgentCore SDKへの移行

| メリット | 説明 |
|---------|------|
| コードの簡素化 | HTTPエンドポイント実装が不要 |
| 自動ヘルスチェック | /pingエンドポイントが自動提供 |
| 標準化 | AWS推奨のパターンに準拠 |
| 保守性向上 | Runtimeのアップデートで自動的に機能改善 |

### 4.2 Observability環境変数について

**結論：AgentCore Runtimeでは手動設定不要**

- ✅ `aws-opentelemetry-distro`を依存関係に含める
- ✅ `opentelemetry-instrument`でアプリケーションを起動
- ❌ OTEL環境変数の手動設定は不要
- ❌ ロググループ/ログストリーム名の指定は不要

**理由：**
1. AgentCore Runtimeが自動的にOpenTelemetryパイプラインを設定
2. CloudWatch Logs、X-Ray、CloudWatch Metricsへの送信が自動化
3. リソース属性やエクスポーター設定も自動構成

**手動設定が必要な唯一のケース：**
- AgentCore Runtime外（ローカル、EC2、ECS等）で実行する場合のみ

### 4.3 次のアクション

1. [ ] `agent.py`をAgentCore SDKに移行
2. [ ] `infrastructure/main.tf`からOTEL環境変数を削除
3. [ ] Dockerfileを簡素化
4. [ ] `pyproject.toml`から不要な依存関係を削除
5. [ ] デプロイ後にCloudWatch Logsで動作確認

## 5. 参考資料

- [AgentCore Observability Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-get-started.html)
- [Strands Agents Documentation](https://strandsagents.com/)
- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)
