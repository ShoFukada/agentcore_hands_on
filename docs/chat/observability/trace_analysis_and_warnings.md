# トレース分析結果とTracerProvider警告について

## 目次
1. [現在のトレース状況](#現在のトレース状況)
2. [期待されるデータ構造との比較](#期待されるデータ構造との比較)
3. [TracerProvider警告について](#tracerprovider警告について)
4. [改善策](#改善策)

---

## 現在のトレース状況

### ✅ 記録されているデータ

StrandsTelemetryの初期化により、以下のメタデータが正常に記録されています：

#### エージェントレベル
```
gen_ai.agent.name: Strands Agents
gen_ai.operation.name: invoke_agent
gen_ai.request.model: global.anthropic.claude-haiku-4-5-20251001-v1:0
gen_ai.agent.tools: ["execute_python", "browse_web"]
gen_ai.system: strands-agents
gen_ai.event.start_time: 2025-10-25T15:30:07.258832+00:00
gen_ai.event.end_time: 2025-10-25T15:30:14.261814+00:00
```

#### トークン使用量
```
gen_ai.usage.prompt_tokens: 6471
gen_ai.usage.output_tokens: 173
gen_ai.usage.total_tokens: 6644
gen_ai.usage.completion_tokens: 173
gen_ai.usage.input_tokens: 6471
gen_ai.usage.cache_read_input_tokens: 0
gen_ai.usage.cache_write_input_tokens: 0
```

#### イベントループサイクル
```
event_loop.cycle_id: 10a90b9f-87b6-4ef0-9816-60d817c91a28
event_loop.parent_cycle_id: (親サイクルがある場合)
```

#### ツール実行情報
```
gen_ai.tool.name: execute_python
gen_ai.tool.call.id: tooluse_uMtzGxn-RKSpnArREdRP7g
gen_ai.tool.status: success
gen_ai.tool.description: Execute Python code in a sandboxed Code Interpreter environment...
gen_ai.tool.json_schema: {"properties": {...}, "required": [...], "type": "object"}
```

#### BedrockRuntime詳細
```
gen_ai.response.finish_reasons: ['tool_use'] / ['end_turn']
gen_ai.server.request.duration: 1849 (ms)
gen_ai.server.time_to_first_token: 1272 (ms)
```

### ❌ 記録されていないデータ

以下のデータが**X-Ray APIから取得できませんでした**：

```
gen_ai.user.message: <ユーザーの質問テキスト>
gen_ai.assistant.message: <フォーマットされたプロンプト>
gen_ai.choice: <エージェントのレスポンステキスト>
gen_ai.choice.tool.result: <ツール実行結果の詳細>
gen_ai.choice.message: <フォーマットされた補完>
```

---

## 期待されるデータ構造との比較

### Strandsドキュメントに記載されている構造

```
+-------------------------------------------------------------------------------------+
| Strands Agent                                                                       |
| - gen_ai.system: ✅ 記録されている                                                    |
| - gen_ai.agent.name: ✅ 記録されている                                                |
| - gen_ai.operation.name: ✅ 記録されている                                            |
| - gen_ai.request.model: ✅ 記録されている                                             |
| - gen_ai.user.message: ❌ 取得できていない                                            |
| - gen_ai.choice: ❌ 取得できていない                                                  |
| - gen_ai.usage.*: ✅ すべて記録されている                                             |
|                                                                                     |
|  +-------------------------------------------------------------------------------+  |
|  | Cycle <cycle-id>                                                              |  |
|  | - gen_ai.user.message: ❌ 取得できていない                                      |  |
|  | - gen_ai.assistant.message: ❌ 取得できていない                                 |  |
|  | - event_loop.cycle_id: ✅ 記録されている                                        |  |
|  | - gen_ai.choice: ❌ 取得できていない                                            |  |
|  |                                                                               |  |
|  |  +-----------------------------------------------------------------------+    |  |
|  |  | Model invoke                                                          |    |  |
|  |  | - gen_ai.user.message: ❌ 取得できていない                              |    |  |
|  |  | - gen_ai.assistant.message: ❌ 取得できていない                         |    |  |
|  |  | - gen_ai.choice: ❌ 取得できていない                                    |    |  |
|  |  | - gen_ai.usage.*: ✅ すべて記録されている                               |    |  |
|  |  +-----------------------------------------------------------------------+    |  |
|  |                                                                               |  |
|  |  +-----------------------------------------------------------------------+    |  |
|  |  | Tool: <tool name>                                                     |    |  |
|  |  | - gen_ai.tool.name: ✅ 記録されている                                   |    |  |
|  |  | - gen_ai.tool.call.id: ✅ 記録されている                                |    |  |
|  |  | - gen_ai.tool.status: ✅ 記録されている                                 |    |  |
|  |  | - gen_ai.choice: ❌ 取得できていない                                    |    |  |
|  |  +-----------------------------------------------------------------------+    |  |
|  +-------------------------------------------------------------------------------+  |
+-------------------------------------------------------------------------------------+
```

### なぜプロンプト/レスポンスが取得できないのか

#### 原因1: スパンイベントとして記録されている

プロンプト/レスポンスのテキストは、スパン**属性（attributes）**ではなく、スパン**イベント（events）**として記録されている可能性があります。

OpenTelemetryでは：
- **attributes**: 数値や短い文字列（メタデータ）
- **events**: 長いテキストやログのような詳細データ

X-Ray APIの`batch-get-traces`では、**スパンイベントの詳細が含まれない**場合があります。

#### 原因2: CloudWatch Transaction Searchが無効

```bash
$ aws logs describe-log-streams --log-group-name "/aws/spans/default"
An error occurred (ResourceNotFoundException): The specified log group does not exist.
```

`/aws/spans/default` ログループが存在しません。これは：
- **CloudWatch Transaction Searchが有効化されていない**
- スパンデータがCloudWatch Logsに送信されていない
- GenAI Observabilityがイベントデータを取得できない

#### 原因3: OpenTelemetryの設定不足

Strands Telemetryがデフォルトでプロンプト/レスポンスを記録しない設定になっている可能性があります。

---

## TracerProvider警告について

### 警告メッセージ

```
2025-10-25 15:30:12,028 - opentelemetry.trace - WARNING - Overriding of current TracerProvider is not allowed
```

### なぜこの警告が出るのか

#### 背景: OpenTelemetryのTracerProvider

OpenTelemetryでは、アプリケーション全体で**1つのTracerProvider**を使用することが推奨されています。TracerProviderは、トレースの生成と収集を管理する中心的なコンポーネントです。

#### 実行順序

現在のコードでは、以下の順序で初期化が行われています：

1. **AWS Distro for OpenTelemetry (ADOT) の自動計装**
   - 環境変数 `OTEL_PYTHON_DISTRO=aws_distro` により、アプリケーション起動時に自動実行
   - ADOTがグローバルなTracerProviderを設定
   - X-RayエクスポーターとCloudWatchエクスポーターを構成

2. **Strands Telemetry の初期化**
   - `agent.py:36-38` で `StrandsTelemetry().setup_otlp_exporter()` を実行
   - Strandsが**新しい**TracerProviderを設定しようとする
   - 既存のTracerProviderが存在するため、警告が発生

#### なぜ警告なのか

OpenTelemetryは、既存のTracerProviderを**上書きできない**仕様になっています。理由は：
- 複数のTracerProviderが存在すると、トレースデータが分断される
- エクスポーター設定が競合する
- データの一貫性が失われる

**警告が出ても、先に設定されたADOTのTracerProviderが継続して使用されます。**

### この警告の影響

#### 実害は少ない

現在の状況では：
- ✅ ADOTのTracerProviderが動作している
- ✅ X-RayとCloudWatchへのエクスポートは正常
- ✅ Strandsのスパン生成は動作している（TracerProviderの切り替えは失敗しているが、既存のTracerを使用している）
- ⚠️ Strandsが意図した独自のエクスポーター設定は適用されていない可能性

#### 潜在的な問題

- Strandsが期待する特定の設定（例: 詳細なイベント記録）が有効化されていない可能性
- 2つのシステムが同じTracerProviderを共有しているため、設定の競合リスク

---

## 改善策

### Phase 1: Transaction Searchの有効化（最優先）

CloudWatch Transaction Searchを有効化することで、スパンデータが `/aws/spans/default` に記録され、GenAI Observabilityでイベント詳細が表示されるようになります。

**手順:**

1. **CloudWatchコンソールを開く**
   ```
   AWS Console → CloudWatch → 設定 → Transaction Search
   ```

2. **Transaction Searchを有効化**
   - 「Enable Transaction Search」ボタンをクリック
   - リージョン: us-east-1

3. **エージェントを再実行**
   ```bash
   uv run python src/agentcore_hands_on/invoke_agent.py \
     --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
     --prompt "テストメッセージ"
   ```

4. **ログループの確認**
   ```bash
   aws logs describe-log-streams \
     --log-group-name "/aws/spans/default" \
     --order-by LastEventTime --descending --max-items 1
   ```

### Phase 2: TracerProvider警告の解消（オプション）

警告を解消するには、**ADOTとStrandsの初期化順序を制御**する必要があります。

#### Option A: StrandsTelemetryの初期化を先に実行（推奨しない）

ADOTの自動計装より前にStrandsを初期化する必要がありますが、環境変数による自動計装を無効化する必要があり、複雑です。

#### Option B: ADOTのTracerProviderを使用（現状維持）

**推奨:** 現在の状態を受け入れる

- ADOTのTracerProviderは完全に機能している
- Strandsのスパンも正常に生成されている
- 警告は出るが、実害は少ない

#### Option C: 共通のTracerProviderを明示的に設定

両方のシステムで共有できる、統一されたTracerProviderを設定します。

**実装例（agent.py）:**

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from strands.telemetry import StrandsTelemetry

# 設定の読み込み
settings = Settings()

# 既存のTracerProviderを取得（ADOTが設定済みの場合）
tracer_provider = trace.get_tracer_provider()

# TracerProviderが未設定の場合のみ新規作成
if not isinstance(tracer_provider, TracerProvider):
    tracer_provider = TracerProvider()
    trace.set_tracer_provider(tracer_provider)

    # OTLPエクスポーターを追加
    otlp_exporter = OTLPSpanExporter()
    tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))

# Strands Telemetry を初期化（TracerProvider設定はスキップ）
strands_telemetry = StrandsTelemetry()
# setup_otlp_exporter()は呼ばない（既存のTracerProviderを使用）

logger.info("Telemetry initialized with existing TracerProvider")
```

**注意:** この方法は、StrandsとADOTの両方の動作を理解している必要があり、複雑です。

### Phase 3: Strandsの設定確認

Strandsがプロンプト/レスポンスをイベントとして記録するための設定があるか確認します。

**調査項目:**

1. **環境変数での制御**
   ```bash
   # 詳細なテレメトリを有効化する環境変数があるか
   STRANDS_TELEMETRY_LEVEL=verbose
   OTEL_TRACES_SAMPLER=always_on
   OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT=-1  # 制限なし
   ```

2. **Agent作成時のオプション**
   ```python
   # カスタム属性で制御できるか
   agent = Agent(
       model=...,
       tools=...,
       trace_attributes={
           "telemetry.level": "verbose",
           "capture_prompts": True,
       }
   )
   ```

3. **Strands公式ドキュメントを確認**
   - https://strandsagents.com/latest/documentation/docs/user-guide/observability-evaluation/traces/
   - プロンプト/レスポンス記録の設定方法を探す

---

## まとめ

### 現状

| 項目 | 状態 | 説明 |
|------|------|------|
| トレース構造 | ✅ 正常 | スパン階層は正しく記録されている |
| メタデータ | ✅ 正常 | トークン使用量、ツール情報などは完全 |
| プロンプト/レスポンス | ❌ 不足 | テキスト内容が取得できていない |
| Transaction Search | ❌ 無効 | `/aws/spans/default` が存在しない |
| TracerProvider警告 | ⚠️ 警告 | 動作には影響しないが警告が出る |

### 最優先アクション

1. **CloudWatch Transaction Searchを有効化する**
   - これにより、GenAI Observabilityでイベント詳細が表示される可能性が高い

2. **エージェントを再実行してスパンログを確認する**
   - `/aws/spans/default` にデータが記録されているか確認

3. **GenAI Observabilityダッシュボードで確認**
   - イベントセクションにプロンプト/レスポンスが表示されるか確認

### TracerProvider警告について

- **結論:** 現状のまま（警告を残す）で問題ない
- ADOTのTracerProviderが正常に動作している
- Strandsのスパンも正常に生成されている
- 警告を消すための複雑な変更は、リスクに見合わない

### 次のステップ

1. CloudWatchコンソールでTransaction Searchを有効化
2. エージェントを実行してスパンデータを生成
3. `/aws/spans/default` のログを確認
4. GenAI Observabilityでイベント表示を確認
5. それでもイベントが表示されない場合、Strandsの設定を調査

---

## 参考リソース

- [OpenTelemetry TracerProvider仕様](https://opentelemetry.io/docs/specs/otel/trace/api/#tracerprovider)
- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)
- [CloudWatch Transaction Search](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search.html)
- [Strands Agents Traces](https://strandsagents.com/latest/documentation/docs/user-guide/observability-evaluation/traces/)
