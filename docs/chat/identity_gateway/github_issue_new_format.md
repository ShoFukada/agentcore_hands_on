# GitHub Issue - New Format

**Repository**: https://github.com/hashicorp/terraform-provider-aws/issues/new/choose
**Type**: Bug Report

---

## Add a title

```
[Bug]: aws_bedrockagentcore_gateway requires authorizer_configuration for AWS_IAM
```

---

## Terraform and AWS Provider Version

```
Terraform v1.10.4
on darwin_arm64
+ provider registry.terraform.io/hashicorp/aws v6.18.0
```

---

## Affected Resource(s) or Data Source(s)

```
* aws_bedrockagentcore_gateway
```

---

## Expected Behavior

When `authorizer_type = "AWS_IAM"` is specified, the `authorizer_configuration` block should be optional or not required.

According to the [AWS CreateGateway API documentation](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html), the `authorizerConfiguration` parameter is only required when `authorizerType` is `CUSTOM_JWT`. For `AWS_IAM`, this parameter should not be provided as AWS IAM credentials are used directly for authorization.

The resource should successfully create without the `authorizer_configuration` block when using AWS_IAM authorization.

---

## Actual Behavior

The Terraform provider marks `authorizer_configuration` as required regardless of the `authorizer_type` value.

When attempting to create a gateway with `authorizer_type = "AWS_IAM"` without the `authorizer_configuration` block, Terraform validation fails. When providing an empty `authorizer_configuration {}` block as a workaround, the apply operation fails with an "Incompatible Types" error.

---

## Relevant Error/Panic Output

```console
Error: Invalid Block

  with aws_bedrockagentcore_gateway.test,
  on main.tf line 28, in resource "aws_bedrockagentcore_gateway" "test":
  28: resource "aws_bedrockagentcore_gateway" "test" {

Block authorizer_configuration must have a configuration value as the
provider has marked it as required
```

When attempting with empty `authorizer_configuration {}`:

```console
Error: creating Bedrock AgentCore Gateway: Incompatible Types

  with aws_bedrockagentcore_gateway.test,
  on main.tf line 28, in resource "aws_bedrockagentcore_gateway" "test":
  28: resource "aws_bedrockagentcore_gateway" "test" {

Cause: An unexpected error occurred while expanding configuration. This is
always an error in the provider. Please report the following to the
provider developer:

Expanding
"github.com/hashicorp/terraform-provider-aws/internal/service/bedrockagentcore.authorizerConfigurationModel"
returned nil.
```

---

## Sample Terraform Configuration

<details open>
<summary>Click to expand configuration</summary>

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

# IAM Role for Gateway
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
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = "123456789012"
        }
      }
    }]
  })
}

# Gateway with AWS_IAM authorizer
resource "aws_bedrockagentcore_gateway" "test" {
  name            = "test-gateway"
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
  role_arn        = aws_iam_role.gateway.arn

  # According to AWS API docs, authorizer_configuration should NOT be
  # required for AWS_IAM, but the provider marks it as required
}
```
</details>

---

## Steps to Reproduce

1. Create the Terraform configuration shown above
2. Run `terraform init`
3. Run `terraform validate` or `terraform plan`
4. Observe the validation error requiring `authorizer_configuration` block

Alternative reproduction with empty block:

1. Add `authorizer_configuration {}` to the configuration
2. Run `terraform apply`
3. Observe the "Incompatible Types" error during resource creation

---

## Debug Logging

<details>
<summary>Click to expand log output (validation error)</summary>

```console
$ terraform validate
╷
│ Error: Invalid Block
│
│   with aws_bedrockagentcore_gateway.test,
│   on main.tf line 28, in resource "aws_bedrockagentcore_gateway" "test":
│   28: resource "aws_bedrockagentcore_gateway" "test" {
│
│ Block authorizer_configuration must have a configuration value as the
│ provider has marked it as required
╵
```
</details>

Full debug output with `TF_LOG=trace` can be provided if needed.

---

## GenAI / LLM Assisted Development

Claude 3.5 Sonnet was used to help identify the discrepancy between AWS API documentation and Terraform provider schema definition.

---

## Important Facts and References

### AWS API Documentation

According to the [CreateGateway API Reference](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html):

**authorizerType** (Required):
- `AWS_IAM`: Authorize with your AWS IAM credentials
- `CUSTOM_JWT`: Authorize with a bearer token

**authorizerConfiguration** (Conditional):
> "If you specify `CUSTOM_JWT` as the `authorizerType`, you must provide an `authorizerConfiguration`."

This clearly indicates that `authorizerConfiguration` is:
- **Required** when `authorizerType = "CUSTOM_JWT"`
- **Not required** when `authorizerType = "AWS_IAM"`

### Verification with AWS CLI

The gateway can be successfully created using AWS CLI without `authorizerConfiguration`:

```bash
aws bedrock-agentcore-control create-gateway \
  --name "test-gateway" \
  --authorizer-type AWS_IAM \
  --protocol-type MCP \
  --role-arn "arn:aws:iam::123456789012:role/test-gateway-role" \
  --region us-east-1
```

This confirms that the AWS API itself does not require `authorizerConfiguration` for AWS_IAM.

### Current Workaround

Users must create the gateway via AWS CLI and import it into Terraform:

```bash
# Create gateway via CLI
aws bedrock-agentcore-control create-gateway \
  --name "my-gateway" \
  --authorizer-type AWS_IAM \
  --protocol-type MCP \
  --role-arn "arn:aws:iam::123456789012:role/gateway-role" \
  --region us-east-1

# Import into Terraform state
terraform import aws_bedrockagentcore_gateway.test <gateway_id>
```

### Provider Schema Issue

The provider schema appears to mark `authorizer_configuration` as universally required:

```bash
$ terraform providers schema -json | \
  jq '.provider_schemas["registry.terraform.io/hashicorp/aws"].resource_schemas["aws_bedrockagentcore_gateway"].block.block_types.authorizer_configuration'
```

Shows no conditional logic based on `authorizer_type` value.

### Related Issues

- #43424 - Bedrock AgentCore Support (implemented in v6.18.0)

### Suggested Fix

The schema definition in `internal/service/bedrockagentcore/gateway.go` should make `authorizer_configuration` optional and add validation to ensure it's only provided when `authorizer_type = "CUSTOM_JWT"`.

Similar patterns exist in other AWS resources where blocks are conditionally required based on other attribute values (e.g., API Gateway authorizer configurations, ALB listener rules).

---

## Would you like to implement a fix?

**No** - I'm reporting this issue for the maintainers to fix. However, I'm happy to provide additional information, test cases, or assist with PR testing if needed.

---

## Additional Notes for Maintainers

**Affected Code Location:**
- `internal/service/bedrockagentcore/gateway.go`
- Schema definition for `authorizer_configuration` block
- Validation/expansion logic for `authorizerConfigurationModel`

**Impact:**
This bug prevents users from creating AWS_IAM-authorized gateways using Terraform, forcing them to use AWS CLI and import, which adds operational complexity and breaks infrastructure-as-code workflows.
