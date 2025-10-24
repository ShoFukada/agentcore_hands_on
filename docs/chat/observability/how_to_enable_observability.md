# 現在のコードで Observability を有効にする方法

## 結論

**はい、OTEL関連の環境変数を追加する必要があります。**

ただし、**Terraformの現在のコードは変更不要**です。Agent Runtime作成後に追加作業が必要になります。

## 必要な作業の流れ

### 1. 事前準備（アカウントごとに1回のみ）

CloudWatch Transaction Search を有効化します。

```bash
export AWS_PROFILE=your-aws-profile
aws sso login

# CloudWatch Transaction Searchを有効化
aws xray update-trace-segment-destination \
  --destination CloudWatchLogs \
  --region us-east-1

# サンプリング率を設定（1%で無料）
aws xray update-indexing-rule \
  --name "Default" \
  --rule '{"Probabilistic": {"DesiredSamplingPercentage": 1}}' \
  --region us-east-1
```

### 2. 通常通り Agent Runtime を作成

```bash
cd infrastructure
terraform apply
```

この段階では **Observability は無効** です。

### 3. Agent Runtime に環境変数を追加

**問題点**: Agent Runtime ID は作成後にしかわからないため、Terraform だけでは完結できません。

#### Option A: AWS コンソールで手動追加（簡単）

1. AWS Console で Bedrock AgentCore を開く
2. 作成した Agent Runtime を選択
3. 環境変数を編集して以下を追加：

```
AGENT_OBSERVABILITY_ENABLED=true
OTEL_PYTHON_DISTRO=aws_distro
OTEL_PYTHON_CONFIGURATOR=aws_configurator
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_EXPORTER=otlp
```

さらに、以下の変数には Agent Runtime ID が必要：

```
OTEL_RESOURCE_ATTRIBUTES=service.name=my-agent,aws.log.group.names=/aws/bedrock-agentcore/runtimes/<RUNTIME_ID>
OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=/aws/bedrock-agentcore/runtimes/<RUNTIME_ID>,x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore
```

`<RUNTIME_ID>` を実際の Runtime ID に置き換える必要があります。

#### Option B: シェルスクリプトで自動化（中級者向け）

`scripts/enable_observability.sh` のようなスクリプトを作成：

```bash
#!/bin/bash
set -e

export AWS_PROFILE=your-aws-profile

# Agent Runtime ID を取得
RUNTIME_ID=$(cd infrastructure && terraform output -raw agent_runtime_id)
RUNTIME_ARN=$(cd infrastructure && terraform output -raw agent_runtime_arn)

echo "==> Agent Runtime ID: ${RUNTIME_ID}"
echo "==> Observability を有効化中..."

# ⚠️ 注意: この API はまだ完全にサポートされていない可能性があります
# AWS Console から手動で設定することを推奨します

echo "以下の環境変数を AWS Console から追加してください："
echo ""
echo "AGENT_OBSERVABILITY_ENABLED=true"
echo "OTEL_PYTHON_DISTRO=aws_distro"
echo "OTEL_PYTHON_CONFIGURATOR=aws_configurator"
echo "OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"
echo "OTEL_TRACES_EXPORTER=otlp"
echo "OTEL_RESOURCE_ATTRIBUTES=service.name=my-agent,aws.log.group.names=/aws/bedrock-agentcore/runtimes/${RUNTIME_ID}"
echo "OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=/aws/bedrock-agentcore/runtimes/${RUNTIME_ID},x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore"
```

## エージェントコード（agent.py）の変更は？

**不要です！**

現在の `src/agentcore_hands_on/agent.py` はそのままで動作します。

```python
# このコードは変更不要
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Dict, Any

app = FastAPI()

# ... 既存のコード ...
```

OpenTelemetry の計装は **Agent Runtime 側で自動的に行われる** ため、エージェントコード自体を変更する必要はありません。

## Dockerfile の変更は？

**不要です！**

現在の Dockerfile もそのままで OK です。

```dockerfile
# 変更不要
FROM --platform=linux/arm64 python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn[standard] pydantic
COPY src/agentcore_hands_on/agent.py ./
EXPOSE 8080
CMD ["uvicorn", "agent:app", "--host", "0.0.0.0", "--port", "8080"]
```

Agent Runtime が環境変数を読み取って、自動的に OpenTelemetry の計装を行います。

## requirements.txt の変更は？

**不要です！**

`aws-opentelemetry-distro` などのパッケージを追加する必要はありません。

## Terraform コードの変更は？

**不要です！**

`infrastructure/` 以下のコードは一切変更不要です。

将来的に Terraform Provider が `observability` ブロックをサポートしたら、以下のように書けるようになります（今はまだ無理）：

```hcl
# 将来的にはこう書けるようになる予定（現在は未サポート）
resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = var.agent_runtime_name

  # ❌ 現在はこのブロックは使えません
  observability {
    enable = true
  }
}
```

## まとめ

### コード変更

- ✅ **エージェントコード**: 変更不要
- ✅ **Dockerfile**: 変更不要
- ✅ **requirements.txt**: 変更不要
- ✅ **Terraform**: 変更不要

### 追加で必要な作業

1. **CloudWatch Transaction Search を有効化**（アカウントごとに1回）
2. **Agent Runtime 作成後に環境変数を追加**（Runtime ごとに1回）
   - AWS Console から手動で追加
   - または、Runtime ID を取得してスクリプトで追加

### なぜこんなに面倒なのか？

Agent Runtime ID は作成されるまでわからないため、Terraform だけでは完結できません。これが GitHub Issue #44742 で問題提起されている理由です。

### いつ改善される？

Terraform Provider の Issue #44742 が解決されれば、Terraform のコードに `observability { enable = true }` と書くだけで済むようになります。それまでは手動での設定が必要です。

## Observability 有効化後の確認

```bash
# ログを確認
aws logs tail "/aws/bedrock-agentcore/runtimes/<RUNTIME_ID>" \
  --follow \
  --region us-east-1

# CloudWatch Console で確認
# GenAI Observability > Bedrock AgentCore タブ
```

## 参考リンク

- [observability_setup.md](./observability_setup.md) - 詳細な設定方法
- [GitHub Issue #44742](https://github.com/hashicorp/terraform-provider-aws/issues/44742) - Terraform サポート状況
