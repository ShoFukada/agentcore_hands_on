# AgentCore Gateway の統合プロバイダー設定ガイド

## 概要

Amazon Bedrock AgentCore Gateway では、ターゲットに対する認証方法として**統合プロバイダー（Integration Provider）**を設定できます。コンソール上では選択肢として表示されますが、Terraformでの設定方法について解説します。

## 認証方法（Credential Provider Types）

AgentCore Gateway は以下の3種類の認証タイプをサポートしています：

### 1. GATEWAY_IAM_ROLE

- **用途**: AWS Lambda関数やSmithyモデルベースのターゲット向け
- **説明**: Gatewayの実行ロール（IAMロール）を使用して認証
- **利点**: AWSサービスとのネイティブ統合、追加の認証情報管理が不要

### 2. API_KEY

- **用途**: OpenAPI スキーマやMCPサーバー向け
- **説明**: APIキーベースの認証
- **設定項目**:
  - `provider_arn`: 認証プロバイダーのARN
  - `credential_location`: `HEADER` または `QUERY_PARAMETER`
  - `credential_parameter_name`: APIキーを含むパラメータ名
  - `credential_prefix`: APIキー値に追加するプレフィックス（例: "Bearer"）

### 3. OAUTH

- **用途**: OpenAPIスキーマ向け
- **説明**: OAuth 2.0（2-legged）認証
- **設定項目**:
  - `provider_arn`: OIDCプロバイダーのARN
  - `scopes`: OAuthスコープのリスト
  - `custom_parameters`: カスタムパラメータのマップ

## Terraformでの設定方法

### 基本構造

```hcl
resource "aws_bedrockagentcore_gateway_target" "example" {
  name               = "example-target"
  gateway_identifier = aws_bedrockagentcore_gateway.example.gateway_id
  description        = "Gateway target description"

  # 認証方法の設定
  credential_provider_configuration {
    # 以下のいずれか1つを選択
    # gateway_iam_role {} または api_key {} または oauth {}
  }

  target_configuration {
    # ターゲットの設定
  }
}
```

### 1. IAMロールを使用する場合

```hcl
credential_provider_configuration {
  gateway_iam_role {}
}
```

**注意**: 空のブロックとして定義します。Gatewayに関連付けられたIAMロールが自動的に使用されます。

### 2. APIキーを使用する場合

```hcl
credential_provider_configuration {
  api_key {
    provider_arn              = "arn:aws:iam::123456789012:oidc-provider/example.com"
    credential_location       = "HEADER"
    credential_parameter_name = "X-API-Key"
    credential_prefix         = "Bearer"
  }
}
```

### 3. OAuthを使用する場合

```hcl
credential_provider_configuration {
  oauth {
    provider_arn = "arn:aws:iam::123456789012:oidc-provider/oauth.example.com"
    scopes       = ["read", "write"]
    custom_parameters = {
      "client_type" = "confidential"
      "grant_type"  = "authorization_code"
    }
  }
}
```

## ターゲットタイプ別の認証方法

| ターゲットタイプ | サポートする認証方法 |
|--------------|------------------|
| Lambda関数 | GATEWAY_IAM_ROLE のみ |
| MCPサーバー | なし（No Authorization） または API_KEY |
| OpenAPIスキーマ | OAUTH または API_KEY |
| Smithyスキーマ | GATEWAY_IAM_ROLE のみ |

## コンソール限定：統合プロバイダーテンプレート

AWSコンソールでは、以下の**16種類の統合プロバイダーテンプレート**が利用可能です：

### エンタープライズ＆生産性ツール
- Amazon
- Asana
- Confluence
- Jira
- Microsoft (Exchange, OneDrive, SharePoint, Teams)
- PagerDuty
- Salesforce
- ServiceNow
- Slack
- Smartsheet
- Zoom

### HR＆ビジネスシステム
- BambooHR
- SAP (Bill of Material, Business Partner, Material Stock, Physical Inventory, Product Master)

### 検索＆情報
- Brave Search
- Tavily Search
- Zendesk

### 重要な制約事項

⚠️ **これらの統合プロバイダーテンプレートは、AWSマネジメントコンソールからのみ設定可能です。**

現時点では、以下の方法では利用できません：
- Terraform
- AWS API
- CloudFormation

## Terraformでの実装サンプル

### 完全な例：Lambda関数ターゲット with IAMロール

