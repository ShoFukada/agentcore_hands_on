# AgentCore Memory リソース構造

## 全体像

AgentCore Memoryは**2層構造**のリソースで構成されます：

```
┌─────────────────────────────────────────────────────────────────────┐
│  aws_bedrockagentcore_memory (Memory本体)                           │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│  name: "agent-assistant-memory"                                     │
│  event_expiry_duration: 30 (日)  ← Short-term Memory設定           │
│  encryption_key_arn: (optional)                                     │
│  memory_execution_role_arn: (optional)                              │
│                                                                     │
│  ┌────────────────────────────────────────────────────────┐        │
│  │ aws_bedrockagentcore_memory_strategy (Strategy 1)      │        │
│  │ ────────────────────────────────────────────────────── │        │
│  │ type: SEMANTIC                                         │        │
│  │ namespaces: ["app_name/knowledge/{actorId}"]           │        │
│  │              ↑ Long-term Memory設定                   │        │
│  └────────────────────────────────────────────────────────┘        │
│                                                                     │
│  ┌────────────────────────────────────────────────────────┐        │
│  │ aws_bedrockagentcore_memory_strategy (Strategy 2)      │        │
│  │ ────────────────────────────────────────────────────── │        │
│  │ type: USER_PREFERENCE                                  │        │
│  │ namespaces: ["app_name/preferences/{actorId}"]         │        │
│  └────────────────────────────────────────────────────────┘        │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │ aws_bedrockagentcore_memory_strategy (Strategy 3)        │      │
│  │ ──────────────────────────────────────────────────────── │      │
│  │ type: SUMMARIZATION                                      │      │
│  │ namespaces: ["app_name/summaries/{actorId}/{sessionId}"] │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 1層目: Memory本体 (aws_bedrockagentcore_memory)

Memory全体の設定を行います。**ここでShort-term Memoryの設定を行います。**

### 必須パラメータ

| パラメータ | 説明 | 例 |
|-----------|------|-----|
| `name` | Memory名 | `"agent-assistant-memory"` |
| `event_expiry_duration` | **Short-term Memoryの保持期間（分）** | `30` (30分), `1440` (24時間) |

### オプションパラメータ

| パラメータ | 説明 | 備考 |
|-----------|------|------|
| `description` | 説明 | `"Memory for customer service agent"` |
| `encryption_key_arn` | KMSキーARN | 暗号化が必要な場合 |
| `memory_execution_role_arn` | IAMロールARN | Strategyでモデル処理する場合に必須 |

### Terraformコード例

```hcl
resource "aws_bedrockagentcore_memory" "agent_memory" {
  name                  = "agent-assistant-memory"
  description           = "Memory for AI assistant agent"
  event_expiry_duration = 1440  # 24時間 = Short-term Memory保持期間

  # オプション: カスタム暗号化
  # encryption_key_arn = aws_kms_key.example.arn

  # オプション: IAMロール（Strategyでモデル使う場合）
  # memory_execution_role_arn = aws_iam_role.example.arn

  tags = {
    Environment = "development"
    Project     = "agentcore-hands-on"
  }
}
```

## 2層目: Memory Strategy (aws_bedrockagentcore_memory_strategy)

**Long-term Memoryの処理方法を定義します。**

### ストラテジーの種類

| タイプ | 説明 | 最大数 | Namespace例 |
|--------|------|--------|-------------|
| **SEMANTIC** | 事実・知識を抽出 | 1つまで | `app_name/knowledge/{actorId}` |
| **USER_PREFERENCE** | ユーザーの好みを記録 | 1つまで | `app_name/preferences/{actorId}` |
| **SUMMARIZATION** | 会話の要約を生成 | 1つまで | `app_name/summaries/{actorId}/{sessionId}` |
| **CUSTOM** | カスタム処理 | 複数可（全体で最大6つ） | 任意 |

### 制約事項

```
┌──────────────────────────────────────────────┐
│  Memoryあたりの制約                          │
│                                              │
│  ・最大6つのStrategyまで                     │
│  ・SEMANTIC: 1つまで                         │
│  ・USER_PREFERENCE: 1つまで                  │
│  ・SUMMARIZATION: 1つまで                    │
│  ・CUSTOM: 複数OK（全体で6つまで）           │
│                                              │
│  例: SEMANTIC(1) + USER_PREFERENCE(1)        │
│      + SUMMARIZATION(1) + CUSTOM(3) = 6つ   │
└──────────────────────────────────────────────┘
```

### Namespaceとは

**Namespaceは、そのStrategyが適用される「データの範囲」を指定します。**

#### Namespace形式のルール

- **スラッシュ (/) で区切られた階層形式**を使用
- 論理的に整理するための階層構造
- 自由に設計可能（制約はない）
- 以下の**定義済み変数**を含めることができる：
  - `{actorId}` - ユーザー識別子（実行時に置き換わる）
  - `{sessionId}` - セッション識別子（実行時に置き換わる）
  - `{memoryStrategyId}` - 戦略識別子（オプション、使わなくてもOK）

**重要:** `{memoryStrategyId}` などの変数は**自動付与されません**。必要な場合は明示的にNamespaceに含める必要があります。

#### AWSコンソールの例示 vs 実際のベストプラクティス

**AWSコンソールで表示される例:**
```
/strategies/{memoryStrategyId}/actors/{actorId}/sessions/{sessionId}
```

これは単なる「例示」です。**実際にはもっとシンプルな形式が一般的です**：

**実際のベストプラクティス例（元記事より）:**
```
tech_learning/knowledge/{actorId}
tech_learning/preferences/{actorId}
tech_learning/summaries/{actorId}/{sessionId}
```

#### Namespace変数の展開例

変数は実行時に実際の値に置き換わります：

```
設定時: tech_learning/preferences/{actorId}
  ↓ 実行時（boto3でretrieve_memoriesを呼ぶ時）
