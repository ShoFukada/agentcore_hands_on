# AgentCore CloudWatch Logs配信設定調査結果

## 概要

AWS Bedrock AgentCoreの各リソース（Gateway、Memory、Code Interpreter、Browser）について、CloudWatch Logsへの配信設定が可能かどうかを調査した結果をまとめます。

## 調査結果サマリー

### AWSコンソール・SDK

すべてのAgentCoreリソースで**CloudWatch Logsへのログ配信が可能**です：

| リソース | CloudWatch Logs対応 | ログタイプ | デフォルトロググループパス |
|---------|-------------------|-----------|------------------------|
| Gateway | ✅ 対応 | APPLICATION_LOGS | `/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/{gateway_id}` |
| Memory | ✅ 対応 | APPLICATION_LOGS | `/aws/vendedlogs/bedrock-agentcore/memory/APPLICATION_LOGS/{memory_id}` |
| Code Interpreter | ✅ 対応 | APPLICATION_LOGS | `/aws/vendedlogs/bedrock-agentcore/code-interpreter/APPLICATION_LOGS/{code_interpreter_id}` |
| Browser | ✅ 対応 | APPLICATION_LOGS | `/aws/vendedlogs/bedrock-agentcore/browser/APPLICATION_LOGS/{browser_id}` |

### Terraform対応状況

**現状の問題点：**
- 既存のTerraform AgentCoreリソースドキュメント（`gateway.md`, `memory.md`, `code_interpreter.md`, `browser.md`）には、CloudWatch Logsの配信設定パラメータが**記載されていません**
- 2025年10月時点のTerraform AWS Provider v6.16.0では、AgentCoreリソースのサポートがまだ完全ではない可能性があります

**回避策：**
- Terraformで設定する場合は、`aws_cloudwatch_log_delivery_source`、`aws_cloudwatch_log_delivery_destination`、`aws_cloudwatch_log_delivery`リソースを使用する必要があります

## 詳細情報

### 1. ログ配信先の種類

AgentCoreリソースは、以下の3種類のログ配信先をサポートしています：

1. **CloudWatch Logs**（デフォルト、Agent Runtimeの場合）
2. **Amazon S3 バケット**
3. **Amazon Data Firehose 配信ストリーム**

### 2. コンソールでの設定方法

各リソースの詳細ページで以下の手順で設定可能です：

1. AgentCoreリソース（Gateway、Memoryなど）を選択
2. 「ログ配信（Log Delivery）」セクションまでスクロール
3. 「追加（Add）」ボタンをクリック
4. 配信先タイプ（CloudWatch Logs、S3、Firehose）を選択
5. ログタイプとして「APPLICATION_LOGS」を選択
6. 配信先のロググループ名を指定（またはデフォルトを使用）
7. オプション設定（フィールド選択、出力形式など）を構成
8. 「追加」をクリックして保存

### 3. 各リソースで記録される情報

#### Gateway
- リクエストライフサイクル（開始と完了）
- Target設定のエラーメッセージ
- 認証に関する問題（欠落または不正な認証ヘッダー）
- パラメータ検証エラー（tools、methodなどの不正なリクエストパラメータ）
- ツール呼び出し情報（ツール名とターゲットID）

**制限事項：** ツール呼び出しの入力パラメータやレスポンスは現在ログに含まれていません。完全な可視性のためには、Lambda関数や公開APIでの補足的なログ記録が必要です。

#### Memory
- イベント作成とリトリーブの情報
- 長期記憶戦略の実行ログ
- エラーと例外情報

#### Code Interpreter
- Pythonコード実行のログ
- 実行エラーと例外
- ファイル処理の情報

#### Browser
- Webブラウジングのアクティビティ
- ナビゲーションとページロードイベント
- エラーとタイムアウト情報

**注：** Browserには追加で`recording`機能があり、ブラウザセッションをS3バケットに記録することも可能です。

### 4. Terraformでの設定方法

