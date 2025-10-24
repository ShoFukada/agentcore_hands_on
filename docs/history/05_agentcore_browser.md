# Browser実装

## 概要

AgentCore BrowserとPlaywrightを統合し、エージェントがWebページにアクセスして情報を取得できる機能を実装。

## 1. Terraformインフラ構築

### Browserモジュール作成

`infrastructure/modules/browser/`を作成：

- **main.tf**: Browser リソース定義（PUBLICモード）
- **variables.tf**: 名前、説明、実行ロール、ネットワークモードの変数
- **outputs.tf**: ARN、ID、名前を出力

### IAMロール設定

#### Browser専用IAMロール

`infrastructure/modules/iam/main.tf`に追加：

- CloudWatch Logs書き込み権限
- S3フルアクセス（GetObject, PutObject, DeleteObject, ListBucket）

#### Agent Runtime IAMロール権限追加

最小限のBrowser操作権限を追加：

```hcl
statement {
  sid    = "BedrockAgentCoreBrowser"
  effect = "Allow"
  actions = [
    "bedrock-agentcore:StartBrowserSession",
    "bedrock-agentcore:GetBrowserSession",
    "bedrock-agentcore:StopBrowserSession",
    "bedrock-agentcore:UpdateBrowserStream",
    "bedrock-agentcore:ConnectBrowserAutomationStream"
  ]
  resources = ["*"]
}
```

### main.tf更新

#### Browserモジュール追加

```hcl
module "browser" {
  source = "./modules/browser"

  name               = local.browser_name
  description        = "Browser for ${var.agent_name} with web browsing capabilities"
  execution_role_arn = module.iam.browser_role_arn
  network_mode       = "PUBLIC"

  tags = local.common_tags
}
```

#### Agent Runtime環境変数設定

`module.agent_runtime`の`environment_variables`にBrowser IDを追加：

```hcl
environment_variables = {
  # 既存の環境変数
  LOG_LEVEL   = var.log_level
  ENVIRONMENT = var.environment

  # Code Interpreter ID
  CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id

  # Browser ID
  BROWSER_ID = module.browser.browser_id

  # ... その他の環境変数 ...
}
```

### デプロイ

```bash
cd infrastructure

export AWS_PROFILE=239339588912_AdministratorAccess

# 初期化
terraform init -upgrade

# 検証
terraform validate

# 計画確認
terraform plan

# 適用
terraform apply
```

### デプロイされるリソース

- `aws_bedrockagentcore_browser` - PUBLICモードのBrowser
- `aws_iam_role.browser` - 専用IAMロール
- `aws_iam_role_policy.browser` - CloudWatch Logs + S3アクセスポリシー

### デプロイ結果

```
browser_id   = agentcore_hands_on_my_agent_browser-pd1xaee1WZ
browser_arn  = arn:aws:bedrock-agentcore:us-east-1:239339588912:browser-custom/agentcore_hands_on_my_agent_browser-pd1xaee1WZ
browser_name = agentcore_hands_on_my_agent_browser
```

## 2. Agent側の実装

### 依存関係追加

```bash
uv add playwright
```

### 設定の追加

**.env**に追加：
```bash
BROWSER_ID=agentcore_hands_on_my_agent_browser-pd1xaee1WZ
```

**src/agentcore_hands_on/config.py**に追加：
```python
class Settings(BaseSettings):
    # ... 既存の設定 ...
    BROWSER_ID: str = ""
```

### browse_webツール実装

**src/agentcore_hands_on/agent.py**に追加：

```python
from bedrock_agentcore.tools.browser_client import BrowserClient
from playwright.sync_api import sync_playwright

@tool
def browse_web(url: str) -> str:
    """Browse the web and get page information.

    Access a URL and retrieve the page title and text content.
    """
    try:
        # BrowserClientを使用してカスタムBrowserに接続
        client = BrowserClient(region=settings.AWS_REGION)

        # カスタムBrowserでセッション開始
        session_id = client.start(identifier=settings.BROWSER_ID)
        logger.info("Browser session started: %s", session_id)

        try:
            # WebSocket接続情報を取得
            ws_url, headers = client.generate_ws_headers()

            # Playwrightで接続
            with sync_playwright() as playwright:
                browser = playwright.chromium.connect_over_cdp(
                    endpoint_url=ws_url,
                    headers=headers,
                )

                try:
                    page = browser.new_page()
                    logger.info("Navigating to: %s", url)
                    page.goto(url, wait_until="domcontentloaded")

                    # ページ情報を取得
                    title = page.title()
                    text_content = page.inner_text("body")

                    result = {
                        "url": url,
                        "title": title,
                        "content": text_content,
                    }

                    return json.dumps(result, ensure_ascii=False)

                finally:
                    browser.close()

        finally:
            # セッション停止
            client.stop()
            logger.info("Browser session stopped")

    except Exception as e:
        error_msg = f"Browser action failed: {e!s}"
        logger.exception(error_msg)
        return json.dumps({"error": error_msg}, ensure_ascii=False)


# Strands Agent の初期化 (Code Interpreter + Browserツール付き)
agent = Agent(
    model=BedrockModel(
        model_id="global.anthropic.claude-haiku-4-5-20251001-v1:0",
        region_name=settings.AWS_REGION,
    ),
    tools=[execute_python, browse_web],
)
```

### 実装のポイント

1. `BrowserClient`でカスタムBrowser IDを指定
2. `generate_ws_headers()`でWebSocket接続情報を取得
3. PlaywrightのCDP接続で`connect_over_cdp()`を使用
4. ページタイトルとテキストコンテンツを取得
5. 適切なエラーハンドリングとロギング
6. 必ずセッションを停止

## 3. デプロイとテスト

### バージョン更新

`infrastructure/terraform.tfvars`のimage_tagを更新：

```hcl
image_tag = "v1.0.7"
```

### Dockerイメージのビルドとプッシュ

```bash
cd /Users/fukadasho/individual_development/agentcore_hands_on
export AWS_PROFILE=239339588912_AdministratorAccess
./scripts/build_and_push.sh 239339588912.dkr.ecr.us-east-1.amazonaws.com/agentcore-hands-on-my-agent v1.0.7
```

### Terraform Apply

```bash
cd infrastructure
terraform apply
```

### Agent実行テスト

#### テスト1: Example.com

```bash
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "https://example.com にアクセスして、ページのタイトルとコンテンツを教えて" \
  --region us-east-1
```

**実行結果**:
```json
{
  "output": {
    "response": "example.comのページ情報を取得しました：\n\n**ページタイトル：** Example Domain\n\n**ページコンテンツ：**\n- Example Domain\n- This domain is for use in documentation examples without needing permission. Avoid use in operations.\n- Learn more\n"
  }
}
```

#### テスト2: Hacker News

```bash
uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "https://news.ycombinator.com/ にアクセスして、トップの記事タイトルを3つ教えて" \
  --region us-east-1
```

**実行結果**:
```json
{
  "output": {
    "response": "Hacker Newsのトップページから記事を取得しました。トップの3つの記事タイトルは以下です：\n\n1. **Roc Camera** (215ポイント)\n2. **Alaska Airlines' statement on IT outage** (36ポイント)\n3. **Counter-Strike's player economy is in a multi-billion dollar freefall** (139ポイント)\n"
  }
}
```
