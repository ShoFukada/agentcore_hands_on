# AWS IAM認証を使用したAgentCore Gateway接続ガイド

## 概要

Amazon Bedrock AgentCore Gatewayは、2つの主要な認証方式をサポートしています：

1. **AWS_IAM (SigV4認証)** - AWS標準のIAM認証（本ドキュメントの対象）
2. **CUSTOM_JWT (OAuth/Cognito)** - JWTトークンベース認証

本ドキュメントでは、**AgentCore Runtime内からGatewayにアクセスする際のAWS_IAM認証**の実装方法について説明します。

---

## 問題の背景

### 発生した問題

AgentCore Runtime上で実行しているPythonコードから、MCP Client (`streamablehttp_client`) を使用してGatewayに接続しようとした際、`401 Unauthorized`エラーが発生しました。

```python
# 失敗したコード例
mcp_client = MCPClient(lambda: streamablehttp_client(settings.GATEWAY_URL))
```

**エラーログ:**
```
HTTP Request: POST https://agentcore-hands-on-gateway-gxaburshtd.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp
"HTTP/1.1 401 Unauthorized"
```

### 原因

AgentCore Runtime上で実行していても、**MCPクライアントがGatewayにアクセスする際には、明示的にAWS SigV4署名付きヘッダーが必要**です。

`streamablehttp_client(url)`だけでは、IAM認証のヘッダーは自動的に付与されません。

---

## 認証の仕組み

### Inbound認証とOutbound認証

AgentCore Gatewayには2種類の認証があります：

1. **Inbound認証**: 誰がGatewayにアクセスできるか（Runtime → Gateway）
2. **Outbound認証**: Gatewayが何にアクセスできるか（Gateway → Target API）

本ドキュメントで扱うのは **Inbound認証（AWS_IAM）** です。

### AWS_IAM認証フロー

```
AgentCore Runtime
    ↓
    1. AWS認証情報を取得（IAMロール）
    ↓
    2. リクエストにSigV4署名を追加
    ↓
    3. 署名付きHTTPリクエストを送信
    ↓
AgentCore Gateway (AWS_IAM検証)
    ↓
    4. 署名を検証してアクセス許可
    ↓
MCP Server / Target API
```

---

## 実装方法

### 方法1: AWS SigV4署名の手動実装（推奨）

最も確実な方法は、`botocore`を使用してSigV4署名を手動で生成し、`streamablehttp_client`にヘッダーとして渡すことです。

#### 完全な実装例

```python
import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from mcp.client.streamable_http import streamablehttp_client
from strands.tools.mcp.mcp_client import MCPClient
from urllib.parse import urlparse


def generate_sigv4_headers(url: str, region: str, service: str = "bedrock-agentcore") -> dict[str, str]:
    """AWS SigV4署名付きヘッダーを生成する

    Args:
        url: 署名対象のURL
        region: AWSリージョン
        service: AWSサービス名（デフォルト: bedrock-agentcore）

    Returns:
        dict[str, str]: SigV4署名付きヘッダー
    """
    # boto3セッションからAWS認証情報を取得
    session = boto3.Session()
    credentials = session.get_credentials()

    # URLをパース
    parsed_url = urlparse(url)

    # AWS Request オブジェクトを作成
    request = AWSRequest(
        method="POST",
        url=url,
        headers={
            "Host": parsed_url.netloc,
            "Content-Type": "application/json",
        },
    )

    # SigV4署名を追加
    SigV4Auth(credentials, service, region).add_auth(request)

    # 署名済みヘッダーを返す
    return dict(request.headers)


# 使用例
gateway_url = "https://agentcore-hands-on-gateway-gxaburshtd.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp"
region = "us-east-1"

# 署名付きヘッダーを生成
headers = generate_sigv4_headers(gateway_url, region)

# MCPクライアントを作成（署名付きヘッダーを渡す）
mcp_client = MCPClient(
    lambda: streamablehttp_client(gateway_url, headers=headers)
)

# withステートメントでライフサイクル管理
with mcp_client:
    tools = mcp_client.list_tools_sync()
    # ツールを使用...
```

#### ポイント

1. **boto3セッション**: Runtime上のIAMロールから自動的に認証情報を取得
2. **AWSRequest**: 署名対象のリクエストを表現
3. **SigV4Auth**: AWS Signature Version 4による署名を追加
4. **headers引数**: `streamablehttp_client`に署名済みヘッダーを渡す

---

### 方法2: httpx.Authを使用したカスタム認証クラス

より高度な実装として、`httpx.Auth`を継承したカスタム認証クラスを作成する方法もあります。

#### 実装例（参考: kane.mx記事）

```python
import httpx
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import boto3


class HTTPXSigV4Auth(httpx.Auth):
    """httpx用のAWS SigV4認証ハンドラ"""

    def __init__(self, credentials, service: str, region: str):
        self.credentials = credentials
        self.service = service
        self.region = region

    def auth_flow(self, request: httpx.Request):
        """リクエストにSigV4署名を追加"""
        # リクエストボディを取得
        body = request.content.decode('utf-8') if request.content else ''

        # AWSRequestオブジェクトを作成
        aws_request = AWSRequest(
            method=request.method,
            url=str(request.url),
            headers=dict(request.headers),
            data=body,
        )

        # SigV4署名を追加
        SigV4Auth(self.credentials, self.service, self.region).add_auth(aws_request)

        # httpxリクエストのヘッダーを更新
        request.headers.update(aws_request.headers)

        yield request


# 使用例
session = boto3.Session()
credentials = session.get_credentials()

auth = HTTPXSigV4Auth(
    credentials=credentials,
    service="bedrock-agentcore",
    region="us-east-1"
)

# httpxクライアントで使用
client = httpx.Client(auth=auth)
response = client.post(gateway_url, json=payload)
```

