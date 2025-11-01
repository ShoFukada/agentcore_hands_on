# MCP Gateway AWS SigV4 Authentication - Implementation Examples

このドキュメントは、AWS SigV4認証を使ってMCP (Model Context Protocol) Gatewayに接続する実装例をまとめたものです。

## 概要

AWS Bedrock AgentCore GatewayにAWS_IAM認証で接続する場合、リクエストごとにAWS Signature Version 4 (SigV4)で署名する必要があります。

### 問題点

`streamablehttp_client`に事前生成したヘッダーを渡す方法では、以下の理由で認証が失敗します：

1. **SigV4署名はリクエストbodyを含めて計算される**
2. `streamablehttp_client`にヘッダーを渡す時点では、まだリクエストbodyが決まっていない
3. 空のbodyで署名を生成すると、実際のMCPリクエストとは異なる署名になり401エラーになる

### 解決策

**httpx.Auth**インターフェースを実装し、リクエストごとに動的に署名を生成する。

---

## 実装例1: カスタムHTTPXSigV4Authクラス

**ソース**: [How invoking remote MCP servers hosted on AWS AgentCore](https://kane.mx/posts/2025/invoke-mcp-hosted-on-aws-agentcore/)

### HTTPXSigV4Auth実装

```python
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import httpx

class HTTPXSigV4Auth(httpx.Auth):
    """Custom httpx.Auth implementation for AWS SigV4 authentication."""

    def __init__(self, credentials, service: str, region: str):
        """
        Args:
            credentials: boto3 credentials object
            service: AWS service name (e.g., 'bedrock-agentcore')
            region: AWS region (e.g., 'us-east-1')
        """
        self.credentials = credentials
        self.service = service
        self.region = region

    def auth_flow(self, request: httpx.Request):
        """
        Called by httpx for each request to add authentication.

        This method:
        1. Extracts the request body
        2. Creates an AWSRequest with the body included
        3. Signs the request using SigV4Auth
        4. Updates the httpx request headers with signed values
        """
        # Extract request body for signing
        body = request.content if hasattr(request, 'content') else b''

        # Create AWS request for signing (bodyを含める!)
        aws_request = AWSRequest(
            method=request.method,
            url=str(request.url),
            data=body  # ★ 重要: bodyを含めて署名
        )
        aws_request.headers['Host'] = request.url.host

        # Sign the request
        signer = SigV4Auth(self.credentials, self.service, self.region)
        signer.add_auth(aws_request)

        # Update HTTPX request with signed headers
        for name, value in aws_request.headers.items():
            request.headers[name] = value

        yield request
```

### 使用例: SigV4AgentCoreMCPClient

```python
import boto3
from mcp.client.session import ClientSession
from mcp.client.stdio import streamablehttp_client

class SigV4AgentCoreMCPClient:
    """MCP client with AWS SigV4 authentication for AgentCore."""

    def __init__(self, agent_arn: str, region: str = "us-west-2"):
        self.agent_arn = agent_arn
        self.region = region
        self.session = boto3.Session()
        self.credentials = self.session.get_credentials()

    def get_mcp_url(self) -> str:
        """Generate MCP endpoint URL from Agent ARN."""
        # ARN needs URL encoding: : -> %3A, / -> %2F
        encoded_arn = self.agent_arn.replace(':', '%3A').replace('/', '%2F')
        return f"https://bedrock-agentcore.{self.region}.amazonaws.com/runtimes/{encoded_arn}/invocations?qualifier=DEFAULT"

    async def connect(self):
        """Connect to MCP server with SigV4 authentication."""
        mcp_url = self.get_mcp_url()

        # Create auth object that will sign each request
        auth = HTTPXSigV4Auth(
            credentials=self.credentials,
            service='bedrock-agentcore',
            region=self.region
        )

        # Pass auth object to streamablehttp_client
        async with streamablehttp_client(url=mcp_url, auth=auth) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                return session

# 使用例
async def main():
    client = SigV4AgentCoreMCPClient(
        agent_arn="arn:aws:bedrock-agentcore:us-west-2:123456789012:runtime/my-server"
    )
    session = await client.connect()
    # session を使ってMCPツールを呼び出す
```

### 重要なポイント

1. **httpx.Authを継承**: `auth_flow`メソッドで各リクエストに署名を追加
2. **bodyを含めて署名**: `AWSRequest(data=body)`でリクエストbodyを含める
3. **streamablehttp_clientに渡す**: `streamablehttp_client(url=mcp_url, auth=auth)`

---

## 実装例2: httpx-auth-awssigv4ライブラリ

**ソース**: [httpx-auth-awssigv4 GitHub](https://github.com/mmuppidi/httpx-auth-awssigv4)

既存のライブラリを使う方法。

### インストール

```bash
pip install httpx-auth-awssigv4
```

### 基本的な使用例

```python
from httpx_auth_awssigv4 import Sigv4Auth
import httpx

# 認証オブジェクトを作成
auth = Sigv4Auth(
    access_key="AWS_ACCESS_KEY_ID",
    secret_key="AWS_SECRET_ACCESS_KEY",
    service="bedrock-agentcore",  # サービス名
    region="us-east-1"
)

# httpxクライアントで使用
response = httpx.post(
    url="https://gateway-url.amazonaws.com/mcp",
    auth=auth,
    json={"method": "initialize", ...}
)
```

### boto3 credentialsを使う例

```python
import boto3
from httpx_auth_awssigv4 import Sigv4Auth

# boto3からcredentialsを取得
credentials = boto3.Session().get_credentials()

auth = Sigv4Auth(
    access_key=credentials.access_key,
    secret_key=credentials.secret_key,
    token=credentials.token,  # 一時credentialsの場合
    service="bedrock-agentcore",
    region="us-east-1"
)
```

---

## 実装例3: httpx-aws-authライブラリ

**ソース**: [httpx-aws-auth PyPI](https://pypi.org/project/httpx-aws-auth/)

より高機能なライブラリ。IAMロール引き受けにも対応。

### インストール

```bash
pip install httpx-aws-auth
```

**要件**: Python >=3.10

### 直接的なAWS認証情報を使う

```python
import httpx
from httpx_aws_auth import AwsSigV4Auth, AwsCredentials

credentials = AwsCredentials(
    access_key='YOUR_ACCESS_KEY',
    secret_key='YOUR_SECRET_KEY'
)

client = httpx.Client(
    auth=AwsSigV4Auth(
        credentials=credentials,
        region='us-east-1',
        service='bedrock-agentcore'
    )
)

response = client.post('https://gateway-url/mcp', json={...})
```

### IAMロール引き受けを使う（同期）

```python
import boto3
from httpx_aws_auth import AwsSigV4AssumeRoleAuth
from datetime import timedelta

session = boto3.Session()

client = httpx.Client(
    auth=AwsSigV4AssumeRoleAuth(
        region='us-east-1',
        role_arn='arn:aws:iam::123456789012:role/YourRole',
        session=session,
        duration=timedelta(hours=1)
    )
)
```

### 非同期版

```python
import httpx
import aioboto3
from httpx_aws_auth import AwsSigV4AssumeRoleAuth

async_session = aioboto3.Session()

async with httpx.AsyncClient(
    auth=AwsSigV4AssumeRoleAuth(
        region='us-east-1',
        role_arn='arn:aws:iam::123456789012:role/YourRole',
        async_session=async_session,
        service='bedrock-agentcore'
    )
) as client:
    response = await client.post('https://gateway-url/mcp', json={...})
```

### 主な機能

- **自動credential更新**: 一時credentialsの有効期限前に自動更新
- **同期/非同期対応**: boto3とaioboto3の両方をサポート
- **ロール引き受け**: IAMロールの引き受けに対応

---

## 比較表

| 実装方法 | メリット | デメリット | おすすめ用途 |
|---------|---------|----------|------------|
| **カスタムHTTPXSigV4Auth** | - 依存ライブラリが少ない<br>- 完全にコントロール可能 | - 自分でメンテナンスが必要 | - 学習目的<br>- 最小限の依存 |
| **httpx-auth-awssigv4** | - シンプルな実装<br>- 軽量 | - 機能が限定的 | - 基本的なSigV4認証のみ |
| **httpx-aws-auth** | - 高機能（ロール引き受け等）<br>- 自動更新対応<br>- 非同期対応 | - 依存が多い | - プロダクション環境<br>- 複雑な認証要件 |

---

## 我々のプロジェクトへの適用

### 現在の問題

```python
# 現在の実装（agent.py）
def generate_sigv4_headers(url: str, region: str) -> dict[str, str]:
    session = boto3.Session()
    credentials = session.get_credentials()
    parsed_url = urlparse(url)

    request = AWSRequest(
        method="POST",
        url=url,
        headers={
            "Host": parsed_url.netloc,
            "Content-Type": "application/json",
        },
        # ★ 問題: bodyが無い！
    )

    SigV4Auth(credentials, "bedrock-agentcore", region).add_auth(request)
    return dict(request.headers)

# web_researchツールでの使用
headers = generate_sigv4_headers(settings.GATEWAY_URL, settings.AWS_REGION)
mcp_client = MCPClient(
    lambda: streamablehttp_client(settings.GATEWAY_URL, headers=headers)
)
```

### 推奨される修正案

**オプション1: カスタムHTTPXSigV4Authを実装**

```python
# agent.pyに追加
class HTTPXSigV4Auth(httpx.Auth):
    def __init__(self, credentials, service: str, region: str):
        self.credentials = credentials
        self.service = service
        self.region = region

    def auth_flow(self, request: httpx.Request):
        body = request.content if hasattr(request, 'content') else b''
        aws_request = AWSRequest(
            method=request.method,
            url=str(request.url),
            data=body  # bodyを含める
        )
        aws_request.headers['Host'] = request.url.host
        SigV4Auth(self.credentials, self.service, self.region).add_auth(aws_request)

        for name, value in aws_request.headers.items():
            request.headers[name] = value
        yield request

# web_researchツールで使用
session = boto3.Session()
credentials = session.get_credentials()
auth = HTTPXSigV4Auth(credentials, "bedrock-agentcore", settings.AWS_REGION)

mcp_client = MCPClient(
    lambda: streamablehttp_client(settings.GATEWAY_URL, auth=auth)
)
```

**オプション2: httpx-aws-authライブラリを使用**

```bash
uv add httpx-aws-auth
```

```python
from httpx_aws_auth import AwsSigV4Auth, AwsCredentials
import boto3

# web_researchツールで使用
session = boto3.Session()
creds = session.get_credentials()

auth = AwsSigV4Auth(
    credentials=AwsCredentials(
        access_key=creds.access_key,
        secret_key=creds.secret_key,
        token=creds.token
    ),
    region=settings.AWS_REGION,
    service='bedrock-agentcore'
)

mcp_client = MCPClient(
    lambda: streamablehttp_client(settings.GATEWAY_URL, auth=auth)
)
```

---

## 参考リンク

1. [How invoking remote MCP servers hosted on AWS AgentCore](https://kane.mx/posts/2025/invoke-mcp-hosted-on-aws-agentcore/) - カスタムHTTPXSigV4Auth実装例
2. [httpx-auth-awssigv4 GitHub](https://github.com/mmuppidi/httpx-auth-awssigv4) - シンプルなライブラリ
3. [httpx-aws-auth PyPI](https://pypi.org/project/httpx-aws-auth/) - 高機能ライブラリ
4. [AWS SigV4 Signing Examples](https://github.com/aws-samples/sigv4-signing-examples) - AWS公式の署名例
5. [Amazon Bedrock AgentCore Gateway Authentication](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-using-auth.html) - 公式ドキュメント

---

## まとめ

AWS SigV4認証でMCP Gatewayに接続するには、**httpx.Authインターフェースを実装し、リクエストごとに動的に署名を生成する**必要があります。

### 重要なポイント

1. ✅ **bodyを含めて署名**: `AWSRequest(data=body)`でリクエストbodyを含める
2. ✅ **httpx.Authを実装**: `auth_flow`メソッドでリクエストごとに署名
3. ✅ **streamablehttp_clientに渡す**: `streamablehttp_client(url, auth=auth_object)`

### 次のステップ

1. カスタムHTTPXSigV4Authクラスを実装、または
2. httpx-aws-authライブラリを導入
3. web_researchツールを更新してAuthオブジェクトを使用
4. ローカルテストで動作確認
5. デプロイしてRuntime環境で確認
