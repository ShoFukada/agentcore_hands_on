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

        subgraph "Observability"
            XRay[AWS X-Ray<br/>分散トレーシング]
            CW[CloudWatch Logs<br/>ログ収集]
            TxSearch[Transaction Search<br/>スパン検索]
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
    Runtime -->|トレース送信| XRay
    Runtime -->|ログ出力| CW
    Runtime -->|メトリクス送信| Metrics
    XRay -->|スパン転送| CW
    CW -->|インデックス化| TxSearch

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

### 3.7 Observability
- **トレーシング**: AWS X-Ray による分散トレーシング
- **ログ収集**: CloudWatch Logs
- **スパン収集**: CloudWatch Transaction Search
- **メトリクス**: OpenTelemetry
- **可視化機能**:
  - エージェント実行フローの追跡
  - ツール呼び出しのトレース
  - LLM推論リクエスト/レスポンスの記録
  - パフォーマンスボトルネックの特定
  - エラー発生箇所の特定
- **設定要件**:
  - X-Ray トレースセグメント送信先を CloudWatch Logs に設定
  - CloudWatch Logs リソースポリシーで X-Ray からのアクセスを許可
  - エージェント実行時に自動的にトレースデータ収集
  - トレースサンプリング率の設定（オプション）

```mermaid
graph LR
    Runtime[Agent Runtime]
    XRay[AWS X-Ray]
    CWLogs[CloudWatch Logs]
    TxSearch[Transaction Search]

    Runtime -->|トレース送信| XRay
    XRay -->|スパン転送| CWLogs
    CWLogs -->|インデックス化| TxSearch
    TxSearch -->|検索・分析| User[開発者]
```
