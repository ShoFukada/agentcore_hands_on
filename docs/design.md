# AgentCore ハンズオン設計書

## 1. 概要
AgentCoreを使用したAIエージェントシステムの構築。Strands Agentsフレームワークをベースに、Web検索・コード実行・RAG機能を持つエージェントをデプロイする。

## 2. アーキテクチャ

### 2.1 AWS構成図

```mermaid
graph TB
    subgraph "外部サービス"
        User[ユーザー/アプリケーション]
        Tavily[Tavily API]
    end

    subgraph "AWS Account"
        subgraph "Amazon ECR"
            ECR[ECRリポジトリ<br/>ARM64イメージ]
        end

        subgraph "AgentCore Services"
            Runtime[Agent Runtime<br/>コンテナ実行環境]
            Memory[Memory<br/>短期/長期メモリ]
            Code[Code Interpreter<br/>サンドボックス実行]
            Browser[Browser<br/>ヘッドレスブラウザ]
            Gateway[Gateway<br/>API統合]
            Identity[Identity<br/>認証情報管理]
        end

        subgraph "Amazon Bedrock"
            LLM[Foundation Model<br/>Claude/etc]
            KB[Knowledge Base<br/>ベクトル検索]
        end

        subgraph "Storage"
            S3[S3 Bucket<br/>ドキュメント保存]
            RDS[RDS for PostgreSQL<br/>pgvectorベクトルストア]
        end

        subgraph "IAM"
            Role[AgentRuntimeRole<br/>実行権限]
        end

        subgraph "Monitoring"
            CW[CloudWatch Logs<br/>ログ収集]
            Metrics[OpenTelemetry<br/>メトリクス]
        end

        subgraph "Network (Optional)"
            VPC[VPC]
            Subnet[Private Subnet]
            SG[Security Group]
            VPCEndpoint[VPC Endpoint<br/>Bedrock]
        end
    end

    User -->|リクエスト| Runtime
    Runtime -->|イメージ取得| ECR
    Runtime -->|AssumeRole| Role
    Runtime -->|推論| LLM
    Runtime -->|ツール呼び出し| Memory
    Runtime -->|ツール呼び出し| Code
    Runtime -->|ツール呼び出し| Browser
    Runtime -->|ツール呼び出し| Gateway
    Runtime -->|ベクトル検索| KB
    Gateway -->|認証情報取得| Identity
    Gateway -->|Web検索| Tavily
    KB -->|ドキュメント読取| S3
    KB -->|Embedding取得| RDS
    S3 -->|ドキュメント| KB
    KB -->|Embedding保存| RDS
    Runtime -->|ログ出力| CW
    Runtime -->|メトリクス送信| Metrics

    VPC -.->|Private接続| Runtime
    Subnet -.->|配置| Runtime
    SG -.->|ファイアウォール| Runtime
    VPCEndpoint -.->|Private接続| LLM

    style Runtime fill:#FF9900
    style LLM fill:#FF9900
    style KB fill:#FF9900
    style S3 fill:#569A31
    style RDS fill:#3B48CC
    style ECR fill:#FF9900
    style CW fill:#FF4F8B
```

### 2.2 コンポーネント関係図

```mermaid
graph TB
    User[ユーザー]
    Runtime[Agent Runtime<br/>Strands Agents]
    LLM[Bedrock LLM]

    Memory[Memory<br/>会話履歴管理]
    Code[Code Interpreter<br/>Python/TypeScript]
    Browser[Browser<br/>Webスクレイピング]
    Gateway[Gateway<br/>API統合]
    Identity[Identity<br/>認証情報管理]
    KB[Knowledge Base<br/>RAG]
    S3[S3<br/>ドキュメント]
    Tavily[Tavily API<br/>Web検索]

    User --> Runtime
    Runtime --> LLM
    Runtime --> Memory
    Runtime --> Code
    Runtime --> Browser
    Runtime --> Gateway
    Runtime --> KB
    Gateway --> Identity
    Gateway --> Tavily
    KB --> S3
```

## 3. コンポーネント設計

### 3.1 Agent Runtime
- **フレームワーク**: Strands Agents
- **デプロイ方法**: ECRコンテナイメージ（ARM64）
- **実行環境**: サーバーレス自動スケーリング
- **必須IAMロール**: AgentRuntimeRole
  - Bedrock model invoke
  - CloudWatch Logs書き込み
  - ECRイメージ取得

### 3.2 Memory
- **短期メモリ**: セッション内コンテキスト管理
- **長期メモリ**: エージェント間で共有可能な永続ストレージ
- **用途**: 会話履歴、エージェント状態の保存

### 3.3 Code Interpreter
- **Python実行環境**: データ分析・処理タスク
- **TypeScript実行環境**: JavaScript操作
- **セキュリティ**: サンドボックス隔離環境

### 3.4 Browser
- **機能**: ヘッドレスブラウザ
- **用途**: Webスクレイピング、ページ操作、情報抽出