Bedrock Knowledge Basesの例を参考に、同様のパターンでAgentCoreリソースのログ配信を設定できます。

#### 基本パターン

```hcl
# 1. ログ配信ソースの作成
resource "aws_cloudwatch_log_delivery_source" "gateway_logs" {
  name         = "bedrock-agentcore-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_gateway.example.gateway_arn
}

# 2. CloudWatch Logsグループの作成
resource "aws_cloudwatch_log_group" "gateway_logs" {
  name              = "/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/${aws_bedrockagentcore_gateway.example.gateway_id}"
  retention_in_days = 7  # 必要に応じて調整
}

# 3. CloudWatch Logsリソースポリシーの作成
resource "aws_cloudwatch_log_resource_policy" "gateway_logs" {
  policy_name = "bedrock-agentcore-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = ["delivery.logs.amazonaws.com"]
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.gateway_logs.arn}:log-stream:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = [data.aws_caller_identity.current.account_id]
        }
        ArnLike = {
          "aws:SourceArn" = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
        }
      }
    }]
  })
}

# 4. ログ配信先の作成
resource "aws_cloudwatch_log_delivery_destination" "gateway_logs" {
  name = "bedrock-agentcore-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}-cloudwatch"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.gateway_logs.arn
  }

  depends_on = [aws_cloudwatch_log_resource_policy.gateway_logs]
}

# 5. ログ配信の作成（ソースと配信先をリンク）
resource "aws_cloudwatch_log_delivery" "gateway_logs" {
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway_logs.arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway_logs.name
}
```

#### 必要なデータソース

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
```

#### 各リソースへの適用

同様のパターンを他のAgentCoreリソースにも適用できます：

##### Memory

```hcl
resource "aws_cloudwatch_log_delivery_source" "memory_logs" {
  name         = "bedrock-agentcore-memory-${aws_bedrockagentcore_memory.example.id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_memory.example.arn
}

resource "aws_cloudwatch_log_group" "memory_logs" {
  name = "/aws/vendedlogs/bedrock-agentcore/memory/APPLICATION_LOGS/${aws_bedrockagentcore_memory.example.id}"
}

# ... 以下同様のパターン
```

##### Code Interpreter

```hcl
resource "aws_cloudwatch_log_delivery_source" "code_interpreter_logs" {
  name         = "bedrock-agentcore-code-interpreter-${aws_bedrockagentcore_code_interpreter.example.code_interpreter_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_code_interpreter.example.code_interpreter_arn
}

resource "aws_cloudwatch_log_group" "code_interpreter_logs" {
  name = "/aws/vendedlogs/bedrock-agentcore/code-interpreter/APPLICATION_LOGS/${aws_bedrockagentcore_code_interpreter.example.code_interpreter_id}"
}

# ... 以下同様のパターン
```

##### Browser

```hcl
resource "aws_cloudwatch_log_delivery_source" "browser_logs" {
  name         = "bedrock-agentcore-browser-${aws_bedrockagentcore_browser.example.browser_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_browser.example.browser_arn
}

resource "aws_cloudwatch_log_group" "browser_logs" {
  name = "/aws/vendedlogs/bedrock-agentcore/browser/APPLICATION_LOGS/${aws_bedrockagentcore_browser.example.browser_id}"
}

