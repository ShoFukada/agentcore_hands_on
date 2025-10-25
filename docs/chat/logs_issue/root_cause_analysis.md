# AgentCore ログが少ない問題の根本原因分析

## 実行した修正内容

### 1. IAM権限の追加（3段階で実施）

#### Step 1: CloudWatch Logs権限の詳細化
- `logs:DescribeLogGroups` を追加
- ログストリームレベルの明示的なResource指定を追加

**結果:**
- ✅ ログストリーム作成成功: `2025/10/25/[runtime-logs]67a9273b-8ea9-4f21-b065-ca0cb639ab10`
- ✅ 基本的なアプリケーションログ出力開始

#### Step 2: X-Rayサンプリング権限の追加
- `xray:GetSamplingRules` を追加
- `xray:GetSamplingTargets` を追加

**結果:**
- ✅ エラーなく適用完了
- ⚠️ ログサイズに大きな変化なし（144KB）

#### Step 3: Workload Identity権限の追加（最重要）
- `bedrock-agentcore:GetWorkloadAccessToken` を追加
- `bedrock-agentcore:GetWorkloadAccessTokenForJWT` を追加
- `bedrock-agentcore:GetWorkloadAccessTokenForUserId` を追加

**結果:**
- ✅ エージェント正常動作
- ✅ Memory機能正常動作
- ✅ Code Interpreter正常動作
- ⚠️ ログサイズに大きな変化なし（144KB）

## 発見された根本原因

### 問題の症状

エージェント実行時のログを確認すると、以下のエラーが**5秒ごとに繰り返し発生**している：

```
2025-10-25 12:32:24,085 - amazon.opentelemetry.distro.exporter.otlp.aws.logs.otlp_aws_logs_exporter - ERROR - Failed to export logs batch code: 400, reason: 'The specified log group does not exist.
```

### 原因分析

#### 1. 実際のログループ名

AWSに作成されている実際のログループ名：
```
/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT
```

#### 2. 環境変数で指定されているログループ名

**infrastructure/main.tf (Line 127):**
```hcl
OTEL_RESOURCE_ATTRIBUTES = var.agent_runtime_id != "" ?
  "service.name=${var.agent_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id},cloud.resource_id=${var.agent_runtime_id}"
  : "service.name=${var.agent_name}"
```

**terraform.tfvars (Line 10):**
```hcl
agent_runtime_id = "agentcore_hands_on_my_agent_runtime-VNBQgh67mr"
```

**計算されるログループ名:**
```
/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr
```

#### 3. 問題の特定

**❌ 環境変数のログループ名に `-DEFAULT` サフィックスが欠落**

- 実際のログループ: `/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT`
- 環境変数で指定: `/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr`

**差分:** `-DEFAULT` サフィックスがない

### なぜヘルスチェックログは出て、Agent実行の詳細ログは出ないのか

#### 出ているログ
```
2025-10-25 12:31:01 INFO:     Started server process [1]
2025-10-25 12:31:01 INFO:     Waiting for application startup.
2025-10-25 12:31:01 INFO:     Application startup complete.
2025-10-25 12:31:01 INFO:     Uvicorn running on http://0.0.0.0:8080
2025-10-25 12:31:02 2025-10-25 12:31:02,807 - agentcore_hands_on.agent - INFO - ヘルスチェックリクエストを受信
2025-10-25 12:31:02 INFO:     127.0.0.1:36588 - "GET /ping HTTP/1.1" 200 OK
```

これらは**Pythonの標準ロギング（logging.basicConfig）**によって出力されているログ。
- Uvicornのログ
- アプリケーションの基本ログ
- これらはOpenTelemetryを経由せず、直接CloudWatch Logsに書き込まれている

#### 出ていない詳細ログ

- **OpenTelemetryでインスツルメントされたトレースログ**
- **Strands Agentの詳細な実行ログ**
- **ツール呼び出しの詳細ログ**
- **Memory戦略の動作ログ**

これらは**OpenTelemetry経由でエクスポート**されるべきログだが、ログループ名の不一致により失敗している。

### 動作の流れ

