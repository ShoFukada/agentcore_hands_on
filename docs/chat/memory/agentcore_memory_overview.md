# Amazon Bedrock AgentCore Memory 機能解説

## 概要

Amazon Bedrock AgentCore Memoryは、AIエージェントに記憶機能を持たせるためのマネージドサービスです。
この機能により、エージェントは複数のセッションや長期的な相互作用を通じて、ユーザー情報や学習内容を保持・活用できるようになります。

## メモリの種類

### 1. Short-term Memory（短期記憶）

セッション中の会話履歴を保持する仕組みです。

**特徴:**
- 最大365日間の保存が可能（デフォルト: 90日）
- Actor IDとSession IDでデータを整理
- リアルタイムアクセスが可能
- 生データが直接保存される

**ユースケース:**
- セッション内での文脈維持
- 短期的な会話履歴の参照
- ユーザーごとの会話管理

```
┌─────────────────────────────────────┐
│   Short-term Memory                 │
│                                     │
│   Actor ID: user_123                │
│   Session ID: session_abc           │
│   ├─ Message 1: "Pythonを学びたい" │
│   ├─ Message 2: "リストとは？"     │
│   └─ Message 3: "辞書の使い方は？" │
│                                     │
│   保持期間: 最大365日               │
└─────────────────────────────────────┘
```

### 2. Long-term Memory（長期記憶）

Short-term Memoryから自動的に重要情報を抽出・統合し、長期的に保持します。

**3つの組み込みストラテジー:**

| ストラテジー | 機能 | 抽出内容 |
|-------------|------|----------|
| **SemanticMemoryStrategy** | 事実や知識を抽出・保存 | 技術的な事実、概念、定義 |
| **UserPreferenceMemoryStrategy** | ユーザーの好み・傾向を記録 | 学習スタイル、好みのトピック |
| **SummaryMemoryStrategy** | 会話サマリーを生成 | セッション全体の要約 |

**処理フロー:**

```
Short-term Memory
      ↓
   (自動抽出)
      ↓
┌─────────────────────────────────────────────┐
│         Long-term Memory                    │
├─────────────────────────────────────────────┤
│                                             │
│  📚 Semantic Memory                         │
│  ├─ Pythonはインタープリタ型言語           │
│  ├─ リストは可変のシーケンス型             │
│  └─ 辞書はキーと値のペア                   │
│                                             │
│  👤 User Preference Memory                  │
│  ├─ 実践的な例を好む                       │
│  ├─ 基礎から段階的に学習                   │
│  └─ コード例を重視                         │
│                                             │
│  📝 Summary Memory                          │
│  └─ Session ABC: Pythonの基礎文法を学習    │
│                                             │
└─────────────────────────────────────────────┘
```

## ID階層構造

AgentCore Memoryは3層のID階層で記憶を管理します:

```
Memory ID (メモリインスタンス全体)
    │
    ├─ Actor ID 1 (ユーザーA)
    │   ├─ Session ID 1
    │   ├─ Session ID 2
    │   └─ Session ID 3
    │
    └─ Actor ID 2 (ユーザーB)
        ├─ Session ID 1
        └─ Session ID 2
```

| レベル | ID種別 | 役割 | 例 |
|--------|--------|------|-----|
| 1 | Memory ID | メモリインスタンス全体を識別 | `tech_learning_memory` |
| 2 | Actor ID | ユーザーやエンティティを識別 | `user_123` |
| 3 | Session ID | 学習セッションごとの管理 | `session_abc` |

## Namespace設計パターン

記事で紹介されている技術学習支援システムの例:

```
tech_learning/knowledge/{actorId}          # 技術知識
tech_learning/preferences/{actorId}        # 学習傾向
tech_learning/summaries/{actorId}/{sessionId}  # セッションサマリー
```

**設計のポイント:**
- トップレベルでアプリケーション領域を識別
- ミドルレベルでメモリの種類を分類
- 末尾でアクターやセッションを特定

## アーキテクチャパターン

### 基本的な実装フロー

```
┌─────────┐         ┌──────────────┐         ┌─────────────┐
│  User   │────────→│  Agent       │────────→│  Memory     │
└─────────┘         └──────────────┘         └─────────────┘
     │                     │                        │
     │  1. 質問投稿        │                        │
     │────────────────────→│                        │
     │                     │  2. 過去の記憶取得     │
     │                     │───────────────────────→│
     │                     │←───────────────────────│
     │                     │  3. 記憶を活用して回答 │
     │  4. 回答返却        │                        │
     │←────────────────────│                        │
     │                     │  5. 新しい記憶を保存   │
     │                     │───────────────────────→│
     │                     │                        │
```

### カスタムツールの実装例

記事では4つのカスタムツールを実装して学習分析機能を提供:

1. **analyze_learning_progress**
   - Long-term Memoryから学習進捗を分析
   - 学習した技術トピックを整理

2. **identify_weak_areas**
   - 繰り返し質問されるトピックを特定
   - 苦手分野を識別

3. **get_session_summary**
   - 特定セッションの要約を取得
   - 学習履歴の振り返り

4. **suggest_review_topics**
   - 学習パターンから復習トピックを提案
   - 個別最適化された学習計画

```python
# ツール実装のイメージ
@tool
def analyze_learning_progress(actor_id: str) -> str:
    """学習進捗を分析する"""
    # Long-term Memoryから知識を取得
    memories = memory_client.retrieve(
        actor_id=actor_id,
        namespace="tech_learning/knowledge"
    )

    # 分析ロジック
    topics = extract_topics(memories)
    return format_progress_report(topics)
```

## ユースケース

### 1. チャットボット
- ユーザーごとのセッション管理
- 過去の会話を踏まえた応答
- パーソナライズされた対話

### 2. 技術学習支援
- 理解度の追跡
- 個別最適化された学習パス
- 長期的な進捗管理

### 3. カスタマーサポート
- 問い合わせ履歴の保持
- ユーザー嗜好の記録
- 一貫したサポート体験

### 4. パーソナルアシスタント
- ユーザープロファイルの構築
- 習慣やパターンの学習
- 文脈を考慮した提案

## 注意点と制約事項

### ⚠️ 非同期処理

Long-term Memoryは**非同期**で自動処理されます:
- 即座の反映は保証されない
- 抽出までに時間がかかる場合がある
- リアルタイム性が必要な場合はShort-term Memoryを使用

### 📊 精度と検証

- 長期運用時の精度向上については継続的な検証が必要
- メモリの品質をモニタリングする仕組みを検討

### 🔒 データ分離

- ユーザー間のデータ分離はactor_idで実現
- Namespaceによるスコーピングを適切に設計
- セキュリティとプライバシーを考慮した設計が重要

### 💰 コスト管理

- 保存期間の設定を適切に行う
- 不要なメモリは定期的にクリーンアップ
- ストレージコストを考慮した運用

## 参考資料

- [元記事: Amazon Bedrock AgentCore Memory サンプル実装](https://dev.classmethod.jp/articles/amazon-bedrock-agentcore-memory-sample-agent/)
- AWS Bedrock AgentCore 公式ドキュメント