### 3.5 Gateway + Identity
- **Gateway**: REST API/MCPサーバーをエージェントツール化
- **Identity**: 認証情報管理（OAuth2/APIキー）
- **統合API**: Tavily（Web検索）
- **認証フロー**:
  - インバウンド: IAM or JWT/Cognito
  - アウトバウンド: IAM/OAuth/APIキー（Identityから取得）

```mermaid
graph LR
    Caller[呼び出し側<br/>ユーザー/アプリ]
    Gateway[Gateway]
    Identity[Identity<br/>認証情報管理]
    RestAPI[REST API]
    Lambda[Lambda関数]
    MCP[MCPサーバー<br/>Brave/Tavily等]

    Caller -->|インバウンド認証<br/>IAM or JWT/Cognito| Gateway
    Gateway -->|アウトバウンド認証<br/>IAM/OAuth/APIキー| RestAPI
    Gateway --> Lambda
    Gateway --> MCP
    Identity -.-> Gateway
```

### 3.6 RAG (Knowledge Base)
- **サービス**: Amazon Bedrock Knowledge Base
- **データソース**: S3バケット（元ドキュメント）
- **ベクトルストア**: RDS for PostgreSQL（pgvector）
- **検索方式**: ベクトル化による意味検索
- **フロー**:
  1. S3にドキュメントをアップロード
  2. Knowledge Baseがドキュメントをチャンク化
  3. BedrockでEmbedding生成
  4. RDS（pgvector）にベクトル保存
  5. クエリ時はRDSでベクトル検索
- **アクセス**: エージェントから直接クエリ

## 4. デプロイ要件

### 4.1 必須リソース
1. **IAMロール** (AgentRuntimeRole)
2. **ECRリポジトリ** (ARM64アーキテクチャ)
3. **Agent Runtime** (create_agent_runtime API)
4. **RDS for PostgreSQL** (pgvector拡張有効化)
5. **S3バケット** (Knowledge Baseドキュメント保存)
6. **ネットワーク設定** (PRIVATEの場合):
   - VPC
   - サブネット（RDS用とRuntime用）
   - セキュリティグループ
   - VPCエンドポイント（Bedrock用）

### 4.2 外部サービス
- **Tavily API**: Web検索機能（Gateway経由）
- **Amazon Bedrock**: LLMモデル
- **Amazon S3**: Knowledge Baseドキュメント保存

## 5. データフロー

### 5.1 基本フロー

```mermaid
sequenceDiagram
    participant User as ユーザー
    participant Runtime as Agent Runtime
    participant LLM as Bedrock LLM
    participant Tool as ツール<br/>(Memory/Code/Browser/Gateway/KB)

    User->>Runtime: リクエスト
    Runtime->>LLM: プロンプト送信
    LLM->>Runtime: ツール選択指示
    Runtime->>Tool: ツール実行
    Tool->>Runtime: 実行結果
    Runtime->>LLM: 結果を含めて再送信
    LLM->>Runtime: 最終レスポンス
    Runtime->>User: レスポンス返却
```

### 5.2 Web検索フロー

```mermaid
sequenceDiagram
    participant Runtime as Agent Runtime
    participant Gateway
    participant Identity
    participant Tavily as Tavily API

    Runtime->>Gateway: 検索リクエスト<br/>(インバウンド認証)
    Gateway->>Identity: 認証情報取得
    Identity->>Gateway: APIキー返却
    Gateway->>Tavily: 検索実行<br/>(アウトバウンド認証)
    Tavily->>Gateway: 検索結果
    Gateway->>Runtime: 結果返却
```

### 5.3 RAGフロー（セットアップ）

```mermaid
sequenceDiagram
    participant Admin as 管理者
    participant S3
    participant KB as Knowledge Base
    participant Bedrock as Bedrock Embedding
    participant RDS as RDS (pgvector)

    Admin->>S3: ドキュメントアップロード
    S3->>KB: 同期トリガー
    KB->>S3: ドキュメント読取
    KB->>KB: チャンク化
    KB->>Bedrock: Embedding生成リクエスト
    Bedrock->>KB: Embeddingベクトル
    KB->>RDS: ベクトル保存
```

### 5.4 RAGフロー（検索時）

```mermaid
sequenceDiagram
    participant Runtime as Agent Runtime
    participant KB as Knowledge Base
    participant Bedrock as Bedrock Embedding
    participant RDS as RDS (pgvector)

    Runtime->>KB: クエリ送信
    KB->>Bedrock: クエリのEmbedding生成
    Bedrock->>KB: クエリベクトル
    KB->>RDS: ベクトル類似度検索
    RDS->>KB: 関連チャンク
    KB->>Runtime: コンテキスト拡張された結果
```

## 6. セキュリティ

- **コード実行**: サンドボックス隔離
- **認証情報**: Identity（Secrets Manager相当）で管理
- **ネットワーク**: VPC内プライベート通信（オプション）
- **IAM**: 最小権限の原則

## 7. モニタリング

- **ログ**: CloudWatch Logs
- **トレース**: OpenTelemetry対応
- **メトリクス**: エージェント実行状況の可視化
