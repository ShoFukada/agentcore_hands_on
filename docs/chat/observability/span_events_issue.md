# スパンイベント（プロンプト/レスポンス）が表示されない問題の原因と改善策

## 目次
1. [問題の症状](#問題の症状)
2. [調査結果](#調査結果)
3. [根本原因](#根本原因)
4. [改善策](#改善策)
5. [実装手順](#実装手順)

---

## 問題の症状

CloudWatch GenAI Observabilityのトレース詳細画面で、以下の問題が発生している：

- ✅ スパン構造は正しく表示される
- ✅ タイミング情報は正常
- ✅ 基本的な属性（attributes）は記録される
- ❌ **イベント（events）が「イベントはありません」と表示される**
- ❌ **プロンプト/レスポンスの内容が見えない**

参考記事（https://dev.classmethod.jp/articles/amazon-bedrock-agentcore-observability-genai-observability/）
では、イベントとして以下が表示されている：
- システムプロンプト
- ユーザー入力
- ツール呼び出し結果
- アシスタント応答

---

## 調査結果

### 1. Strands Agentsのトレース機能

Strands SDKは**OpenTelemetry標準を使用**しており、以下の情報を自動的にトレースに記録する：

**エージェントレベル:**
- システム識別子（`gen_ai.system`）
- **ユーザープロンプトとエージェント応答**
- トークン使用量
- 実行時刻

**サイクルレベル:**
- 各推論サイクルの識別子
- **フォーマットされたプロンプトとアシスタントメッセージ**
- ツール呼び出し結果

**モデル呼び出しレベル:**
- モデルID
- **プロンプト/補完の詳細**

**ツール実行レベル:**
- ツール名、実行ステータス

### 2. Strands Telemetryの設定方法

Strands SDKには専用の`StrandsTelemetry`クラスが存在し、以下のように設定する：

```python
from strands.telemetry import StrandsTelemetry

# テレメトリのセットアップ
strands_telemetry = StrandsTelemetry()
strands_telemetry.setup_otlp_exporter()  # OTLPエクスポーター有効化
strands_telemetry.setup_console_exporter()  # オプション: コンソール出力
```

環境変数での設定も可能：
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="http://collector.example.com:4318"
```

### 3. AWS AgentCore Observabilityの仕組み

クラスメソッド記事によると：

> AgentCore starter toolkitを使用すると**自動的にopentelemetry-instrumentが有効化されて可視化できるようになっています**

つまり、AgentCore公式のスターターテンプレートでは：
1. OpenTelemetry Instrumentationが自動有効化
2. Strands AgentsのテレメトリがOTLP経由でCloudWatchに送信
3. トレースにプロンプト/レスポンスが自動的に記録される

---

## 根本原因

現在のコード（`src/agentcore_hands_on/agent.py`）を確認した結果：

### ❌ 問題点

1. **StrandsTelemetryの初期化が無い**
   ```python
   # agent.py には StrandsTelemetry の import も初期化コードも無い
   ```

2. **環境変数は設定済みだが、Strandsのセットアップコードが無い**
   - `infrastructure/main.tf`にOpenTelemetry関連の環境変数は設定されている
   - しかし、**Strands SDKがそれを使用するためのセットアップコードが無い**

3. **ADOTの自動計装のみに依存**
   - AWS Distro for OpenTelemetry（ADOT）の自動計装は動作している
   - しかし、**Strands特有のテレメトリ（プロンプト/レスポンス詳細）は記録されない**

### 🔍 なぜ基本的なトレースは動くのか？

- ADOTの自動計装により、HTTPリクエスト、Bedrock APIコールなどの基本スパンは自動生成される
- しかし、**Strands Agentの内部動作（サイクル、プロンプト、ツール実行詳細）はStrandsTelemetryが無いと記録されない**

---

## 改善策

### 解決方法: StrandsTelemetryの初期化を追加

Strands SDKのテレメトリ機能を明示的に有効化する必要がある。

### 必要な変更

1. **StrandsTelemetryのインポートと初期化**
2. **OTLPエクスポーターのセットアップ**
3. **（オプション）カスタム属性の追加**

---

## 実装手順

### Phase 1: 最小限の修正（テレメトリ有効化）

**ファイル:** `src/agentcore_hands_on/agent.py`

**追加するコード:**

```python
# 既存のimportの下に追加
from strands.telemetry import StrandsTelemetry

# 設定の読み込みの後に追加（app = FastAPI()の前）
# Strands Telemetry のセットアップ
strands_telemetry = StrandsTelemetry()
strands_telemetry.setup_otlp_exporter()
logger.info("Strands Telemetry initialized with OTLP exporter")
```

**配置場所:**
```python
# 既存のコード
settings = Settings()

# ↓ ここに追加 ↓
# Strands Telemetry のセットアップ
strands_telemetry = StrandsTelemetry()
strands_telemetry.setup_otlp_exporter()
logger.info("Strands Telemetry initialized with OTLP exporter")

# 既存のコード
app = FastAPI(title="Strands Agent Runtime")
```

### Phase 2: カスタム属性の追加（オプション）

より詳細な追跡を行う場合、Agent作成時にカスタム属性を追加：

```python
def create_agent(session_id: str | None = None, actor_id: str | None = None) -> Agent:
    """Strands Agent を作成する(Memory統合対応)"""
    # MEMORY_IDが設定されている場合はSessionManagerを作成
    session_manager = None
    if settings.MEMORY_ID:
        memory_config = AgentCoreMemoryConfig(
            memory_id=settings.MEMORY_ID,
            session_id=session_id or settings.DEFAULT_SESSION_ID,
            actor_id=actor_id or settings.DEFAULT_ACTOR_ID,
        )

        session_manager = AgentCoreMemorySessionManager(
            agentcore_memory_config=memory_config,
            region_name=settings.AWS_REGION,
        )
        logger.info(
            "Memory統合有効: memory_id=%s, session_id=%s, actor_id=%s",
            settings.MEMORY_ID,
            memory_config.session_id,
            memory_config.actor_id,
        )

    # カスタム属性を追加
    trace_attributes = {
        "session_id": session_id or settings.DEFAULT_SESSION_ID,
        "actor_id": actor_id or settings.DEFAULT_ACTOR_ID,
        "environment": settings.ENVIRONMENT,
    }

    # Strands Agent を作成
    return Agent(
        model=BedrockModel(
            model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
            region_name=settings.AWS_REGION,
        ),
        tools=[execute_python, browse_web],
        session_manager=session_manager,
        trace_attributes=trace_attributes,  # カスタム属性を追加
    )
```

### Phase 3: デバッグ出力の追加（開発時のみ）

テレメトリが正しく動作しているか確認するため、コンソールエクスポーターも追加：

```python
# 開発環境でのみ有効化
if settings.ENVIRONMENT == "dev":
    strands_telemetry.setup_console_exporter()
    logger.info("Console exporter enabled for debugging")
```

---

## 期待される効果

### 修正後に期待される変化

1. **スパンイベントの記録**
   - エージェントサイクルごとのスパンが追加される
   - 各サイクルでのプロンプト/レスポンスがイベントとして記録される

2. **GenAI Observabilityでの表示**
   - トレース詳細画面で「イベント」セクションにデータが表示される
   - 以下の情報が確認できるようになる：
     - システムプロンプト
     - ユーザー入力（質問）
     - ツール呼び出しの引数と結果
     - モデルの応答（日本語含む）

3. **トークン使用量の詳細**
   - プロンプトトークン、補完トークン、キャッシュトークンの詳細
   - サイクルごとのトークン消費量

4. **デバッグの向上**
   - エージェントの思考プロセスが可視化される
   - ツール選択の理由が追跡可能
   - エラー発生時の文脈が明確になる

---

## 検証方法

### 1. ローカルでのテスト

```bash
# 依存関係の確認
uv run python -c "from strands.telemetry import StrandsTelemetry; print('OK')"

# コード修正後、ローカルで起動
uv run python src/agentcore_hands_on/agent.py

# ログに以下のメッセージが出力されることを確認
# "Strands Telemetry initialized with OTLP exporter"
```

### 2. デプロイ後の確認

```bash
# イメージビルド & プッシュ
export AWS_PROFILE=239339588912_AdministratorAccess
./scripts/build_and_push.sh

# Terraformでデプロイ
cd infrastructure
terraform apply

# ログの確認
aws logs get-log-events \
  --log-group-name "/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT" \
  --log-stream-name "<最新のストリーム名>" \
  --limit 50 | grep "Strands Telemetry"
```

### 3. GenAI Observabilityでの確認

1. AgentCore経由でエージェントを実行
2. CloudWatch → GenAI Observability → Bedrock AgentCore
3. Traces Viewで最新のトレースを選択
4. **「イベント」セクションにデータが表示されることを確認**
5. プロンプト/レスポンスの内容が確認できることを確認

---

## 参考リソース

### Strands Agents公式ドキュメント
- [Observability概要](https://strandsagents.com/latest/documentation/docs/user-guide/observability-evaluation/observability/)
- [トレース詳細](https://strandsagents.com/latest/documentation/docs/user-guide/observability-evaluation/traces/)
- [メトリクス](https://strandsagents.com/latest/documentation/docs/user-guide/observability-evaluation/metrics/)
- [ログ](https://strandsagents.com/latest/documentation/docs/user-guide/observability-evaluation/logs/)

### AWS関連
- [Amazon Bedrock AgentCore Observability解説](https://dev.classmethod.jp/articles/amazon-bedrock-agentcore-observability-genai-observability/)
- [AgentCore Observability公式ドキュメント](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-get-started.html)

---

## まとめ

### 原因
Strands AgentsのOpenTelemetryテレメトリが初期化されていなかったため、エージェントの詳細動作（プロンプト/レスポンス/ツール実行）がトレースに記録されていなかった。

### 解決策
`StrandsTelemetry`クラスを初期化し、`setup_otlp_exporter()`を呼び出すことで、Strandsの詳細テレメトリをOpenTelemetry経由でAWS X-Ray/CloudWatchに送信する。

### 期待される結果
GenAI Observabilityダッシュボードでプロンプト/レスポンスの詳細が表示され、エージェントの思考プロセスを完全に追跡できるようになる。

### 次のステップ
1. `agent.py`にStrandsTelemetryの初期化コードを追加
2. ローカルでテスト
3. イメージをビルド & デプロイ
4. GenAI Observabilityで動作確認