```
1. Agent実行
   ↓
2. Python基本ログ → 標準出力 → CloudWatch Logs（成功）
   ↓
3. OpenTelemetry計装ログ → OTLPエクスポーター → 存在しないログループ（失敗）
   ↓
4. ERROR: The specified log group does not exist.
```

## なぜこの問題が発生したか

### `-DEFAULT` サフィックスの由来

AgentCore Runtimeは、実際にデプロイされる際に**自動的に `-DEFAULT` サフィックスを追加**する仕様になっている可能性が高い。

**想定される理由:**
- 複数のエンドポイント/環境をサポートするため
- `DEFAULT` は qualifier（修飾子）として機能
- Runtime作成時は明示されないが、実際のログループ作成時に付与される

### Terraform設定の問題

現在のTerraform設定では、Runtime IDをそのまま使用しているため、`-DEFAULT` サフィックスを考慮していない。

**infrastructure/main.tf:**
```hcl
# ❌ 問題のある設定
OTEL_RESOURCE_ATTRIBUTES = var.agent_runtime_id != "" ?
  "service.name=${var.agent_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id},cloud.resource_id=${var.agent_runtime_id}"
  : "service.name=${var.agent_name}"
```

## medurance_agentとの比較

### medurance_agent のログサイズ
```
19,344,041 bytes (約18.4 MB)
```

### agentcore_hands_on のログサイズ
```
144,600 bytes (約141 KB)
```

**差:** 約130倍

### medurance_agent が正常に動作している理由

おそらく以下のいずれか：
1. `-DEFAULT` サフィックスを環境変数に含めている
2. OpenTelemetryの設定を手動で調整している
3. Runtime作成時の設定が異なる

## 影響範囲

### 現在出力されているログ
- ✅ サーバー起動ログ
- ✅ ヘルスチェックログ
- ✅ HTTPリクエスト基本ログ
- ✅ Python標準ロギングの出力

### 出力されていない（べき）ログ
- ❌ OpenTelemetryトレース詳細
- ❌ Agent実行の詳細フロー
- ❌ Tool呼び出しの詳細
- ❌ Memory戦略の動作詳細
- ❌ Bedrock API呼び出し詳細
- ❌ Code Interpreter/Browser実行詳細
- ❌ エラーハンドリングの詳細

## 修正案

### Option 1: 環境変数に `-DEFAULT` を追加（推奨）

**infrastructure/main.tf:**
```hcl
OTEL_RESOURCE_ATTRIBUTES = var.agent_runtime_id != "" ?
  "service.name=${var.agent_name},aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-DEFAULT,cloud.resource_id=${var.agent_runtime_id}"
  : "service.name=${var.agent_name}"

OTEL_EXPORTER_OTLP_LOGS_HEADERS = var.agent_runtime_id != "" ?
  "x-aws-log-group=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-DEFAULT,x-aws-log-stream=runtime-logs,x-aws-metric-namespace=bedrock-agentcore"
  : "x-aws-metric-namespace=bedrock-agentcore"
```

**変更点:**
- `${var.agent_runtime_id}` → `${var.agent_runtime_id}-DEFAULT`

### Option 2: terraform.tfvars に `-DEFAULT` を含める

**terraform.tfvars:**
```hcl
agent_runtime_id = "agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT"
```

**メリット:**
- main.tfの変更不要
- 明示的でわかりやすい

**デメリット:**
- Runtime IDの命名規則との不一致が発生する可能性

### Option 3: Dynamic lookup で実際のログループ名を取得

**infrastructure/main.tf:**
```hcl
data "aws_cloudwatch_log_group" "runtime_logs" {
  count = var.agent_runtime_id != "" ? 1 : 0
  name  = "/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-DEFAULT"
}

# 環境変数で実際の名前を使用
OTEL_RESOURCE_ATTRIBUTES = var.agent_runtime_id != "" ?
  "service.name=${var.agent_name},aws.log.group.names=${data.aws_cloudwatch_log_group.runtime_logs[0].name},cloud.resource_id=${var.agent_runtime_id}"
  : "service.name=${var.agent_name}"
```