```hcl
# Gateway用のIAMロール
data "aws_iam_policy_document" "gateway_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway_role" {
  name               = "bedrock-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume.json
}

# Lambda用のIAMロール
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "example-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Lambda関数
resource "aws_lambda_function" "example" {
  filename      = "example.zip"
  function_name = "example-function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
}

# Gateway
resource "aws_bedrockagentcore_gateway" "example" {
  name     = "example-gateway"
  role_arn = aws_iam_role.gateway_role.arn

  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url = "https://accounts.google.com/.well-known/openid-configuration"
    }
  }
}

# Gateway Target
resource "aws_bedrockagentcore_gateway_target" "example" {
  name               = "example-target"
  gateway_identifier = aws_bedrockagentcore_gateway.example.gateway_id
  description        = "Lambda function target for processing requests"

  # IAMロールを使用した認証
  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.example.arn

        tool_schema {
          inline_payload {
            name        = "process_request"
            description = "Process incoming requests"

            input_schema {
              type        = "object"
              description = "Request processing schema"

              property {
                name        = "message"
                type        = "string"
                description = "Message to process"
                required    = true
              }
            }

            output_schema {
              type = "object"

              property {
                name     = "status"
                type     = "string"
                required = true
              }

              property {
                name = "result"
                type = "string"
              }
            }
          }
        }
      }
    }
  }
}
```

## まとめ

### コンソールで選択できる「統合プロバイダー」について

コンソールで表示される統合プロバイダーは、以下の2つの概念が混在しています：

1. **認証方法（Credential Provider Type）**
   - GATEWAY_IAM_ROLE
   - API_KEY
   - OAUTH
   - ✅ **Terraformで設定可能**

2. **統合プロバイダーテンプレート**
   - Asana、Slack、Salesforce など16種類
   - ❌ **Terraformでは設定不可（コンソールのみ）**

### Terraformでの設定方針

1. **認証方法は `credential_provider_configuration` ブロックで設定**
2. **ターゲットタイプに応じた適切な認証方法を選択**
3. **統合プロバイダーテンプレートが必要な場合は、コンソールで手動設定**

## コンソールテンプレートをTerraformで再現する

コンソールで提供されている統合プロバイダーテンプレートは、OpenAPIスキーマを使用してTerraformで同等の設定を再現できます。

### 前提条件

1. **API Key Credential Providerの作成**（API Key認証を使用する場合）
   - AWS CLIまたはコンソールで事前に作成
   - 作成したCredential ProviderのARNを使用

2. **Gateway の作成**
   - 統合プロバイダーターゲットを追加するGatewayが必要

### Tavily Search の Terraform 設定例

Tavilyは検索APIを提供するサービスで、AgentCore Gatewayから利用できます。

```hcl
# Tavily API Key Credential Provider（事前にAWS CLIで作成）
# aws bedrock-agentcore-control create-api-key-credential-provider \
#   --name tavily-api-key \
#   --api-key "tvly-YOUR_API_KEY" \
#   --description "Tavily search API integration"

# Tavily用のOpenAPIスキーマ定義
locals {
  tavily_openapi_schema = jsonencode({
    openapi = "3.0.0"
    info = {
      title       = "Tavily Search API"
      description = "Tavily search and extract API"
      version     = "1.0.0"
    }
    servers = [
      {
        url = "https://api.tavily.com"
      }
    ]
    paths = {
      "/search" = {
        post = {
          operationId = "TavilySearchPost"
          summary     = "Execute search queries"
          description = "Search the web using Tavily API"
          requestBody = {
            required = true
            content = {
              "application/json" = {
                schema = {
                  type = "object"
                  required = ["query"]
                  properties = {
                    query = {
                      type        = "string"
                      description = "Search query"
                    }
                    search_depth = {
                      type        = "string"
                      description = "Search depth: basic or advanced"
                      enum        = ["basic", "advanced"]
                      default     = "basic"
                    }
                    max_results = {
                      type        = "integer"
                      description = "Maximum number of results"
                      default     = 5
                      minimum     = 0
                      maximum     = 20
                    }
                    include_answer = {
                      type        = "boolean"
                      description = "Include AI-generated answer"
                      default     = false
                    }
                    include_raw_content = {
                      type        = "boolean"
                      description = "Include raw HTML content"
                      default     = false
                    }
                    include_images = {
                      type        = "boolean"
                      description = "Include image search results"
                      default     = false
                    }
                  }
                }
              }
            }
          }
          responses = {
            "200" = {
              description = "Successful search response"
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      query = {
                        type = "string"
                      }
                      results = {
                        type = "array"
                        items = {
                          type = "object"
                          properties = {
                            title   = { type = "string" }
                            url     = { type = "string" }
                            content = { type = "string" }
                            score   = { type = "number" }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          security = [
            {
              ApiKeyAuth = []
            }
          ]
        }
      }
      "/extract" = {
        post = {
          operationId = "TavilySearchExtract"
          summary     = "Extract webpage content"
          description = "Extract content from URLs"
          requestBody = {
            required = true
            content = {
              "application/json" = {
                schema = {
                  type = "object"
                  required = ["urls"]
                  properties = {
                    urls = {
                      type        = "array"
                      description = "URLs to extract content from"
                      items = {
                        type = "string"
                      }
                    }
                    include_images = {
                      type        = "boolean"
                      description = "Include images from the pages"
                      default     = false
                    }
                  }
                }
              }
            }
          }
          responses = {
            "200" = {
              description = "Successful extraction"
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      results = {
                        type = "array"
                        items = {
                          type = "object"
                          properties = {
                            url         = { type = "string" }
                            raw_content = { type = "string" }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          security = [
            {
              ApiKeyAuth = []
            }
          ]
        }
      }
    }
    components = {
      securitySchemes = {
        ApiKeyAuth = {
          type = "apiKey"
          in   = "header"
          name = "Authorization"
        }
      }
    }
  })
}

# Tavily Gateway Target
resource "aws_bedrockagentcore_gateway_target" "tavily" {
  name               = "tavily-search"
  gateway_identifier = aws_bedrockagentcore_gateway.example.gateway_id
  description        = "Tavily search and extract API integration"

  # API Key認証の設定
  credential_provider_configuration {
    api_key {
      provider_arn              = "arn:aws:bedrock-agentcore:us-east-1:123456789012:credential-provider/tavily-api-key"
      credential_location       = "HEADER"
      credential_parameter_name = "Authorization"
      credential_prefix         = "Bearer "
    }
  }

  # OpenAPIスキーマを使用したターゲット設定
  target_configuration {
    mcp {
      open_api_schema {
        inline_payload {
          payload = local.tavily_openapi_schema
        }
      }
    }
  }
}
```

