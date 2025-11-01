
## デプロイに必要な最低リソース

#### 1. IAMロール (AgentRuntimeRole)
- **目的**: AgentCore Runtimeでの実行権限
- **必須ポリシー**:
  - Bedrock model invoke
  - CloudWatch Logs書き込み
  - ECRイメージ取得
  - 必要に応じてS3、DynamoDBなど

#### 2. Amazon ECR リポジトリ
- **作成方法**: `aws ecr create-repository`
- **アーキテクチャ**: ARM64必須
- **管理**: イメージのビルド・プッシュは手動

#### 3. Agent Runtime
- **作成方法**: `create_agent_runtime` API
- **必須設定**:
  - エージェントランタイム名
  - コンテナURI（ECRから）
  - ネットワーク設定（PUBLIC/PRIVATE）
  - IAMロールARN

#### 4. ネットワーク設定（PRIVATEの場合）
- VPC
- サブネット
- セキュリティグループ
- VPCエンドポイント（Bedrock用）

## 各種リソース

### Agent Runtime
**= AIエージェント用のLambda的なサーバーレス実行環境**

**Terraformリソース:**
- [Agent Runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_agent_runtime) - エージェント実行環境本体
- [Agent Runtime Endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_agent_runtime_endpoint) - エージェント呼び出し用エンドポイント

エージェントのコードを動かすためのコンテナ実行環境。ECRにプッシュしたDockerイメージを指定して作成し、LangGraphやCrewAIなどで書いたエージェントコードを実行できる。Lambdaと同じように自動スケーリングし、インフラ管理が不要。

**Agent Runtime vs Agent Runtime Endpoint:**
- **Agent Runtime**: エージェントの実行環境そのもの（コンテナ、IAMロール、ネットワーク設定など）
- **Agent Runtime Endpoint**: Agent Runtimeの特定バージョンを参照するためのエンドポイント（invoke用のURL/ARN）

**Agent Runtime Endpointの詳細:**

Agent Runtimeは更新のたびに自動的に新しいバージョンが生成されます（Version 1, 2, 3...）。各バージョンは不変で、実行に必要なすべての設定を含む自己完結型です。

**エンドポイントの種類:**
- **DEFAULTエンドポイント**: 常に最新バージョンを自動参照（開発環境向け）
- **カスタムエンドポイント**: 特定バージョンを固定参照（本番環境向け）

**ユースケース例:**
```
開発環境: DEFAULTエンドポイント → 常に最新バージョン
ステージング: custom-stagingエンドポイント → Version 2に固定
本番環境: custom-prodエンドポイント → Version 1に固定
```

これにより、本番環境を安定させつつ、開発環境で新しいバージョンをテストできます。

参考: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agent-runtime-versioning.html

### Memory
**= エージェントが使える記憶領域（短期・長期）**

**Terraformリソース:**
- [Memory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_memory) - メモリストア本体
- [Memory Strategy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_memory_strategy) - メモリの戦略設定

エージェントが会話や過去の情報を覚えておくためのストレージ。短期メモリは1つの会話セッション内での記憶、長期メモリは複数のエージェント間で共有できる永続的な記憶。DynamoDBやRDSのような感覚で、エージェントがデータを保存・取得できる。

