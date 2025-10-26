# Terraform AWS Provider Bug Report Guide

## 発見したバグ

`aws_bedrockagentcore_gateway` リソースで、`authorizer_type = "AWS_IAM"` を指定した場合、`authorizer_configuration` ブロックが不要であるべきなのに、Terraformプロバイダーが必須としている。

## バグの詳細

### AWS API仕様（正しい動作）

[CreateGateway API](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html)によると：

- `authorizerType`: **Required**
  - `AWS_IAM`: AWS IAM credentialsで認証
  - `CUSTOM_JWT`: Bearer tokenで認証

- `authorizerConfiguration`: **Conditional**
  - `CUSTOM_JWT`を指定した場合のみ必須
  - `AWS_IAM`の場合は不要

### Terraform Provider（バグのある動作）

Terraform AWS Provider (v6.18.0) では：

```hcl
resource "aws_bedrockagentcore_gateway" "main" {
  name            = "example-gateway"
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
  role_arn        = "arn:aws:iam::123456789012:role/gateway-role"

  # AWS_IAMの場合は不要なはずだが、プロバイダーが必須としている
  # authorizer_configuration {}  # これがないとエラー
}
```

**エラーメッセージ:**
```
Error: Invalid Block

Block authorizer_configuration must have a configuration value as the provider has marked it as required
```

さらに、空のブロック `authorizer_configuration {}` を指定すると：

```
Error: creating Bedrock AgentCore Gateway: Incompatible Types

Cause: An unexpected error occurred while expanding configuration. This is
always an error in the provider. Please report the following to the
provider developer:

Expanding
"github.com/hashicorp/terraform-provider-aws/internal/service/bedrockagentcore.authorizerConfigurationModel"
returned nil."
```

## 再現手順

1. Terraform設定を作成:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.18.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "gateway" {
  name = "test-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_bedrockagentcore_gateway" "test" {
  name            = "test-gateway"
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
  role_arn        = aws_iam_role.gateway.arn

  # AWS APIではAWS_IAMの場合にauthorizer_configurationは不要
  # しかしTerraformプロバイダーはこれを必須としている
}
```

2. `terraform validate` または `terraform apply` を実行

3. エラー発生

## 期待される動作

`authorizer_type = "AWS_IAM"` の場合、`authorizer_configuration` ブロックは**オプション**であるべき（または指定不可）。

AWS API仕様と一致するように：
- `AWS_IAM`: `authorizer_configuration` 不要
- `CUSTOM_JWT`: `authorizer_configuration` 必須（`custom_jwt_authorizer`ブロックを含む）

## 回避策

現時点では、AWS CLIでGatewayを作成し、Terraformにimportする方法しかない：

```bash
# AWS CLIでGateway作成
aws bedrock-agentcore-control create-gateway \
  --name "my-gateway" \
  --authorizer-type AWS_IAM \
  --protocol-type MCP \
  --role-arn "arn:aws:iam::123456789012:role/gateway-role" \
  --region us-east-1

# 出力からgateway_idを取得してimport
terraform import aws_bedrockagentcore_gateway.test <gateway_id>
```

## 環境

- Terraform: v1.10.4
- AWS Provider: v6.18.0
- OS: macOS 23.6.0

## GitHub Issue作成方法

### 1. Issue URL

https://github.com/hashicorp/terraform-provider-aws/issues/new/choose

### 2. Issue Type

**Bug Report** を選択

### 3. Issueテンプレート記入例

#### Title
```
[Bug]: aws_bedrockagentcore_gateway requires authorizer_configuration for AWS_IAM authorizer type
```

#### Terraform Core Version
```
1.10.4
```

#### AWS Provider Version
```
6.18.0
```

#### Affected Resource(s)
```
- aws_bedrockagentcore_gateway
```

#### Expected Behavior

```
When `authorizer_type = "AWS_IAM"` is specified, the `authorizer_configuration` block should be optional (or not allowed), as per the AWS API specification.

According to the [CreateGateway API documentation](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html):

- `authorizerConfiguration` is only required when `authorizerType` is `CUSTOM_JWT`
- For `AWS_IAM`, this parameter should not be provided

The resource should accept:

```hcl
resource "aws_bedrockagentcore_gateway" "example" {
  name            = "example-gateway"
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
  role_arn        = aws_iam_role.gateway.arn
  # No authorizer_configuration needed for AWS_IAM
}
```
```

#### Actual Behavior

```
The provider requires `authorizer_configuration` block even when `authorizer_type = "AWS_IAM"`.

Error 1: Without `authorizer_configuration` block:
```
Error: Invalid Block

Block authorizer_configuration must have a configuration value as the provider has marked it as required
```

Error 2: With empty `authorizer_configuration {}` block:
```
Error: creating Bedrock AgentCore Gateway: Incompatible Types

Cause: An unexpected error occurred while expanding configuration. This is
always an error in the provider.

Expanding
"github.com/hashicorp/terraform-provider-aws/internal/service/bedrockagentcore.authorizerConfigurationModel"
returned nil."
```
```

#### Relevant Error/Panic Output Snippet

```terraform
# Paste the error output here
```

#### Terraform Configuration Files

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.18.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "gateway" {
  name = "test-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_bedrockagentcore_gateway" "test" {
  name            = "test-gateway"
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
  role_arn        = aws_iam_role.gateway.arn
}
```

#### Steps to Reproduce

```
1. Create the Terraform configuration above
2. Run `terraform validate` or `terraform apply`
3. Observe the error
```

#### Debug Output

```
(Optional: terraform plan output with TF_LOG=DEBUG)
```

#### Panic Output

```
N/A
```

#### Important Factoids

```
This appears to be a discrepancy between the AWS API specification and the Terraform provider schema definition.

The provider's schema marks `authorizer_configuration` as required:
- Location: `internal/service/bedrockagentcore`
- The block should be conditionally required based on `authorizer_type`
```

#### References

```
- AWS API Documentation: https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html
- Related feature request: #43424 (Bedrock AgentCore Support - now implemented in v6.18.0)
```

#### Would you like to implement a fix?

```
No / Yes (select as appropriate)
```

## 提出前チェックリスト

- [ ] Issueが重複していないか検索で確認
- [ ] タイトルが明確で具体的
- [ ] 再現手順が明確
- [ ] AWS API仕様へのリンクを含む
- [ ] エラーメッセージの全文を含む
- [ ] Terraform/Providerバージョンを明記
- [ ] 最小限の再現可能な設定を提供

## 参考リンク

- [Terraform AWS Provider Issues](https://github.com/hashicorp/terraform-provider-aws/issues)
- [Contributing Guide](https://github.com/hashicorp/terraform-provider-aws/blob/main/docs/contributing)
- [AWS Bedrock AgentCore API Reference](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/Welcome.html)