実際: tech_learning/preferences/user-abc123
```

```
設定時: tech_learning/summaries/{actorId}/{sessionId}
  ↓ 実行時
実際: tech_learning/summaries/user-abc123/session-xyz789
```

#### Namespace階層の例

```
Memory: agent-assistant-memory
  │
  ├─ tech_learning/knowledge/user_001
  │   └─ 知識: "Pythonはインタープリタ型言語"
  │
  ├─ tech_learning/preferences/user_001
  │   └─ 好み: "実践的なコード例を好む"
  │
  └─ tech_learning/summaries/user_001/session_xyz
      └─ 要約: "Pythonの基礎文法を学習"
```

#### カスタムNamespaceの設計例

自由に設計できます。以下は実際のプロジェクトでよく使われるパターン：

```hcl
# 例1: アプリケーション名を含める（推奨）
namespaces = ["tech_learning/knowledge/{actorId}"]

# 例2: 環境を分離
namespaces = ["prod/tech_learning/knowledge/{actorId}"]

# 例3: 複数のNamespaceを設定
namespaces = [
  "app_name/knowledge/{actorId}",
  "app_name/facts/{actorId}"
]

# 例4: セッション情報も含める
namespaces = ["app_name/summaries/{actorId}/{sessionId}"]
```

## Terraformコード例: 完全な構成

### ビルトインStrategyを全て使う例

```hcl
# 1. Memory本体（Short-term Memory設定含む）
resource "aws_bedrockagentcore_memory" "agent_memory" {
  name                  = "agent-assistant-memory"
  description           = "Memory for AI assistant"
  event_expiry_duration = 1440  # Short-term: 24時間

  tags = {
    Environment = "development"
  }
}

# 2-1. Semantic Strategy（知識抽出）
resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name        = "semantic_builtin"
  memory_id   = aws_bedrockagentcore_memory.agent_memory.id
  type        = "SEMANTIC"
  description = "Extract technical knowledge and facts from conversations"

  # Namespace: アプリ名/データ種別/ユーザー
  namespaces = ["agent_assistant/knowledge/{actorId}"]
}

# 2-2. User Preference Strategy（好み記録）
resource "aws_bedrockagentcore_memory_strategy" "user_preference" {
  name        = "preference_builtin"
  memory_id   = aws_bedrockagentcore_memory.agent_memory.id
  type        = "USER_PREFERENCE"
  description = "Track user preferences and behavioral patterns"

  # Namespace: アプリ名/データ種別/ユーザー
  namespaces = ["agent_assistant/preferences/{actorId}"]
}

