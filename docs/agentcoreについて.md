
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
- 現時点ではTerraformリソース未提供（コンソール/APIのみ）

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

### Identity (Credential Provider)
**= エージェント用の認証情報管理サービス**

**Terraformリソース:**
- [API Key Credential Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_api_key_credential_provider) - APIキー認証用
- OAuth2/Workload Providerは現時点では未提供の可能性あり

エージェントが外部サービスにアクセスする際の認証情報を安全に管理する仕組み。Secrets Managerのような感覚で、以下の認証方式をサポート:
- **API Key**: APIキーベースの認証（Terraform対応済み）
- **OAuth2**: OAuth2フローでの認証（今後対応予定？）
- **Workload Provider**: AWSワークロードアイデンティティでの認証（今後対応予定？）

### Observability
**= エージェントの動作を監視・デバッグする仕組み**

**Terraformリソース:**
- 現時点ではTerraformリソース未提供（コンソール/APIのみ）

エージェントの実行状況をトレースし、パフォーマンスを監視するための機能。CloudWatch LogsやX-Rayのような感覚で、OpenTelemetry形式のテレメトリデータを収集し、エージェントの動作を可視化できる。

## Tips
[Agentcore IAMをまとめたサイト](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-iam-awsmanpol.html)
[同上](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonbedrockagentcore.html)
