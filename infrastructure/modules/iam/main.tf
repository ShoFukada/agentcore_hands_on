# Get current AWS account and region info
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Agent Runtime IAM Role
data "aws_iam_policy_document" "agent_runtime_assume_role" {
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

data "aws_iam_policy_document" "agent_runtime_permissions" {
  # ECR permissions
  statement {
    sid    = "ECRAuthToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRImageAccess"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability"
    ]
    resources = var.ecr_repository_arns
  }

  # CloudWatch Logs permissions
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*"
    ]
  }

  # Bedrock model invocation permissions
  dynamic "statement" {
    for_each = var.enable_bedrock_invoke ? [1] : []
    content {
      sid    = "BedrockInvoke"
      effect = "Allow"
      actions = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      resources = var.bedrock_model_arns
    }
  }

  # Additional custom policy statements
  dynamic "statement" {
    for_each = var.additional_policy_statements
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role" "agent_runtime" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.agent_runtime_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy" "agent_runtime" {
  name   = var.policy_name
  role   = aws_iam_role.agent_runtime.id
  policy = data.aws_iam_policy_document.agent_runtime_permissions.json
}