# 2-3. Summarization Strategy（要約生成）
resource "aws_bedrockagentcore_memory_strategy" "summarization" {
  name        = "summary_builtin"
  memory_id   = aws_bedrockagentcore_memory.agent_memory.id
  type        = "SUMMARIZATION"
  description = "Generate session summaries with key insights"

  # Namespace: アプリ名/データ種別/ユーザー/セッション
  namespaces = ["agent_assistant/summaries/{actorId}/{sessionId}"]
}
```

### Custom Strategyの例

```hcl
# IAMロール（Custom Strategyでモデル使う場合に必要）
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "memory_role" {
  name               = "bedrock-agentcore-memory-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "memory_policy" {
  role       = aws_iam_role.memory_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}

# Memory本体（IAMロール指定）
resource "aws_bedrockagentcore_memory" "agent_memory" {
  name                      = "agent-assistant-memory"
  event_expiry_duration     = 1440
  memory_execution_role_arn = aws_iam_role.memory_role.arn
}

# Custom Strategy（Semantic Override）
resource "aws_bedrockagentcore_memory_strategy" "custom_semantic" {
  name                      = "custom-semantic-strategy"
  memory_id                 = aws_bedrockagentcore_memory.agent_memory.id
  memory_execution_role_arn = aws_iam_role.memory_role.arn
  type                      = "CUSTOM"
  description               = "Custom semantic processing with specific models"

  namespaces = ["custom_knowledge/{actorId}"]

  configuration {
    type = "SEMANTIC_OVERRIDE"

    # 統合処理（複数のメモリをまとめる）
    consolidation {
      append_to_prompt = "Focus on extracting key semantic relationships and concepts"
      model_id         = "anthropic.claude-3-sonnet-20240229-v1:0"
    }

    # 抽出処理（Short-termから情報を抽出）
    extraction {
      append_to_prompt = "Extract and categorize semantic information"
      model_id         = "anthropic.claude-3-haiku-20240307-v1:0"
    }
  }
}
```

## データフロー: Short-term → Long-term

```
┌────────────────────────────────────────────────────────────────┐
│  1. ユーザーとの会話                                           │
│     "Pythonのリストって何ですか？"                             │
│     "可変のシーケンス型です"                                   │
└─────────────────┬──────────────────────────────────────────────┘
                  ↓
┌────────────────────────────────────────────────────────────────┐
│  2. Short-term Memory（生データ保存）                          │
│     event_expiry_duration: 1440分間保持                        │
│                                                                │
│     actor_id: user_123                                         │
│     session_id: session_abc                                    │
│     messages: [...会話履歴...]                                 │
└─────────────────┬──────────────────────────────────────────────┘
                  ↓ (非同期処理)
┌────────────────────────────────────────────────────────────────┐
│  3. Long-term Memory（Strategyで処理）                         │
│                                                                │
│  ┌──────────────────────────────────────────────┐             │
│  │ SEMANTIC Strategy                            │             │
│  │ namespace: tech_learning/knowledge/user_123  │             │
│  │ → "Pythonのリストは可変のシーケンス型"       │             │
│  └──────────────────────────────────────────────┘             │
│                                                                │
│  ┌────────────────────────────────────────────────┐           │
│  │ USER_PREFERENCE Strategy                       │           │
│  │ namespace: tech_learning/preferences/user_123  │           │
│  │ → "実践的なコード例を好む"                     │           │
│  └────────────────────────────────────────────────┘           │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐     │
│  │ SUMMARIZATION Strategy                               │     │
│  │ namespace: tech_learning/summaries/user_123/         │     │
│  │            session_abc                               │     │
│  │ → "Pythonの基礎文法について学習した"                 │     │
│  └──────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────┘
```

## Namespace設計のベストプラクティス

### パターン1: アプリケーション名ベース（推奨）

**最もシンプルで実用的なパターン**。実際のプロジェクトで最も使われています：

```hcl
# SEMANTIC / USER_PREFERENCE
namespaces = ["app_name/knowledge/{actorId}"]

