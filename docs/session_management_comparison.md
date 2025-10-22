# Strands Agentのセッション管理とAgentCore Memoryの比較

## 概要

Strands AgentをAmazon Bedrock AgentCore上で使用する際、セッション管理には2つの選択肢があります:

1. **Strands独自のS3SessionManager**: S3バケットを使った自前のセッション管理
2. **AgentCore Memory**: AWSが提供するマネージドメモリサービス

このドキュメントでは、両者の違いとAgentCore Memoryを使う利点を解説します。

## Strands S3SessionManagerとは

### 概要
Strands SDKが提供するS3ベースのセッション永続化機構です。開発者が指定したS3バケットに会話ログとエージェント状態を保存します。

### 動作の仕組み

#### データモデル
セッションデータは3つのモデルで構造化されます:

- **Session**: セッションIDとタイムスタンプを含むトップレベルコンテナ
- **SessionAgent**: エージェント固有の状態と設定を保存
- **SessionMessage**: 会話履歴を保存

#### 永続化トリガー
以下のイベント時に自動的にS3へ保存されます:

- エージェント初期化
- メッセージ追加
- エージェント実行
- メッセージ削除

#### 必要なIAM権限
```json
{
  "s3:PutObject",
  "s3:GetObject",
  "s3:DeleteObject",
  "s3:ListBucket"
}
```

#### 実装例
```python
from strands_agents import Agent, S3SessionManager

session_manager = S3SessionManager(
    session_id="user-456",
    bucket="my-agent-sessions",
    prefix="production/"
)

agent = Agent(session_manager=session_manager)
```

### 開発者が実装する必要があるもの

- S3バケットの設計と運用（バケット作成、命名規則、権限管理）
- データ構造の設計（JSONスキーマ）
- ライフサイクル管理（古いセッションの削除）
- 暗号化設定
- 検索機能（過去の会話を検索する場合）
- 要約・分析ロジック（必要な場合）

## AgentCore Memoryとは

### 概要
Amazon Bedrock AgentCoreが提供するフルマネージドのメモリサービスです。短期・長期の両方のメモリを自動管理し、セマンティック検索や要約機能を標準で提供します。

### 動作の仕組み

#### 短期メモリ (Short-Term Memory)
- イミュータブルなイベントとして生の対話データをキャプチャ
- アクターとセッション単位で整理
- リアルタイムで会話コンテキストを保持
- `create_event`アクションで即座に保存

#### 長期メモリ (Long-Term Memory)
3つのメモリ戦略をサポート:

1. **ユーザー嗜好学習**: ユーザーの行動パターンや好みを学習
2. **セマンティックファクト**: ドメイン固有の知識を保存
3. **セッションサマリー**: 対話内容の要約を自動生成

#### メモリ保持期間
- 設定可能範囲: 1〜365日
- デフォルト: 30日
- イベント単位で有効期限を設定可能

#### セキュリティ
- 転送中・保管時の両方で暗号化
- AWS管理キーまたは顧客管理KMSキーを選択可能
- テナント分離が自動で実施

#### 実装例
```python
from bedrock_agentcore.memory import MemoryClient

client = MemoryClient(region_name="us-west-2")

# メモリリソースの作成
memory = client.create_memory(
    name="CustomerSupportAgentMemory",
    description="顧客サポート会話用メモリ",
    strategies=["USER_PREFERENCES", "SESSION_SUMMARIES"]
)

# イベントの保存
client.create_event(
    memory_id=memory.id,
    session_id="session-123",
    event_data={
        "role": "user",
        "content": "注文状況を確認したい"
    }
)

# セマンティック検索で関連記憶を取得
results = client.query_memory(
    memory_id=memory.id,
    query="過去の注文履歴"
)
```

## 比較表

| 観点 | Strands S3 SessionManager | AgentCore Memory |
| --- | --- | --- |
| **プロビジョニング** | バケット、IAM、命名規則を自前で設計・運用 | AgentCoreがメモリリソースをマネージド提供 |
| **データ構造** | JSONファイルを開発者が定義し、検索・要約は別途実装 | 短期/長期メモリと抽出ストラテジーを設定するだけで自動化 |
| **メモリタイプ** | セッション履歴のみ（単一レベル） | 短期・長期メモリの二層構造で自動抽出・要約 |
| **検索機能** | S3オブジェクト検索や埋め込み計算を自力で構築 | セマンティック検索APIが標準で提供 |
| **スケーラビリティ** | S3のスケーラビリティに依存、検索は自前実装 | サーバーレスで自動スケール、組み込みベクトル検索 |
| **セキュリティ** | バケットポリシーや暗号化、監査を個別対応 | AgentCoreのガードレールとテナント分離に一元化 |
| **運用負荷** | ライフサイクル、GC、バックアップを全て自前管理 | API呼び出しのみ、インフラ運用不要 |
| **コスト** | S3ストレージ + データ転送 + 検索実装コスト | AgentCore Memory利用料（2025年9月16日まで無料） |

