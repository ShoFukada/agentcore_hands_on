# AgentCore Gateway & Identity の IAM ポリシー要件

TavilyをAgentCoreと接続するために、Gateway・Identity (Credential Provider) を使用する際に必要なIAMポリシーを列挙します。

## 目次
1. [Agent Runtimeへの追加ポリシー](#1-agent-runtimeへの追加ポリシー)
2. [Gateway IAMロール](#2-gateway-iamロール)
3. [Lambda (Gateway Target) IAMロール](#3-lambda-gateway-target-iamロール)
4. [Identity (Credential Provider) 関連の権限](#4-identity-credential-provider-関連の権限)

---

## 1. Agent Runtimeへの追加ポリシー

Agent RuntimeからGatewayを呼び出すために、以下の権限を**既存のAgent Runtime IAMロールに追加**します。

### 必要なアクション

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAgentCoreGatewayInvoke",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:InvokeGateway",
        "bedrock-agentcore:GetGateway",
        "bedrock-agentcore:ListGateways"
      ],
      "Resource": [
        "arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:gateway/*"
      ]
    },
    {
      "Sid": "BedrockAgentCoreGatewayTargetAccess",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:GetGatewayTarget",
        "bedrock-agentcore:ListGatewayTargets"
      ],
      "Resource": [
        "arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:gateway/*/target/*"
      ]
    }
  ]
}
```

### Terraform実装例

```hcl
# infrastructure/modules/iam/main.tf に追加

# Bedrock AgentCore Gateway permissions
statement {
  sid    = "BedrockAgentCoreGateway"
  effect = "Allow"
  actions = [
    "bedrock-agentcore:InvokeGateway",
    "bedrock-agentcore:GetGateway",
    "bedrock-agentcore:ListGateways",
    "bedrock-agentcore:GetGatewayTarget",
    "bedrock-agentcore:ListGatewayTargets"
  ]
  resources = [
    "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:gateway/*"
  ]
}
```

### 目的
- **InvokeGateway**: Agent実行時にGatewayを呼び出すために必須
- **GetGateway/ListGateways**: Gatewayの設定を読み取るために使用
- **GetGatewayTarget/ListGatewayTargets**: Gateway Targetの詳細を取得

---

## 2. Gateway IAMロール

Gatewayリソース自体が外部サービス（Lambda、API、MCPサーバー等）を呼び出すために使用するIAMロールです。

### 信頼ポリシー (Assume Role Policy)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock-agentcore.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${ACCOUNT_ID}"
        }
      }
    }
  ]
}
```

### 権限ポリシー

Gateway自体に必要な権限は、呼び出すターゲットによって異なります。