この方法は、複数のリクエストで認証を再利用する場合に便利です。

---

## IAMロールとポリシー設定

### Runtime側のIAMロール

AgentCore RuntimeのIAMロールには、以下の権限が必要です：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAgentCoreGateway",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:InvokeGateway",
        "bedrock-agentcore:GetGateway",
        "bedrock-agentcore:ListGateways"
      ],
      "Resource": [
        "arn:aws:bedrock-agentcore:us-east-1:123456789012:gateway/*"
      ]
    }
  ]
}
```

**重要ポイント:**
- `bedrock-agentcore:InvokeGateway`が必須
- リソースARNは適切なGatewayを指定

### Gateway側の設定

GatewayのInbound認証設定：

```hcl
resource "aws_bedrockagentcore_gateway" "main" {
  name              = "my-gateway"
  role_arn          = var.gateway_role_arn
  authorizer_type   = "AWS_IAM"  # ←ここが重要
  protocol_type     = "MCP"
}
```

---

## トラブルシューティング

### 401 Unauthorized エラー

**症状:**
```
httpx.HTTPStatusError: Client error '401 Unauthorized' for url 'https://...'
```

**原因と対策:**

1. **署名が付与されていない**
   - `streamablehttp_client`に`headers`引数を渡していない
   - → SigV4署名付きヘッダーを生成して渡す

2. **IAM権限不足**
   - RuntimeのIAMロールに`bedrock-agentcore:InvokeGateway`権限がない
   - → IAMポリシーを確認・追加

3. **Gatewayの認証設定ミス**
   - `authorizer_type`が`CUSTOM_JWT`になっている
   - → `AWS_IAM`に変更

4. **リージョン不一致**
   - SigV4署名のリージョンとGatewayのリージョンが異なる
   - → 同じリージョンを指定

### 署名の有効期限

AWS SigV4署名には有効期限があります（デフォルト15分）。

**対策:**
- 長時間実行するアプリケーションでは、リクエストごとに署名を再生成
- または、定期的に署名を更新する仕組みを実装

---

## ベストプラクティス

### 1. エラーハンドリング

```python
def web_research(query: str) -> str:
    try:
        # Gateway設定の検証
        if not settings.GATEWAY_URL:
            raise ValueError("GATEWAY_URL not configured")

        # 署名生成
        headers = generate_sigv4_headers(settings.GATEWAY_URL, settings.AWS_REGION)

        # MCPクライアント作成
        mcp_client = MCPClient(
            lambda: streamablehttp_client(settings.GATEWAY_URL, headers=headers)
        )

        with mcp_client:
            tools = mcp_client.list_tools_sync()
            # 処理...

    except httpx.HTTPStatusError as e:
        if e.response.status_code == 401:
            logger.error("Gateway authentication failed. Check IAM permissions.")
        raise
    except Exception as e:
        logger.exception("Gateway invocation failed")
        raise
```

### 2. ログ出力

```python
logger.info("Connecting to Gateway: %s", gateway_id)
logger.debug("Generated SigV4 headers: %s", headers.keys())
logger.info("Retrieved %d tools from Gateway", len(tools))
```

### 3. 環境変数管理

```python
class Settings(BaseSettings):
    AWS_REGION: str = "us-east-1"
    GATEWAY_URL: str = ""
    GATEWAY_ID: str = ""
    GATEWAY_TARGET_PREFIX: str = ""  # ツールフィルタリング用
```

---

## まとめ

### 重要ポイント

1. ✅ **AgentCore Runtime上でもSigV4署名は必須**
   - `streamablehttp_client`だけでは認証されない
   - 明示的に署名付きヘッダーを渡す必要がある

2. ✅ **boto3を活用**
   - RuntimeのIAMロールから自動的に認証情報を取得
   - `SigV4Auth`で簡単に署名を生成

3. ✅ **IAM権限の設定**
   - RuntimeとGatewayの両方で適切な権限設定が必要
   - `bedrock-agentcore:InvokeGateway`は必須

4. ✅ **エラーハンドリング**
   - 401エラーは認証の問題
   - ログ出力で問題箇所を特定

---

## 参考リンク

- [AWS Bedrock AgentCore Gateway Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway.html)
- [AWS Signature Version 4 Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv.html)
- [Invoking MCP servers on AWS AgentCore (kane.mx)](https://kane.mx/posts/2025/invoke-mcp-hosted-on-aws-agentcore/)
- [Strands MCP Tools Documentation](https://strandsagents.com/latest/documentation/docs/user-guide/concepts/tools/mcp-tools/)

---

## 更新履歴

- 2025-11-01: 初版作成（401エラー調査結果に基づく）
