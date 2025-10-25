# プロンプト/レスポンステキストが記録されない問題の解決策

## 目次
1. [問題の現状](#問題の現状)
2. [根本原因の分析](#根本原因の分析)
3. [解決策](#解決策)
4. [実装手順](#実装手順)

---

## 問題の現状

### 確認できた事実

1. **Strands Telemetryは初期化されている**
   ```
   2025-10-25 15:30:12,028 - strands.telemetry.config - INFO - Initializing tracer
   2025-10-25 15:30:12,028 - strands.telemetry.config - INFO - OTLP exporter configured
   ```

2. **スパンは正常に記録されている**
   - `invoke_agent Strands Agents`
   - `execute_event_loop_cycle`
   - `execute_tool execute_python`
   - トークン使用量などのメタデータも完全

3. **CloudWatch Logsにスパンデータが記録されている**
   - ログループ: `aws/spans` (NOT `/aws/spans`)
   - ログストリーム: `default`
   - Transaction Searchは有効

4. **プロンプト/レスポンスのテキストが記録されていない**
   ```json
   {
     "attributes": {
       "gen_ai.usage.prompt_tokens": 6471,
       "gen_ai.usage.output_tokens": 173,
       "gen_ai.agent.name": "Strands Agents",
       // ❌ gen_ai.user.message が存在しない
       // ❌ gen_ai.choice が存在しない
       // ❌ gen_ai.assistant.message が存在しない
     }
   }
   ```

5. **スパンイベント（events）フィールドが存在しない**
   - スパンデータに`"events": []`フィールド自体がない
   - OpenTelemetryのイベントとして記録されていない

### Strandsドキュメントとの相違

Strandsの公式ドキュメントでは、以下が**デフォルトで記録される**と記載されています：

- `gen_ai.user.message`: ユーザーの質問
- `gen_ai.choice`: エージェントの応答
- `gen_ai.assistant.message`: フォーマット済みプロンプト

しかし、実際には記録されていません。

---

## 根本原因の分析

### 原因1: OpenTelemetryの属性値長制限

OpenTelemetryには、デフォルトで**属性値の長さ制限**があります：

```python
# デフォルト制限
OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT = 128  # 文字数
```

プロンプト/レスポンスは通常、数百〜数千文字になるため、この制限により**切り詰められる、または記録されない**可能性があります。

### 原因2: TracerProvider上書き警告の影響

```
opentelemetry.trace - WARNING - Overriding of current TracerProvider is not allowed
```

この警告が示すように：
1. ADOT（AWS Distro for OpenTelemetry）が先にTracerProviderを設定
2. Strandsが新しいTracerProviderを設定しようとして失敗
3. **Strandsの独自設定（プロンプト/レスポンス記録など）が適用されない**

ADOTのTracerProviderがデフォルトで属性値の長さ制限を持っている可能性があります。

### 原因3: スパンイベントとして記録されるべきだが、されていない

OpenTelemetryの仕様では：
- **Attributes**: 短いメタデータ（数値、短い文字列）
- **Events**: 長いテキストデータ（ログ、プロンプト、レスポンス）

プロンプト/レスポンスは**イベント**として記録されるべきですが、実際のスパンデータには`events`フィールドが存在しません。

これは、Strandsが：
- イベントとして記録しようとしているが、TracerProviderの設定により無効化されている
- または、attributesとして記録しようとしているが、長さ制限により切り詰められている

---

## 解決策

### 解決策1: OpenTelemetry環境変数で長さ制限を解除（推奨）

`infrastructure/main.tf` の環境変数に以下を追加：

```hcl
environment_variables = merge(
  {
    # 既存の環境変数
    LOG_LEVEL   = var.log_level
    ENVIRONMENT = var.environment

    # ... 既存の設定 ...

    # OpenTelemetry属性値の長さ制限を解除
    OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT = "-1"  # 無制限
    OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT = "-1"  # 無制限

    # スパンイベントの属性値の長さ制限も解除
    OTEL_SPAN_EVENT_ATTRIBUTE_VALUE_LENGTH_LIMIT = "-1"  # 無制限
  },
  # Memory ID, Code Interpreter ID, etc...
)
```

**期待される効果:**
- プロンプト/レスポンスの完全なテキストが属性として記録される
- GenAI Observabilityで表示可能になる

### 解決策2: Strandsの明示的なイベント記録を有効化

Strandsが内部的にイベント記録の設定を持っている可能性があるため、環境変数で制御：

```hcl
# Strandsのテレメトリレベルを最大に
STRANDS_TELEMETRY_LEVEL = "verbose"
STRANDS_CAPTURE_PROMPTS = "true"
STRANDS_CAPTURE_RESPONSES = "true"

# OpenTelemetryのイベント記録を強制有効化
OTEL_PYTHON_DISABLED_INSTRUMENTATIONS = ""  # 無効化されている計装を再有効化
```

**注意:** これらの環境変数は、Strandsのドキュメントに明記されていないため、効果は不明です。

### 解決策3: カスタムスパンプロセッサーを追加（高度）

Strandsの初期化後に、カスタムスパンプロセッサーを追加してプロンプト/レスポンスを手動で記録：

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider, SpanProcessor
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

class PromptResponseProcessor(SpanProcessor):
    """プロンプト/レスポンスをスパンイベントとして記録するプロセッサー"""

    def on_start(self, span, parent_context):
        # スパン開始時には何もしない
        pass

    def on_end(self, span):
        # スパン終了時にプロンプト/レスポンスをイベントとして追加
        # （実装は複雑になるため、解決策1を優先）
        pass

# agent.py に追加
tracer_provider = trace.get_tracer_provider()
if isinstance(tracer_provider, TracerProvider):
    tracer_provider.add_span_processor(PromptResponseProcessor())
```

**注意:** この方法は複雑で、Strandsの内部実装に依存するため、推奨しません。

### 解決策4: Strands Agentのイベントフックを利用（要調査）

Strands Agentに、実行前後のフックがあるか確認：

```python
agent = Agent(
    model=...,
    tools=...,
    # イベントフック（仮説）
    on_request=lambda prompt: ...,
    on_response=lambda response: ...,
)
```

Strandsのドキュメントやソースコードを調査する必要があります。

---

## 実装手順

### Phase 1: 属性値長制限の解除（最優先・最も簡単）

#### 1. Terraformファイルを編集

`infrastructure/main.tf` の環境変数セクションに追加：

```hcl
environment_variables = merge(
  {
    # 既存の環境変数
    LOG_LEVEL   = var.log_level
    ENVIRONMENT = var.environment
    CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id
    BROWSER_ID = module.browser.browser_id
    MEMORY_ID = module.memory.memory_id

    # AgentCore Observability設定
    AGENT_OBSERVABILITY_ENABLED = "true"
    OTEL_PYTHON_DISTRO       = "aws_distro"
    OTEL_PYTHON_CONFIGURATOR = "aws_configurator"
    OTEL_RESOURCE_ATTRIBUTES = var.agent_runtime_id != "" ? "service.name=${var.agent_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-${var.agent_runtime_endpoint_qualifier},cloud.resource_id=${var.agent_runtime_id}" : "service.name=${var.agent_name}"
    OTEL_EXPORTER_OTLP_LOGS_HEADERS = var.agent_runtime_id != "" ? "x-aws-log-group=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-${var.agent_runtime_endpoint_qualifier},x-aws-metric-namespace=bedrock-agentcore" : "x-aws-metric-namespace=bedrock-agentcore"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_TRACES_SAMPLER = "always_on"

    # ↓ ここに追加 ↓
    # OpenTelemetry属性値の長さ制限を解除（プロンプト/レスポンス記録のため）
    OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT = "-1"
    OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT = "-1"
    OTEL_SPAN_EVENT_ATTRIBUTE_VALUE_LENGTH_LIMIT = "-1"
  }
)
```

#### 2. tfvarsのバージョン更新

```bash
# infrastructure/terraform.tfvars
image_tag = "v1.1.1"
```

#### 3. ビルド＆デプロイ

```bash
# イメージビルド（コード変更なし、環境変数のみ）
export AWS_PROFILE=239339588912_AdministratorAccess
cd /Users/fukadasho/individual_development/agentcore_hands_on
./scripts/build_and_push.sh 239339588912.dkr.ecr.us-east-1.amazonaws.com/agentcore-hands-on-my-agent v1.1.1

# Terraformデプロイ
cd infrastructure
terraform apply -auto-approve
```

#### 4. エージェント実行

```bash
cd /Users/fukadasho/individual_development/agentcore_hands_on
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "こんにちは！簡単な計算をしてください。2 + 2は何ですか？"
```

#### 5. スパンデータの確認

```bash
# 最新のスパンデータを取得
aws logs get-log-events \
  --log-group-name "aws/spans" \
  --log-stream-name "default" \
  --limit 5 \
  > /tmp/spans_after_fix.json

# プロンプト/レスポンスが記録されているか確認
python3 -c "
import json
with open('/tmp/spans_after_fix.json', 'r') as f:
    data = json.load(f)
for event in data.get('events', []):
    msg = event.get('message', '')
    try:
        span_data = json.loads(msg)
        if 'invoke_agent' in span_data.get('name', ''):
            attrs = span_data.get('attributes', {})
            print('=== invoke_agent attributes ===')
            for key in sorted(attrs.keys()):
                if 'message' in key or 'choice' in key or 'prompt' in key:
                    print(f'{key}: {str(attrs[key])[:300]}...')
    except:
        pass
"
```

#### 6. GenAI Observabilityで確認

1. CloudWatch Console → GenAI Observability → Bedrock AgentCore
2. Traces View → 最新のトレースを選択
3. 「イベント」または「属性」セクションを確認
4. プロンプト/レスポンスのテキストが表示されることを確認

---

### Phase 2: それでも表示されない場合の追加調査

#### Option A: Strands Agentsのソースコードを確認

```bash
# Strandsのインストールディレクトリを確認
uv run python -c "import strands; print(strands.__file__)"

# テレメトリ関連のコードを読む
# strands/telemetry/ ディレクトリを確認
# プロンプト/レスポンス記録のロジックを探す
```

#### Option B: デバッグログを有効化

```hcl
# infrastructure/main.tf
environment_variables = merge(
  {
    # ... 既存の設定 ...

    # OpenTelemetryデバッグログを有効化
    OTEL_LOG_LEVEL = "debug"

    # Pythonロギングレベルを DEBUG に
    LOG_LEVEL = "DEBUG"
  }
)
```

ログから、Strandsがプロンプト/レスポンスを記録しようとしているか確認。

#### Option C: OpenTelemetryのバージョン確認

```bash
uv pip list | grep opentelemetry
```

ADOTとStrandsが使用しているOpenTelemetryのバージョンに互換性の問題がないか確認。

---

## まとめ

### 最も可能性の高い原因

**OpenTelemetryの属性値長制限** により、プロンプト/レスポンスが切り詰められている、または記録されていない。

### 最も効果的な解決策

**環境変数で長さ制限を解除する:**
```bash
OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT=-1
OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT=-1
OTEL_SPAN_EVENT_ATTRIBUTE_VALUE_LENGTH_LIMIT=-1
```

### 期待される結果

- `gen_ai.user.message`: ユーザーの質問全文
- `gen_ai.choice`: エージェントの応答全文
- `gen_ai.assistant.message`: フォーマット済みプロンプト全文

これらが属性またはイベントとして記録され、GenAI Observabilityで表示される。

### 次のステップ

1. `infrastructure/main.tf` に3つの環境変数を追加
2. バージョンをv1.1.1に更新
3. ビルド & デプロイ
4. エージェント実行
5. スパンデータを確認
6. GenAI Observabilityで確認
7. 結果をドキュメント化

---

## 参考資料

- [OpenTelemetry Attribute Limits](https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/#attribute-limits)
- [Strands Agents Traces](https://strandsagents.com/latest/documentation/docs/user-guide/observability-evaluation/traces/)
- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)

### OpenTelemetry環境変数リファレンス

| 環境変数 | デフォルト値 | 説明 |
|---------|-------------|------|
| `OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT` | `∞` (OpenTelemetry仕様) / `128` (一部実装) | 属性値の最大文字数 |
| `OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT` | `OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT` | スパン属性値の最大文字数 |
| `OTEL_SPAN_EVENT_ATTRIBUTE_VALUE_LENGTH_LIMIT` | `OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT` | スパンイベント属性値の最大文字数 |

`-1` を設定すると、制限が無効化されます。