**メリット:**
- 実際のログループ名を動的に取得
- 最も堅牢

**デメリット:**
- 複雑性が増す
- ログループが存在しない場合にエラー

## 推奨される修正手順

### Step 1: `-DEFAULT` サフィックスを追加

**修正ファイル:** `infrastructure/main.tf` (Line 127, 130)

```hcl
# Before:
aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}

# After:
aws.log.group.names=/aws/bedrock-agentcore/runtimes/${var.agent_runtime_id}-DEFAULT
```

### Step 2: Terraform Apply

```bash
cd infrastructure
export AWS_PROFILE=239339588912_AdministratorAccess
terraform plan
terraform apply
```

### Step 3: Agent Runtime を再起動

IAM権限やenv変数の変更は、Runtimeの再デプロイで反映される。

新しいイメージをプッシュするか、Runtimeを強制的に再作成：

```bash
# Option A: 新しいイメージバージョンをプッシュ
./scripts/build_and_push.sh <ecr_url> v1.0.9

# Option B: Terraform で強制再作成
terraform apply -replace=module.agent_runtime.aws_bedrockagentcore_agent_runtime.main
```

### Step 4: ログを確認

```bash
# Agent実行
uv run python -m agentcore_hands_on.invoke_agent \
  --runtime-arn "arn:aws:bedrock-agentcore:us-east-1:239339588912:runtime/agentcore_hands_on_my_agent_runtime-VNBQgh67mr" \
  --prompt "Calculate 5 + 3 using code interpreter"

# ログ確認
aws logs tail "/aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT" \
  --since 2m \
  --format short
```

### Step 5: ログサイズの比較

```bash
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/bedrock-agentcore/runtimes/agentcore_hands_on" \
  --query 'logGroups[*].[logGroupName,storedBytes]' \
  --output table
```

## 期待される結果

修正後、以下が期待される：

### ✅ OpenTelemetryエラーの解消
```
# Before（エラー）:
ERROR - Failed to export logs batch code: 400, reason: 'The specified log group does not exist.

# After（成功）:
（エラーメッセージなし、正常にエクスポート）
```

### ✅ 詳細なトレースログの出力

- Agent実行フロー
- Tool呼び出し詳細
- Memory戦略動作
- Bedrock API呼び出し
- エラーハンドリング

### ✅ ログサイズの増加

```
# Before: 144 KB
# After: 数MB〜数十MB（medurance_agentレベル）
```

### ✅ GenAI Observability での可視化

CloudWatch GenAI Observabilityダッシュボードで、以下が表示される：
- Agent Sessions
- Tool Invocations
- Traces with timing
- Performance metrics

## 補足調査項目

### 1. なぜ `-DEFAULT` サフィックスが付くのか

AWS公式ドキュメントまたはAgentCore Runtime APIのレスポンスを確認：

```bash
aws bedrock-agentcore describe-agent-runtime \
  --agent-runtime-id agentcore_hands_on_my_agent_runtime-VNBQgh67mr \
  --query 'agentRuntime.[agentRuntimeId,agentRuntimeArn]' \
  --output json
```

### 2. medurance_agent の設定確認

medurance_agentの環境変数設定を確認し、どのようにログループ名を指定しているか調査。

### 3. Runtime作成時の動作

Runtime作成時に自動的に作成されるログループの命名規則を確認。

## まとめ

### 根本原因
**OpenTelemetryのログエクスポート先ログループ名に `-DEFAULT` サフィックスが欠落しており、存在しないログループへのエクスポートが繰り返し失敗している。**

### 影響
- 基本的なアプリケーションログは出力される
- OpenTelemetry経由の詳細なトレースログが一切出力されない
- ログサイズが約130分の1に留まる

### 解決策
環境変数 `OTEL_RESOURCE_ATTRIBUTES` と `OTEL_EXPORTER_OTLP_LOGS_HEADERS` のログループ名に `-DEFAULT` サフィックスを追加する。

### 優先度
🔴 **最高優先** - この修正により、ログ出力問題は完全に解決される可能性が極めて高い。