# SUMMARIZATION
namespaces = ["app_name/summaries/{actorId}/{sessionId}"]
```

**実例（元記事より）:**
```hcl
namespaces = ["tech_learning/knowledge/{actorId}"]
namespaces = ["tech_learning/preferences/{actorId}"]
namespaces = ["tech_learning/summaries/{actorId}/{sessionId}"]
```

**メリット:**
- シンプルで分かりやすい
- 複数アプリケーションで同じMemoryを使う場合に有効
- アプリケーション単位での管理が容易
- `{memoryStrategyId}` 不要でコードがすっきり

### パターン2: 環境を分離

開発・本番環境を明示的に分離：

```hcl
namespaces = ["prod/app_name/knowledge/{actorId}"]
namespaces = ["dev/app_name/knowledge/{actorId}"]
```

**メリット:**
- 環境ごとにデータを分離
- 誤って本番データを参照するリスクを軽減
- 同一Memoryで複数環境を管理可能

### パターン3: 複数のNamespaceを設定

1つのStrategyで複数のNamespaceを管理：

```hcl
namespaces = [
  "app_name/knowledge/{actorId}",
  "app_name/facts/{actorId}",
  "shared/global_knowledge"  # 全ユーザー共有
]
```

**メリット:**
- ユーザー固有と共有データを同時に扱える
- 柔軟なデータ管理
- 複数のデータソースを統合可能

### パターン4: AWSコンソール例示形式

AWSコンソールで表示される例に従う場合：

```hcl
namespaces = ["/strategies/{memoryStrategyId}/actors/{actorId}"]
```

**注意点:**
- `{memoryStrategyId}` が含まれるため、やや冗長
- 実運用では必須ではない
- 標準化を重視する場合は有効

### 設計時の考慮点

| 観点 | 推奨アプローチ | 例 |
|------|---------------|-----|
| **ユーザー分離** | 必ず`{actorId}`を含める | `app/data/{actorId}` |
| **セッション分離** | SUMMARIZATIONには`{sessionId}`を含める | `app/summary/{actorId}/{sessionId}` |
| **アプリ識別** | 先頭にアプリ名を配置 | `tech_learning/...` |
| **環境分離** | 環境名をプレフィックスに | `prod/app/...` |
| **階層の深さ** | 2-4階層程度に抑える | `app/type/{actorId}` |
| **シンプルさ** | 不要な変数は避ける | ❌ `{memoryStrategyId}` |

## まとめ

### リソース作成の流れ

1. **aws_bedrockagentcore_memory を作成**
   - Short-term Memoryの保持期間を設定（`event_expiry_duration`）
   - 必要ならIAMロールを設定（Custom Strategyを使う場合）

2. **aws_bedrockagentcore_memory_strategy を作成**（1つ以上）
   - Long-term Memoryの処理方法を定義（`type`）
   - Namespaceで適用範囲を指定（`namespaces`）
   - 最大6つまで、ビルトインは各1つまで

### 設定のチェックリスト

- [ ] Short-term Memoryの保持期間は適切か？（分単位で指定）
- [ ] どのStrategyが必要か決めたか？
  - [ ] SEMANTIC（知識抽出）
  - [ ] USER_PREFERENCE（好み記録）
  - [ ] SUMMARIZATION（要約生成）
- [ ] Namespaceの設計は適切か？
  - [ ] **推奨形式**: `app_name/data_type/{actorId}`（シンプルで実用的）
  - [ ] スラッシュ区切りの階層構造を使用
  - [ ] `{actorId}` は必須（ユーザー分離）
  - [ ] `{sessionId}` はSUMMARIZATIONで使用
  - [ ] `{memoryStrategyId}` は通常不要（使わなくてOK）
- [ ] Custom Strategyが必要なら、IAMロールを設定したか？
- [ ] 全体で6つ以下のStrategyか？

### Namespace設定時の注意点

**重要なポイント:**

1. **変数は自動付与されない**
   - `{memoryStrategyId}` などの変数は自動では追加されません
   - 必要な変数は明示的にNamespaceに含める必要があります

2. **実行時の変数展開**
   ```
   設定: tech_learning/preferences/{actorId}
     ↓ boto3でAPIを呼ぶ時
   実際: tech_learning/preferences/user-abc123
   ```

3. **AWSコンソールの例示について**
   - コンソールで表示される `/strategies/{memoryStrategyId}/...` は「例」です
   - 実際にはもっとシンプルな形式で十分機能します
   - `tech_learning/knowledge/{actorId}` のような形式が実用的

4. **戦略名（name）の制約**
   - 英数字、`_`（アンダースコア）、`-`（ハイフン）のみ使用可能
   - 最大48文字

### 次のステップ

1. Terraformで実際にリソースを作成
   ```bash
   cd terraform
   terraform plan
   terraform apply
   ```

2. 作成されたMemory IDを確認
   ```bash
   terraform output memory_id
   ```

3. Memory IDを`.env`に設定
   ```bash
   MEMORY_ID=memory-xxxxxxxxxxxxx
   ```

4. Python SDK (boto3) でMemoryにアクセスするコードを実装

5. エージェントに統合して動作確認