### Slack Web API の Terraform 設定例

SlackのWeb APIをAgentCore Gateway経由で利用する設定です。

```hcl
# Slack API Key Credential Provider（事前にAWS CLIで作成）
# aws bedrock-agentcore-control create-api-key-credential-provider \
#   --name slack-bot-token \
#   --api-key "xoxb-YOUR-SLACK-BOT-TOKEN" \
#   --description "Slack bot token for API access"

# Slack用のOpenAPIスキーマ定義（主要なAPIのみ抜粋）
locals {
  slack_openapi_schema = jsonencode({
    openapi = "3.0.0"
    info = {
      title       = "Slack Web API"
      description = "Slack Web API integration"
      version     = "1.0.0"
    }
    servers = [
      {
        url = "https://slack.com/api"
      }
    ]
    paths = {
      "/chat.postMessage" = {
        post = {
          operationId = "chatPostMessage"
          summary     = "Send a message to a channel"
          description = "Sends a message to a channel"
          requestBody = {
            required = true
            content = {
              "application/json" = {
                schema = {
                  type = "object"
                  required = ["channel", "text"]
                  properties = {
                    channel = {
                      type        = "string"
                      description = "Channel, private group, or IM channel to send message to"
                    }
                    text = {
                      type        = "string"
                      description = "Text of the message to send"
                    }
                    thread_ts = {
                      type        = "string"
                      description = "Provide thread's parent message ts to make this a reply"
                    }
                  }
                }
              }
            }
          }
          responses = {
            "200" = {
              description = "Message sent successfully"
            }
          }
          security = [
            {
              BearerAuth = []
            }
          ]
        }
      }
      "/conversations.list" = {
        get = {
          operationId = "conversationsList"
          summary     = "List conversations"
          description = "Lists all channels in a Slack team"
          parameters = [
            {
              name        = "limit"
              in          = "query"
              description = "Maximum number of items to return"
              schema = {
                type    = "integer"
                default = 100
              }
            },
            {
              name        = "types"
              in          = "query"
              description = "Types of conversations to include"
              schema = {
                type    = "string"
                default = "public_channel"
              }
            }
          ]
          responses = {
            "200" = {
              description = "Conversations list retrieved"
            }
          }
          security = [
            {
              BearerAuth = []
            }
          ]
        }
      }
      "/files.list" = {
        get = {
          operationId = "filesList"
          summary     = "List files"
          description = "List files uploaded to Slack"
          parameters = [
            {
              name        = "channel"
              in          = "query"
              description = "Filter by channel ID"
              schema = {
                type = "string"
              }
            },
            {
              name        = "count"
              in          = "query"
              description = "Number of items to return"
              schema = {
                type    = "integer"
                default = 100
              }
            }
          ]
          responses = {
            "200" = {
              description = "Files list retrieved"
            }
          }
          security = [
            {
              BearerAuth = []
            }
          ]
        }
      }
      "/users.list" = {
        get = {
          operationId = "usersList"
          summary     = "List users"
          description = "Lists all users in a Slack team"
          parameters = [
            {
              name        = "limit"
              in          = "query"
              description = "Maximum number of users to return"
              schema = {
                type    = "integer"
                default = 100
              }
            }
          ]
          responses = {
            "200" = {
              description = "Users list retrieved"
            }
          }
          security = [
            {
              BearerAuth = []
            }
          ]
        }
      }
      "/search.messages" = {
        get = {
          operationId = "searchMessages"
          summary     = "Search messages"
          description = "Searches for messages matching a query"
          parameters = [
            {
              name        = "query"
              in          = "query"
              description = "Search query"
              required    = true
              schema = {
                type = "string"
              }
            },
            {
              name        = "count"
              in          = "query"
              description = "Number of items to return"
              schema = {
                type    = "integer"
                default = 20
              }
            }
          ]
          responses = {
            "200" = {
              description = "Search results retrieved"
            }
          }
          security = [
            {
              BearerAuth = []
            }
          ]
        }
      }
    }
    components = {
      securitySchemes = {
        BearerAuth = {
          type   = "http"
          scheme = "bearer"
        }
      }
    }
  })
}

# Slack Gateway Target
resource "aws_bedrockagentcore_gateway_target" "slack" {
  name               = "slack-web-api"
  gateway_identifier = aws_bedrockagentcore_gateway.example.gateway_id
  description        = "Slack Web API integration"

  # API Key認証の設定（Slack Bot Token）
  credential_provider_configuration {
    api_key {
      provider_arn              = "arn:aws:bedrock-agentcore:us-east-1:123456789012:credential-provider/slack-bot-token"
      credential_location       = "HEADER"
      credential_parameter_name = "Authorization"
      credential_prefix         = "Bearer "
    }
  }

  # OpenAPIスキーマを使用したターゲット設定
  target_configuration {
    mcp {
      open_api_schema {
        inline_payload {
          payload = local.slack_openapi_schema
        }
      }
    }
  }
}
```