## AgentCore Memoryを使う利点

### 1. 運用負荷の大幅削減
- S3バケット管理が不要
- ライフサイクル・GC処理が自動
- IAM権限設計が簡略化
- API利用に集中できる

### 2. リッチな文脈復元機能
- 自動要約がビルトイン
- セマンティック検索で関連記憶を取得
- 長期記憶の自動抽出・統合
- Strandsのカスタム実装が最小化

### 3. エンタープライズグレードのセキュリティ
- 転送中・保管時の暗号化が標準
- AgentCoreガードレールと統合
- テナント分離が自動
- 監査・コンプライアンス対応が容易

### 4. 他のAgentCoreサービスとの統合
- Runtime、Gateway、Toolsと同じ権限モデル
- 統一された監視・トレーシング
- 一元的な運用管理
- モデルやコネクタとシームレス連携

### 5. 開発速度の向上
- インフラコードの記述不要
- 検索・要約ロジックの実装不要
- すぐに本質的な機能開発に集中可能

## Strands AgentとAgentCore Memoryの統合手順

### 1. Strandsプロジェクトの準備
```bash
pip install strands-agents bedrock-agentcore
```

### 2. AgentCore Memory リソースの作成
```python
from bedrock_agentcore.memory import MemoryClient

client = MemoryClient(region_name="us-west-2")
memory = client.create_memory(
    name="MyStrandsAgentMemory",
    description="Strands Agent用のセッションメモリ",
    strategies=["SESSION_SUMMARIES", "SEMANTIC_FACTS"]
)

print(f"Memory ID: {memory.id}")
```

### 3. Strandsエージェントの修正
従来のS3SessionManagerの代わりにAgentCore Memoryを参照:

```python
from strands_agents import Agent
from bedrock_agentcore.memory import MemoryClient

# AgentCore Memoryクライアント初期化
memory_client = MemoryClient(region_name="us-west-2")
memory_id = "your-memory-id"

# Strandsエージェント作成
agent = Agent(
    name="CustomerSupport",
    # AgentCore Memoryを使用する設定
    memory_config={
        "type": "agentcore",
        "memory_id": memory_id,
        "client": memory_client
    }
)

# 会話実行（メモリは自動保存）
response = agent.run(
    "前回の注文状況を教えて",
    session_id="user-123"
)
```

### 4. AgentCore Runtimeへのデプロイ
```bash
# bedrock_agentcore.yamlを生成
agentcore init

# デプロイ
agentcore deploy --config bedrock_agentcore.yaml

# 実行
agentcore invoke --agent-id your-agent-id --input "こんにちは"
```

### 5. 動作確認
```python
# メモリ内容の確認
events = memory_client.list_events(
    memory_id=memory_id,
    session_id="user-123"
)

for event in events:
    print(f"{event.timestamp}: {event.content}")

# 長期記憶の確認
summaries = memory_client.get_summaries(
    memory_id=memory_id,
    session_id="user-123"
)
```

## ユースケース別の推奨

### S3SessionManagerが適している場合
- プロトタイプや個人プロジェクト
- 完全なデータ構造制御が必要
- 既存のS3ベースのデータパイプラインと統合
- コスト最適化が最優先（検索不要の単純保存）

### AgentCore Memoryが適している場合
- 本番環境での運用
- セマンティック検索や要約が必要
- エンタープライズのセキュリティ・コンプライアンス要件
- 複数エージェント間でのメモリ共有
- 開発速度とメンテナンス性を重視

## 運用ヒント

### 段階的な導入
1. まず短期メモリのみで開始
2. 使用パターンを分析
3. 必要に応じて長期メモリストラテジーを有効化
4. コストと運用負荷を段階的に最適化

### 既存S3データの移行
- AgentCore Memory APIでイベントをインポート
- S3アーカイブは二次分析用に保持
- 二重実装を避けるためAgentCore側でエクスポート機能を活用

### モニタリング
- AgentCoreのトレーシング/メトリクスを有効化
- メモリアクセスのパフォーマンスを監視
- ボトルネックの継続的な改善

## まとめ

Strands AgentをAgentCore上で運用する場合、**AgentCore Memoryの使用を強く推奨**します。

理由:
- インフラ運用負荷が劇的に削減
- セマンティック検索・要約が標準機能
- セキュリティ・コンプライアンスが統合済み
- 他のAgentCoreサービスとシームレスに連携

S3SessionManagerは学習目的やプロトタイプには有用ですが、本番環境ではAgentCore Memoryの利点が圧倒的です。

## 参考リンク

- [Amazon Bedrock AgentCore 公式ドキュメント](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/what-is-bedrock-agentcore.html)
- [AgentCore Memory 入門ガイド](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-getting-started.html)
- [Strands Agents セッション管理](https://strandsagents.com/latest/documentation/docs/user-guide/concepts/agents/session-management/)
- [Strands AgentsをAgentCoreにデプロイ](https://strandsagents.com/latest/documentation/docs/user-guide/deploy/deploy_to_bedrock_agentcore/)
