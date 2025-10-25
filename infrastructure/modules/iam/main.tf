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

  # CloudWatch Logs permissions (including Observability)
  # Split into 3 statements following AWS official recommendation

  # Log Group level operations
  statement {
    sid    = "CloudWatchLogsGroup"
    effect = "Allow"
    actions = [
      "logs:DescribeLogStreams",
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"
    ]
  }

  # Describe all log groups (required for OpenTelemetry)
  statement {
    sid    = "CloudWatchLogsDescribeGroups"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"
    ]
  }

  # Log Stream level operations
  statement {
    sid    = "CloudWatchLogsStream"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"
    ]
  }

  # X-Ray permissions for Observability
  statement {
    sid    = "XRayAccess"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets"
    ]
    resources = ["*"]
  }

  # CloudWatch Metrics for Observability
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["bedrock-agentcore"]
    }
  }

  # Workload Identity Token permissions (required for observability)
  statement {
    sid    = "GetAgentAccessToken"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetWorkloadAccessToken",
      "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
      "bedrock-agentcore:GetWorkloadAccessTokenForUserId"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/*"
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

  # Bedrock AgentCore Code Interpreter permissions
  statement {
    sid    = "BedrockAgentCoreCodeInterpreter"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:StartCodeInterpreterSession",
      "bedrock-agentcore:StopCodeInterpreterSession",
      "bedrock-agentcore:InvokeCodeInterpreter"
    ]
    resources = ["*"]
  }

  # Bedrock AgentCore Browser permissions (minimal set for runtime usage)
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

  # Bedrock AgentCore Memory permissions (standard set for runtime usage)
  statement {
    sid    = "BedrockAgentCoreMemory"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetMemory",
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:GetEvent",
      "bedrock-agentcore:ListEvents",
      "bedrock-agentcore:RetrieveMemoryRecords",
      "bedrock-agentcore:GetMemoryRecord",
      "bedrock-agentcore:ListMemoryRecords",
      "bedrock-agentcore:BatchCreateMemoryRecords",
      "bedrock-agentcore:ListActors",
      "bedrock-agentcore:ListSessions"
    ]
    resources = ["*"]
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

# Code Interpreter IAM Role
data "aws_iam_policy_document" "code_interpreter_assume_role" {
  count = var.create_code_interpreter_role ? 1 : 0

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

data "aws_iam_policy_document" "code_interpreter_permissions" {
  count = var.create_code_interpreter_role ? 1 : 0

  # CloudWatch Logs permissions for code interpreter execution logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/code-interpreter/*"
    ]
  }

  # S3 permissions for file processing
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::*"
    ]
  }

  # S3 List Buckets permission
  statement {
    sid    = "S3ListBuckets"
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "code_interpreter" {
  count = var.create_code_interpreter_role ? 1 : 0

  name               = var.code_interpreter_role_name
  assume_role_policy = data.aws_iam_policy_document.code_interpreter_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy" "code_interpreter" {
  count = var.create_code_interpreter_role ? 1 : 0

  name   = var.code_interpreter_policy_name
  role   = aws_iam_role.code_interpreter[0].id
  policy = data.aws_iam_policy_document.code_interpreter_permissions[0].json
}

# Browser IAM Role
data "aws_iam_policy_document" "browser_assume_role" {
  count = var.create_browser_role ? 1 : 0

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

data "aws_iam_policy_document" "browser_permissions" {
  count = var.create_browser_role ? 1 : 0

  # CloudWatch Logs permissions for browser execution logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/browser/*"
    ]
  }

  # S3 permissions for browser data storage
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::*"
    ]
  }

  # S3 List Buckets permission
  statement {
    sid    = "S3ListBuckets"
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "browser" {
  count = var.create_browser_role ? 1 : 0

  name               = var.browser_role_name
  assume_role_policy = data.aws_iam_policy_document.browser_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy" "browser" {
  count = var.create_browser_role ? 1 : 0

  name   = var.browser_policy_name
  role   = aws_iam_role.browser[0].id
  policy = data.aws_iam_policy_document.browser_permissions[0].json
}

# Memory Execution IAM Role (for Memory resource to invoke Bedrock models)
data "aws_iam_policy_document" "memory_execution_assume_role" {
  count = var.create_memory_execution_role ? 1 : 0

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

resource "aws_iam_role" "memory_execution" {
  count = var.create_memory_execution_role ? 1 : 0

  name               = var.memory_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.memory_execution_assume_role[0].json

  tags = var.tags
}

# Attach AWS managed policy for Bedrock model inference
resource "aws_iam_role_policy_attachment" "memory_bedrock_inference" {
  count = var.create_memory_execution_role ? 1 : 0

  role       = aws_iam_role.memory_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}