### API Key Credential Provider の作成方法

Terraformで直接作成できないため、AWS CLIで事前作成が必要です：

#### Tavily用

```bash
aws bedrock-agentcore-control create-api-key-credential-provider \
  --name tavily-api-key \
  --api-key "tvly-YOUR_TAVILY_API_KEY" \
  --description "Tavily search API integration" \
  --region us-east-1
```

#### Slack用

```bash
aws bedrock-agentcore-control create-api-key-credential-provider \
  --name slack-bot-token \
  --api-key "xoxb-YOUR-SLACK-BOT-TOKEN" \
  --description "Slack bot token for API access" \
  --region us-east-1
```

### 設定の確認

作成したCredential ProviderのARNを確認：

```bash
aws bedrock-agentcore-control list-credential-providers --region us-east-1
```

### 利用可能なAPI一覧の取得

Gateway Targetを作成後、利用可能なツールを確認：

```bash
# Gateway経由でtools/listを呼び出す
# （実際の呼び出し方法は使用するSDKやフレームワークによる）
```

### 注意事項

1. **OpenAPIスキーマの完全性**
   - 上記の例は主要なAPIのみを含んでいます
   - 必要に応じて追加のエンドポイントを定義してください
   - 完全なスキーマは各サービスの公式ドキュメントを参照

2. **認証トークンの管理**
   - APIキーやトークンはSecrets Managerでの管理を推奨
   - 定期的なローテーションを実施

3. **APIの制限**
   - Slack: チャンネルごとに1秒に1メッセージの制限
   - Tavily: プランごとのクレジット制限あり

4. **Credential Providerの管理**
   - Terraformでの管理が不可のため、手動またはスクリプトで管理
   - ARNを`tfvars`ファイルで管理することを推奨

### 変数定義の例

```hcl
# variables.tf
variable "tavily_credential_provider_arn" {
  description = "ARN of Tavily API Key Credential Provider"
  type        = string
}

variable "slack_credential_provider_arn" {
  description = "ARN of Slack Bot Token Credential Provider"
  type        = string
}

# terraform.tfvars
tavily_credential_provider_arn = "arn:aws:bedrock-agentcore:us-east-1:123456789012:credential-provider/tavily-api-key"
slack_credential_provider_arn  = "arn:aws:bedrock-agentcore:us-east-1:123456789012:credential-provider/slack-bot-token"
```

## 参考リンク

- [AWS CloudFormation - GatewayTarget CredentialProviderConfiguration](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-properties-bedrockagentcore-gatewaytarget-credentialproviderconfiguration.html)
- [Amazon Bedrock AgentCore - Setting up Outbound Auth](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-outbound-auth.html)
- [Amazon Bedrock AgentCore - Integration Templates](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-target-integrations.html)
- [Amazon Bedrock AgentCore - Supported APIs by Template](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-target-integrations.html#gateway-target-integrations-supported-apis)
- [Slack API OpenAPI Specs](https://github.com/slackapi/slack-api-specs)
- [Tavily API Documentation](https://docs.tavily.com/)
- [Terraform Issue #43424 - Bedrock AgentCore Support](https://github.com/hashicorp/terraform-provider-aws/issues/43424)