# ... 以下同様のパターン
```

### 5. S3への配信例

CloudWatch Logsの代わりにS3バケットにログを配信する場合：

```hcl
# S3バケットの作成
resource "aws_s3_bucket" "gateway_logs" {
  bucket        = "bedrock-agentcore-gateway-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# S3バケットポリシーの作成
resource "aws_s3_bucket_policy" "gateway_logs" {
  bucket = aws_s3_bucket.gateway_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.gateway_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/bedrock/agentcore/gateway/*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          "s3:x-amz-acl"      = "bucket-owner-full-control"
        }
        ArnLike = {
          "aws:SourceArn" = aws_cloudwatch_log_delivery_source.gateway_logs.arn
        }
      }
    }]
  })
}

# ログ配信先の作成（S3用）
resource "aws_cloudwatch_log_delivery_destination" "gateway_logs_s3" {
  name = "bedrock-agentcore-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}-s3"

  delivery_destination_configuration {
    destination_resource_arn = aws_s3_bucket.gateway_logs.arn
  }

  depends_on = [aws_s3_bucket_policy.gateway_logs]
}

# ログ配信の作成
resource "aws_cloudwatch_log_delivery" "gateway_logs_s3" {
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway_logs_s3.arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway_logs.name
}
```

### 6. 複数の配信先を設定する場合の注意点

複数のログ配信先（例：CloudWatch LogsとS3の両方）を設定する場合、**依存関係を明示的に定義**して同時変更の競合を避ける必要があります：

```hcl
resource "aws_cloudwatch_log_delivery" "gateway_logs_cloudwatch" {
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway_logs.arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway_logs.name
}

resource "aws_cloudwatch_log_delivery" "gateway_logs_s3" {
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway_logs_s3.arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway_logs.name

  # CloudWatch Logs配信の後に実行
  depends_on = [aws_cloudwatch_log_delivery.gateway_logs_cloudwatch]
}
```

## オブザーバビリティ機能

### CloudWatch GenAI Observability

AgentCoreは、標準化されたOpenTelemetry（OTEL/ADOT）形式でテレメトリーデータを生成し、Amazon CloudWatch GenAI Observabilityに配信できます。

**有効化の手順：**
1. デフォルトでエージェント設定でオブザーバビリティが有効化されています
2. CloudWatchがADOTデータを受信・処理するには、**X-Ray Transaction Search**をCloudWatch設定で有効化する必要があります
3. AWS CLIを使用してTransaction Searchを設定します

### Tracing

CloudWatchへのトレース配信を有効にすることで、以下が可能になります：
- アプリケーション内のインタラクションフローの追跡
- リクエストの視覚化
- パフォーマンスボトルネックの特定
- エラーのトラブルシューティング
- パフォーマンスの最適化

## 参考リンク

- [AWS公式ドキュメント：Enable observability for AgentCore resources](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-configure.html)
- [DEV Community：AgentCore Gateway Observability](https://dev.to/aws-heroes/amazon-bedrock-agentcore-gateway-part-4-agentcore-gateway-observability-2775)
- [DEV Community：AgentCore Memory Observability](https://dev.to/aws-heroes/amazon-bedrock-agentcore-runtime-part-8-agentcore-memory-observability-32pc)
- [Bedrock Knowledge Basesのログ配信Terraform例](https://blog.avangards.io/enabling-logging-for-amazon-bedrock-knowledge-bases-using-terraform)

## 既知の問題

### Memory のログ配信

一部のユーザーレポートによると、Memoryリソースのログ配信設定を行っても、実際にログストリームが作成されない場合があるようです（数日間の会話後もログが出力されない）。これはユーザー側の設定ミスか、サービス側の未解決の問題である可能性があります。

一方、Gatewayのログ配信は正常に動作することが確認されています。

## まとめ

1. **すべてのAgentCoreリソース（Gateway、Memory、Code Interpreter、Browser）でCloudWatch Logsへのログ配信が可能**
2. **コンソールおよびSDK（Boto3など）を使用して設定可能**
3. **Terraformでは、`aws_cloudwatch_log_delivery_source`、`aws_cloudwatch_log_delivery_destination`、`aws_cloudwatch_log_delivery`リソースを組み合わせて設定**
4. **既存のTerraform AgentCoreリソースドキュメントには、ログ配信パラメータの記載がない**
5. **ログタイプは`APPLICATION_LOGS`を使用**
6. **ログパスは`/aws/vendedlogs/bedrock-agentcore/{resource-type}/APPLICATION_LOGS/{resource-id}`パターンに従う**
