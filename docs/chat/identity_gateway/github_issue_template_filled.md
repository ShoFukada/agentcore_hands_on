# GitHub Issue Template (Filled)

**Repository**: https://github.com/hashicorp/terraform-provider-aws/issues/new/choose

---

## Add a title

```
[Bug]: aws_bedrockagentcore_gateway requires authorizer_configuration for AWS_IAM
```

---

## Terraform Version

```
Terraform v1.10.4
on darwin_arm64
+ provider registry.terraform.io/hashicorp/aws v6.18.0
```

---

## Terraform Configuration Files

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

---

## Debug Output

Full debug output with `TF_LOG=trace` can be provided if needed. The key error occurs during validation:

```
Error: Invalid Block

  with aws_bedrockagentcore_gateway.test,
  on main.tf line 28, in resource "aws_bedrockagentcore_gateway" "test":
  28: resource "aws_bedrockagentcore_gateway" "test" {

Block authorizer_configuration must have a configuration value as the
provider has marked it as required
```

When attempting to provide an empty `authorizer_configuration {}` block:

```
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

## Expected Behavior

When `authorizer_type = "AWS_IAM"` is specified, the `authorizer_configuration` block should be **optional** or **not allowed**.

According to the [AWS CreateGateway API documentation](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html):

**authorizerConfiguration** (Conditional):
> "If you specify `CUSTOM_JWT` as the `authorizerType`, you must provide an `authorizerConfiguration`."

This clearly indicates that:
- For `CUSTOM_JWT`: `authorizerConfiguration` is **required**
- For `AWS_IAM`: `authorizerConfiguration` is **not required**

The resource should successfully create with the configuration shown above (without the `authorizer_configuration` block).

AWS CLI successfully creates the gateway without `authorizerConfiguration`:

```bash
aws bedrock-agentcore-control create-gateway \
  --name "test-gateway" \
  --authorizer-type AWS_IAM \
  --protocol-type MCP \
  --role-arn "arn:aws:iam::123456789012:role/test-gateway-role" \
  --region us-east-1

# Successfully creates the gateway
```

---

## Actual Behavior

The Terraform provider marks `authorizer_configuration` as **required** regardless of the `authorizer_type` value.

**Scenario 1**: Without `authorizer_configuration` block
- **Result**: Terraform validation fails
- **Error**: "Block authorizer_configuration must have a configuration value as the provider has marked it as required"

**Scenario 2**: With empty `authorizer_configuration {}` block
- **Result**: Terraform apply fails
- **Error**: "Incompatible Types" - expanding authorizerConfigurationModel returned nil

**Scenario 3**: With `custom_jwt_authorizer` block (incorrect for AWS_IAM)
- **Result**: Would be semantically incorrect and likely fail at AWS API level

---

## Steps to Reproduce

1. Create the Terraform configuration shown above
2. Run `terraform init`
3. Run `terraform validate`
4. Observe the error: "Block authorizer_configuration must have a configuration value as the provider has marked it as required"

Alternative reproduction:

1. Add empty `authorizer_configuration {}` to the config
2. Run `terraform apply`
3. Observe the error: "Incompatible Types - expanding authorizerConfigurationModel returned nil"

---

## Additional Context

### Provider Schema Issue

The provider's schema definition appears to incorrectly mark `authorizer_configuration` as universally required:

```bash
$ terraform providers schema -json | jq '.provider_schemas["registry.terraform.io/hashicorp/aws"].resource_schemas["aws_bedrockagentcore_gateway"].block.block_types.authorizer_configuration'
```

Shows that `authorizer_configuration` is a required block with only `custom_jwt_authorizer` as a sub-block option, with no conditional logic based on `authorizer_type`.

### Expected Schema Behavior

The `authorizer_configuration` block should be:
- **Required** when `authorizer_type = "CUSTOM_JWT"`
- **Optional** or **not allowed** when `authorizer_type = "AWS_IAM"`

This is a common pattern in Terraform providers where certain blocks are conditionally required based on other attribute values.

### Workaround

Currently, the only workaround is to create the gateway using AWS CLI and import it:

```bash
# Create via AWS CLI
aws bedrock-agentcore-control create-gateway \
  --name "my-gateway" \
  --authorizer-type AWS_IAM \
  --protocol-type MCP \
  --role-arn "arn:aws:iam::123456789012:role/gateway-role" \
  --region us-east-1

# Import into Terraform
terraform import aws_bedrockagentcore_gateway.test <gateway_id>
```

### Impact

This bug prevents users from creating AWS_IAM-authorized gateways using Terraform, forcing them to either:
1. Use AWS CLI and import (extra operational complexity)
2. Use CUSTOM_JWT unnecessarily (incorrect authorization model for their use case)
3. Wait for this bug to be fixed

---

## References

- AWS API Documentation: [CreateGateway](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html)
- Related issue: #43424 (Bedrock AgentCore Support - implemented in v6.18.0)
- AWS API Reference showing conditional requirement: [authorizerConfiguration parameter](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CreateGateway.html#bedrock-agentcore-CreateGateway-request-authorizerConfiguration)

### Similar Issues in Other Resources

This is similar to validation issues found in other AWS resources where blocks are conditionally required:
- API Gateway authorizer configurations
- ALB listener rules with different action types

---

## Generative AI / LLM assisted development?

Claude 3.5 Sonnet was used to help identify the discrepancy between AWS API documentation and Terraform provider schema definition.

---

## Additional Technical Details

### Environment
- **OS**: macOS 23.6.0 (Darwin)
- **Terraform**: v1.10.4
- **AWS Provider**: v6.18.0
- **AWS Region**: us-east-1
- **AWS Account**: Verified with AdministratorAccess permissions

### Related Code Location (for maintainers)

The issue likely originates in:
- `internal/service/bedrockagentcore/gateway.go`
- Schema definition for `authorizer_configuration` block
- Validation/expansion logic for `authorizerConfigurationModel`

### Suggested Fix

The schema definition should use `ConflictsWith` or custom validation to ensure:

```go
"authorizer_configuration": {
    Type:     schema.TypeList,
    Optional: true, // Changed from Required
    MaxItems: 1,
    // Add validation: required only when authorizer_type = "CUSTOM_JWT"
    ValidateDiagFunc: func(v interface{}, path cty.Path) diag.Diagnostics {
        // Logic to validate based on authorizer_type
    },
    Elem: &schema.Resource{
        Schema: map[string]*schema.Schema{
            "custom_jwt_authorizer": { ... }
        },
    },
}
```

Or use `ExactlyOneOf` / `RequiredWith` validation patterns that check `authorizer_type` value.

---

**Note**: I'm happy to provide additional debug output, test cases, or assist with PR development if needed.