#### A. Lambda Targetを呼び出す場合

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaInvoke",
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": [
        "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function/tavily-mcp-*"
      ]
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/bedrock-agentcore/gateway/*"
      ]
    }
  ]
}
```

#### B. Identity (Credential Provider) を使用する場合

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IdentityCredentialAccess",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:GetCredentialProvider",
        "bedrock-agentcore:ListCredentialProviders"
      ],
      "Resource": [
        "arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:credential-provider/*"
      ]
    },
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:bedrock-agentcore/credentials/*"
      ]
    }
  ]
}
```

### Terraform実装例

```hcl
# Gateway IAM Role
data "aws_iam_policy_document" "gateway_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "gateway_permissions" {
  # Lambda invocation for Gateway Targets
  statement {
    sid    = "LambdaInvoke"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:function/tavily-mcp-*"
    ]
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/gateway/*"
    ]
  }

  # Identity (Credential Provider) access
  statement {
    sid    = "IdentityCredentialAccess"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetCredentialProvider",
      "bedrock-agentcore:ListCredentialProviders"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:credential-provider/*"
    ]
  }

  # Secrets Manager for API keys
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:secret:bedrock-agentcore/credentials/*"
    ]
  }
}

resource "aws_iam_role" "gateway" {
  name               = "bedrock-agentcore-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume_role.json
}

resource "aws_iam_role_policy" "gateway" {
  name   = "bedrock-agentcore-gateway-policy"
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.gateway_permissions.json
}
```

### 目的
- **LambdaInvoke**: Gateway TargetとしてLambda関数を呼び出すために必須
- **CloudWatchLogs**: Gatewayの実行ログを記録
- **GetCredentialProvider**: Identityに登録されたAPIキーなどの認証情報を取得
- **SecretsManagerAccess**: APIキーなどのシークレットを安全に取得

---

## 3. Lambda (Gateway Target) IAMロール

Gateway TargetとしてデプロイするLambda関数（例: Tavily MCP Server）に必要なIAMロールです。

### 信頼ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 権限ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/lambda/tavily-mcp-*"
      ]
    },
    {
      "Sid": "SecretsManagerForAPIKey",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:tavily-api-key-*"
      ]
    }
  ]
}
```

### Terraform実装例

```hcl
# Lambda IAM Role for Gateway Target
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_permissions" {
  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/tavily-mcp-*"
    ]
  }

  # Secrets Manager for Tavily API Key
  statement {
    sid    = "SecretsManagerForAPIKey"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:secret:tavily-api-key-*"
    ]
  }
}

resource "aws_iam_role" "lambda_gateway_target" {
  name               = "tavily-mcp-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "lambda_gateway_target" {
  name   = "tavily-mcp-lambda-policy"
  role   = aws_iam_role.lambda_gateway_target.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}
```

### 目的
- **CloudWatchLogs**: Lambda実行ログの記録
- **SecretsManagerForAPIKey**: Tavily APIキーをSecrets Managerから取得（Lambda内で外部API呼び出し時に使用）

---

## 4. Identity (Credential Provider) 関連の権限

Identity（API Key Credential Provider）を使用する場合、追加の権限設定が必要です。

### A. Secrets Managerへのアクセス権限

APIキーをSecrets Managerに保存している場合、以下の権限が必要です。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerReadAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:bedrock-agentcore/credentials/*"
      ]
    }
  ]
}
```

### B. KMS (暗号化キー) へのアクセス権限

Secrets ManagerがKMSで暗号化されている場合、以下の権限も必要です。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "KMSDecryptAccess",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": [
        "arn:aws:kms:${REGION}:${ACCOUNT_ID}:key/${KEY_ID}"
      ],
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "secretsmanager.${REGION}.amazonaws.com"
          ]
        }
      }
    }
  ]
}
```

### Terraform実装例

```hcl
# Secrets Manager用のKMS Key
resource "aws_kms_key" "credentials" {
  description             = "KMS key for AgentCore credentials"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Gateway Role to Decrypt"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.gateway.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "secretsmanager.${data.aws_region.current.id}.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# Tavily API KeyをSecrets Managerに保存
resource "aws_secretsmanager_secret" "tavily_api_key" {
  name       = "bedrock-agentcore/credentials/tavily-api-key"
  kms_key_id = aws_kms_key.credentials.id
}

resource "aws_secretsmanager_secret_version" "tavily_api_key" {
  secret_id     = aws_secretsmanager_secret.tavily_api_key.id
  secret_string = var.tavily_api_key
}
```

---

## まとめ: Gateway & Identity を使った Tavily 接続に必要なIAMロール

以下の4つのIAMロールと権限設定が必要です。

| IAMロール/権限 | 主な目的 | 必須アクション |
|---|---|---|
| **Agent Runtime Role** (追加) | GatewayとGateway Targetの呼び出し | `bedrock-agentcore:InvokeGateway`<br>`bedrock-agentcore:GetGateway`<br>`bedrock-agentcore:GetGatewayTarget` |
| **Gateway IAM Role** | Lambda呼び出し、Identity参照、Secrets Manager読み取り | `lambda:InvokeFunction`<br>`bedrock-agentcore:GetCredentialProvider`<br>`secretsmanager:GetSecretValue` |
| **Lambda (Gateway Target) Role** | Lambda実行、Tavily APIキー取得 | `logs:CreateLogStream`<br>`secretsmanager:GetSecretValue` |
| **Secrets Manager KMS Key** | APIキーの暗号化・復号化 | `kms:Decrypt`<br>`kms:DescribeKey` |

---

## 参考リンク

- [AgentCore IAM公式ドキュメント](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-iam-awsmanpol.html)
- [AgentCore サービス認可リファレンス](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonbedrockagentcore.html)
- [Gateway Architecture (Zenn記事)](https://zenn.dev/aws_japan/articles/1b29bc6b8de3ca)