[わかりやすいサイトこれ](https://dev.classmethod.jp/articles/amazon-bedrock-agentcore-memory-sample-agent/)
[暗号化したい場合これ](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/storage-encryption.html)

### Code Interpreter
**= コード実行用のサンドボックス環境**

**Terraformリソース:**
- [Code Interpreter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_code_interpreter)

エージェントがPythonなどのコードを動的に実行できる隔離された実行環境。エージェントが「このデータを分析して」と言われたときに、その場でコードを書いて実行できる。セキュリティのために完全に隔離されたサンドボックス内で動作する。

### Browser
**= エージェント専用のヘッドレスブラウザ環境**

**Terraformリソース:**
- [Browser](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_browser)

エージェントがウェブサイトにアクセスしたり操作したりするためのクラウドベースのブラウザ。PuppeteerやPlaywrightのような感覚で、エージェントがWebページの情報を取得したり、フォームを操作したりできる。

### Gateway
**= 既存APIやMCPサーバーをエージェント用ツールに変換するアダプター**

**Terraformリソース:**
- [Gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_gateway)
- [Gateway Target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_gateway_target)

既存のREST API、Lambda関数、MCPサーバーなどを、エージェントが使える標準的なツールとして公開する仕組み。「MCPサーバーのマネージドサービス」として、複数のMCPサーバー（Brave、Tavilyなど）を統合し、エージェントから簡単に利用できるようにする。

**Gateway vs Gateway Target:**
- **Gateway**: API統合のエントリーポイント（Gateway本体）
- **Gateway Target**: Gatewayが呼び出す具体的なターゲット（REST API、Lambda、MCPサーバーなど）

エージェントは「このツールを使いたい」と言うだけで、背後のAPI/MCPサーバーを自動的に呼び出せる。Identity機能と統合することで、APIキーなどの認証情報も安全に管理できる。

**認証の仕組み:**
- **インバウンド認証**: 誰がGatewayを呼び出せるか（IAM or JWT/Cognito）
- **アウトバウンド認証**: Gatewayがどうやって外部API/MCPサーバーにアクセスするか（IAM/OAuth/APIキー）(APIキー等はIdentityで登録されているものを選択する形。)

Cognitoは、JWTベースのインバウンド認証を使う場合に、エージェント呼び出し側のユーザー認証を管理するために使用される。

```mermaid
graph LR
    A[呼び出し側<br/>ユーザー/アプリ] -->|インバウンド認証<br/>IAM or JWT/Cognito| B[Gateway]
    B -->|アウトバウンド認証<br/>IAM/OAuth/APIキー| C[REST API]
    B --> D[Lambda関数]
    B --> E[MCPサーバー<br/>Brave/Tavily等]

    G[Identity<br/>認証情報管理] -.-> B
```

参考: https://zenn.dev/aws_japan/articles/1b29bc6b8de3ca
ちなみにこのリンクの例ではInbound AuthとしてCustom JWT(Cognito Provider)を使っており、agent実行環境上でclient credentialsフロー(つまり、agentのみの認証)としてトークンを取得している。

### Identity (Credential Provider)
**= エージェント用の認証情報管理サービス**

**Terraformリソース:**
- [API Key Credential Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_api_key_credential_provider) - APIキー認証用
- [OAuth2 Credential Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_oauth2_credential_provider) - OAuth2認証用
- [Workload Identity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_workload_identity) - AWSワークロードアイデンティティ認証用
- [Token Vault CMK](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_token_vault_cmk) - 認証トークン暗号化用のKMSキー

エージェントが外部サービスにアクセスする際の認証情報を安全に管理する仕組み。Secrets Managerのような感覚(apikey等の実態はsecrets managerに保存される。)で、以下の認証方式をサポート:
- **API Key**: APIキーベースの認証
- **OAuth2**: OAuth2フローでの認証
- **Workload Identity**: AWSワークロードアイデンティティでの認証

### Observability
**= エージェントの動作を監視・デバッグする仕組み**

**Terraformリソース:**
- 現時点ではTerraformリソース未提供（コンソール/APIのみ）

**設定方法:**
- AgentCore SDK を使ってエージェントをデプロイすることで、Observabilityが自動的に有効化される
- **前提条件**: AWSアカウント単位で「Enable Transaction Search」を事前にオンにする必要がある

エージェントの実行状況をトレースし、パフォーマンスを監視するための機能。CloudWatch LogsやX-Rayのような感覚で、OpenTelemetry形式のテレメトリデータを収集し、エージェントの動作を可視化できる。

## AgentCore Identity, Gateway と認証について

![AgentCore認証の仕組み](agentcore_auth.png)

### 認証の全体像

AgentCoreでは**2段階の認証**があります：

1. **Inbound認証（入口）**: 誰がAgent/Gatewayを使えるか
2. **Outbound認証（出口）**: Agent/Gatewayがどのリソースにアクセスできるか

```mermaid
graph LR
    User[ユーザー/アプリ]
    Agent[Agent Runtime]
    Gateway[Gateway]
    Target1[Lambda/AWS]
    Target2[外部API<br/>Tavily/Google等]
    Identity[Identity<br/>Credential Provider]

    User -->|①Inbound認証<br/>IAM or JWT| Agent
    Agent -->|②Inbound認証<br/>Workload Token| Gateway
    Gateway -->|③Outbound認証<br/>IAM Role| Target1
    Gateway -->|③Outbound認証<br/>OAuth/API Key| Target2

    Identity -.->|認証情報提供| Gateway

    style User fill:#e1f5ff
    style Agent fill:#fff4e1
    style Gateway fill:#ffe1f5
    style Identity fill:#e1ffe1
```

### Inbound認証 vs Outbound認証

| | Inbound認証 | Outbound認証 |
|---|---|---|
| **認証タイミング** | ユーザー → Agent/Gateway | Agent/Gateway → 外部リソース |
| **認証方式** | AWS_IAM または CUSTOM_JWT | IAM/OAuth/API Key |
| **設定場所** | `authorizer_type` | Gateway Target の設定 |


### パターン1: AWS IAM認証（ログイン不要）

**ユースケース**: AWSサービス（EC2、Lambda、ECS等）からの呼び出し

```mermaid
sequenceDiagram
    participant Caller as 呼び出し元<br/>(EC2/Lambda等)
    participant Runtime as AgentCore Runtime<br/>(AWS_IAM)
    participant Agent as Agent Logic
    participant GW as Gateway
    participant Identity as Identity<br/>(Credential Provider)
    participant Tavily as Tavily API

    Note over Caller: ログイン不要！<br/>IAMロールが自動付与
    Caller->>Runtime: Runtimeにリクエスト<br/>(AWS SigV4署名自動付与)
    Runtime->>Runtime: Inbound Auth<br/>IAMポリシーチェック<br/>bedrock-agentcore:InvokeAgentRuntime
    Runtime-->>Caller: ✓ 認証成功

    Runtime->>Agent: Agent実行
    Agent->>Agent: ツール呼び出し判断<br/>tool_call("tavily_search")

    Agent->>GW: Gatewayにリクエスト<br/>(Workload Token)
    GW->>GW: Gateway Inbound Auth<br/>このRuntimeは許可されているか？
    GW-->>Agent: ✓ 認証成功

    GW->>Identity: Tavily API Key取得<br/>(Credential Provider)
    Identity-->>GW: API Key返却
    GW->>Tavily: API呼び出し<br/>X-API-Key: <key>
    Tavily->>Tavily: API Key検証
    Tavily-->>GW: 検索結果
    GW-->>Agent: レスポンス
    Agent-->>Caller: 最終結果

    Note over Caller,Tavily: すべて自動認証<br/>開発者はコード不要
```

**特徴**:
- ユーザーログイン不要(つまり、上の画像において、AgentRuntime前のInbound Authは用意しなくても良いということ。)
- IAMロールに権限があればOK

### パターン2: JWT認証

**ユースケース**: Webアプリ、モバイルアプリからの呼び出し

```mermaid
sequenceDiagram
    participant User as 太郎さん<br/>(Webブラウザ)
    participant Cognito as Amazon Cognito<br/>(IdP)
    participant Runtime as AgentCore Runtime<br/>(CUSTOM_JWT)
    participant Agent as Agent Logic
    participant GW as Gateway
    participant Identity as Identity<br/>(Credential Provider)
    participant Tavily as Tavily API

    User->>Cognito: ログイン<br/>(email/password)
    Cognito->>Cognito: 認証確認
    Cognito-->>User: JWTトークン発行<br/>{sub: "taro123", ...}

    Note over User: ここからAgentにアクセス
    User->>Runtime: Runtimeにリクエスト<br/>Authorization: Bearer <JWT>
    Runtime->>Runtime: Inbound Auth<br/>JWT検証<br/>①署名確認<br/>②有効期限<br/>③allowed_audience
    Runtime-->>User: ✓ 太郎さんとして認証

    Runtime->>Agent: Agent実行
    Agent->>Agent: ツール呼び出し判断<br/>tool_call("tavily_search")

    Agent->>GW: Gatewayにリクエスト<br/>(Workload Token + user_id)
    GW->>GW: Gateway Inbound Auth<br/>このRuntimeとユーザーは許可？
    GW-->>Agent: ✓ 認証成功

    GW->>Identity: Tavily API Key取得<br/>(Credential Provider)
    Identity-->>GW: API Key返却
    GW->>Tavily: API呼び出し<br/>X-API-Key: <key>
    Tavily->>Tavily: API Key検証
    Tavily-->>GW: 検索結果
    GW-->>Agent: レスポンス
    Agent-->>User: 最終結果

    Note over User,Tavily: ユーザーログイン必須<br/>Cognitoと連携が必要
```

**特徴**:
- ユーザーログイン必須(Client Credntialsフローのみ不要)


### Identity（Credential Provider）の役割

**Identity = 外部APIの認証情報を安全に管理する仕組み**

```mermaid
graph TD
    GW[Gateway]
    Identity[Identity Service]
    APIKey[API Key Provider]
    OAuth[OAuth2 Provider]
    Vault[Token Vault<br/>暗号化ストレージ]

    Tavily[Tavily API]
    Google[Google Drive API]
    Slack[Slack API]

    GW -->|Tavily用の認証情報が必要| Identity
    Identity -->|API Key方式| APIKey
    Identity -->|OAuth方式| OAuth

    APIKey -->|暗号化保存| Vault
    OAuth -->|OAuth Token保存<br/>Key: WorkloadID + UserID| Vault

    Vault -.->|API Key| Tavily
    Vault -.->|OAuth Token| Google
    Vault -.->|OAuth Token| Slack

    style Identity fill:#e1ffe1
    style Vault fill:#fff4e1
```


## Tips
[Agentcore IAMをまとめたサイト](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-iam-awsmanpol.html)
[同上](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonbedrockagentcore.html)
