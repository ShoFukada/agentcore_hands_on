# AgentCore CloudWatch Logs配信設定ガイド

## 📋 概要

このディレクトリには、AWS Bedrock AgentCoreの各リソース（Gateway、Memory、Code Interpreter、Browser）にCloudWatch Logsのログ配信を設定する方法についてのドキュメントが含まれています。

## 📁 ファイル構成

| ファイル | 説明 |
|---------|------|
| [`agentcore_cloudwatch_logs_configuration.md`](./agentcore_cloudwatch_logs_configuration.md) | 調査結果の詳細、AWS公式の機能説明、実装パターン |
| [`terraform_examples.md`](./terraform_examples.md) | 実装に使える完全なTerraform設定例とモジュール例 |
| `README.md` | このファイル（クイックリファレンス） |

## ✅ 調査結果サマリー

### すべてのリソースでCloudWatch Logs配信が可能

| リソース | 対応状況 | ログタイプ |
|---------|---------|-----------|
| Gateway | ✅ 可能 | APPLICATION_LOGS |
| Memory | ✅ 可能 | APPLICATION_LOGS |
| Code Interpreter | ✅ 可能 | APPLICATION_LOGS |
| Browser | ✅ 可能 | APPLICATION_LOGS |

### 設定方法

**AWSコンソール:**
- リソースの詳細ページ → 「ログ配信」セクション → 「追加」で設定可能

**Terraform:**
- `aws_cloudwatch_log_delivery_source`
- `aws_cloudwatch_log_delivery_destination`
- `aws_cloudwatch_log_delivery`

の3つのリソースを組み合わせて設定

## 🚀 クイックスタート

### 1. 基本的なパターン（Gateway の例）

```hcl
# ログ配信ソース
resource "aws_cloudwatch_log_delivery_source" "gateway" {
  name         = "bedrock-agentcore-gateway-${aws_bedrockagentcore_gateway.example.gateway_id}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_gateway.example.gateway_arn
}

# ロググループ
resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/${aws_bedrockagentcore_gateway.example.gateway_id}"
  retention_in_days = 7
}

# リソースポリシー（delivery.logs.amazonaws.comにログ書き込み権限を付与）
resource "aws_cloudwatch_log_resource_policy" "gateway" {
  policy_name = "gateway-log-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.gateway.arn}:log-stream:*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike = { "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

# ログ配信先
resource "aws_cloudwatch_log_delivery_destination" "gateway" {
  name = "gateway-cloudwatch"
  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.gateway.arn
  }
  depends_on = [aws_cloudwatch_log_resource_policy.gateway]
}

# ログ配信（ソースと配信先のリンク）
resource "aws_cloudwatch_log_delivery" "gateway" {
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway.arn
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway.name
}
```

### 2. モジュール化した例

より詳細な実装例は [`terraform_examples.md`](./terraform_examples.md) の「5. まとめて設定するモジュール例」を参照してください。

## 📊 各リソースで記録される情報

### Gateway
- リクエストライフサイクル（開始と完了）
- Target設定のエラー
- 認証エラー
- パラメータ検証エラー
- ツール呼び出し情報（ツール名、ターゲットID）

### Memory
- イベント作成とリトリーブ
- 長期記憶戦略の実行ログ
- エラーと例外

### Code Interpreter
- Pythonコード実行ログ
- 実行エラーと例外
- ファイル処理情報

### Browser
- Webブラウジングアクティビティ
- ナビゲーションとページロードイベント
- エラーとタイムアウト

## 💡 重要なポイント

### ロググループ名の規則

```
/aws/vendedlogs/bedrock-agentcore/{resource-type}/APPLICATION_LOGS/{resource-id}
```

- `{resource-type}`: `gateway`, `memory`, `code-interpreter`, `browser`
- `{resource-id}`: 各リソースの一意なID

### 必須のIAMポリシー

`delivery.logs.amazonaws.com` サービスに以下の権限が必要：
- `logs:CreateLogStream`
- `logs:PutLogEvents`

### リソース作成順序

1. AgentCoreリソース本体を作成
2. ログ配信設定を追加

依存関係を明示的に設定してください。

## 🔍 既知の問題

### Memoryのログ出力

一部のユーザーレポートによると、Memory リソースの場合、ログ配信設定を行っても実際にログが出力されないケースがあるようです。

一方、Gatewayのログ配信は正常に動作することが確認されています。

## 📚 参考リソース

### AWS公式ドキュメント
- [Enable observability for AgentCore resources](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-configure.html)

### コミュニティ記事
- [AgentCore Gateway Observability](https://dev.to/aws-heroes/amazon-bedrock-agentcore-gateway-part-4-agentcore-gateway-observability-2775)
- [AgentCore Memory Observability](https://dev.to/aws-heroes/amazon-bedrock-agentcore-runtime-part-8-agentcore-memory-observability-32pc)

### Terraform関連
- [Bedrock Knowledge Basesのログ配信Terraform例](https://blog.avangards.io/enabling-logging-for-amazon-bedrock-knowledge-bases-using-terraform)

## 🛠️ トラブルシューティング

### ログが出力されない場合

```bash
# リソースポリシーの確認
aws logs describe-resource-policies

# ログ配信の状態確認
aws logs describe-deliveries

# ログ配信ソースの確認
aws logs describe-delivery-sources

# ログ配信先の確認
aws logs describe-delivery-destinations
```

### よくあるエラー

1. **リソースポリシーの権限不足**
   - `delivery.logs.amazonaws.com`に適切な権限が付与されているか確認

2. **ロググループ名の不一致**
   - `/aws/vendedlogs/`で始まっているか確認
   - リソースタイプとIDが正しいか確認

3. **依存関係の問題**
   - `depends_on`を使用して適切な順序で作成されるよう設定

## 📝 次のステップ

1. [`agentcore_cloudwatch_logs_configuration.md`](./agentcore_cloudwatch_logs_configuration.md) で詳細な調査結果を確認
2. [`terraform_examples.md`](./terraform_examples.md) で実装例を参照
3. プロジェクトに合わせてTerraform設定を調整
4. `terraform plan` で変更内容を確認
5. `terraform apply` でデプロイ

## 📞 お問い合わせ

質問や問題がある場合は、プロジェクトのIssueトラッカーまたはAWS Supportにお問い合わせください。
