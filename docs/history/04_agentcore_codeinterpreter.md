# Code Interpreter実装

## 概要

AgentCore Code Interpreterをサンドボックス環境で実装。安全なPythonコード実行環境を提供し、データ分析やファイル処理が可能。

## 1. Terraformモジュール作成

### Code Interpreterモジュール
`infrastructure/modules/code_interpreter/`を作成：

- **main.tf**: Code Interpreterリソース定義（SANDBOXモード）
- **variables.tf**: 名前、説明、実行ロール、ネットワークモードの変数
- **outputs.tf**: ARN、ID、名前を出力

### IAMロール追加

#### Code Interpreter専用IAMロール
`infrastructure/modules/iam/main.tf`に追加：

- CloudWatch Logs書き込み権限
- S3フルアクセス（GetObject, PutObject, DeleteObject, ListBucket）

#### Agent Runtime IAMロール権限追加
**重要**: Agent Runtimeが Code Interpreterを操作できるように、以下の権限を追加：

```hcl
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
```

## 2. main.tf更新

### Code Interpreterモジュール追加

```hcl
module "code_interpreter" {
  source = "./modules/code_interpreter"

  name               = local.code_interpreter_name
  description        = "Code interpreter for ${var.agent_name} with sandboxed Python execution"
  execution_role_arn = module.iam.code_interpreter_role_arn
  network_mode       = "SANDBOX"

  tags = local.common_tags
}
```

### Agent Runtime環境変数設定

`module.agent_runtime`の`environment_variables`にCode Interpreter IDを追加：

```hcl
environment_variables = {
  # 既存の環境変数
  LOG_LEVEL   = var.log_level
  ENVIRONMENT = var.environment

  # Code Interpreter ID
  CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id

  # ... その他の環境変数 ...
}
```

## 3. デプロイ

### AWS Profileを設定

```bash
export AWS_PROFILE=239339588912_AdministratorAccess
```

### Terraform実行

```bash
cd infrastructure

# 初期化
terraform init -upgrade

# 検証
terraform validate

# 計画確認
terraform plan

# 適用
terraform apply
```

### デプロイされるリソース

- `aws_bedrockagentcore_code_interpreter` - SANDBOXモードのCode Interpreter
- `aws_iam_role.code_interpreter` - 専用IAMロール
- `aws_iam_role_policy.code_interpreter` - CloudWatch Logs + S3アクセスポリシー

## セキュリティ設計

- **SANDBOXモード**: 分離された安全な実行環境
- **最小権限の原則**: CloudWatch LogsとS3のみにアクセス制限
- **専用IAMロール**: Agent Runtimeとは独立した権限管理

## 確認

デプロイ後、以下のOutputsで確認：

```bash
terraform output code_interpreter_id
terraform output code_interpreter_arn
terraform output code_interpreter_role_arn
```

## デプロイ結果

```
code_interpreter_id   = agentcore_hands_on_my_agent_code_interpreter-zuuXJLi5Dj
code_interpreter_arn  = arn:aws:bedrock-agentcore:us-east-1:239339588912:code-interpreter-custom/agentcore_hands_on_my_agent_code_interpreter-zuuXJLi5Dj
code_interpreter_name = agentcore_hands_on_my_agent_code_interpreter
```

## 4. Agent側の実装

### Code Interpreter IDの取得方法

TerraformでデプロイしたCode Interpreter IDは以下の方法で取得できます：

```bash
cd infrastructure
terraform output code_interpreter_id
# 出力: agentcore_hands_on_my_agent_code_interpreter-zuuXJLi5Dj
```

このIDは環境変数`CODE_INTERPRETER_ID`としてAgent Runtimeに自動的に渡されます。

### boto3を使用する理由

**重要**: `bedrock-agentcore` SDKの`code_session`は、AWSがマネージドするデフォルトのCode Interpreter (`aws.codeinterpreter.v1`) のみを使用します。

Terraformで作成したカスタムCode Interpreterを使用するには、`boto3`クライアントを直接使用する必要があります。

**実装方法**:

```python
import boto3

# boto3クライアントを使用してカスタムCode Interpreterと通信
client = boto3.client("bedrock-agentcore", region_name=settings.AWS_REGION)

# セッション開始（カスタムCode Interpreter IDを指定）
session_response = client.start_code_interpreter_session(
    codeInterpreterIdentifier=settings.CODE_INTERPRETER_ID
)
session_id = session_response["sessionId"]

try:
    # コード実行（executeCodeツールを呼び出し）
    invoke_response = client.invoke_code_interpreter(
        codeInterpreterIdentifier=settings.CODE_INTERPRETER_ID,
        sessionId=session_id,
        name="executeCode",
        arguments={
            "code": code,
            "language": "python",
        },
    )

    # レスポンス処理
    for event in invoke_response["stream"]:
        if "result" in event:
            return json.dumps(event["result"], ensure_ascii=False)
        elif "stdout" in event:
            return event["stdout"]

finally:
    # セッション停止
    client.stop_code_interpreter_session(
        codeInterpreterIdentifier=settings.CODE_INTERPRETER_ID,
        sessionId=session_id,
    )
```

**重要な実装ポイント**:

1. `invoke_code_interpreter`には`codeInterpreterIdentifier`も必須
2. `name="executeCode"`でツール名を指定
3. `arguments`でコードと言語を渡す
4. `stop_code_interpreter_session`にも`codeInterpreterIdentifier`が必要

### 依存関係の追加

```bash
uv add boto3
```

### 設定の追加

**.env**に追加：
```bash
CODE_INTERPRETER_ID=agentcore_hands_on_my_agent_code_interpreter-zuuXJLi5Dj
```

**src/agentcore_hands_on/config.py**に追加：
```python
class Settings(BaseSettings):
    # ... 既存の設定 ...
    CODE_INTERPRETER_ID: str = ""
```

## 5. デプロイとテスト

### バージョン更新

`infrastructure/terraform.tfvars`のimage_tagを更新：

```hcl
image_tag = "v1.0.5"
```

### Dockerイメージのビルドとプッシュ

```bash
cd /Users/fukadasho/individual_development/agentcore_hands_on
export AWS_PROFILE=239339588912_AdministratorAccess
./scripts/build_and_push.sh 239339588912.dkr.ecr.us-east-1.amazonaws.com/agentcore-hands-on-my-agent v1.0.5
```

### Terraform Apply

```bash
cd infrastructure
terraform apply
```

### Agent実行テスト

```bash
cd /Users/fukadasho/individual_development/agentcore_hands_on
export AWS_PROFILE=239339588912_AdministratorAccess

uv run python src/agentcore_hands_on/invoke_agent.py \
  --runtime-arn "$(cd infrastructure && terraform output -raw agent_runtime_arn)" \
  --prompt "1から100の和をpythonで計算して教えて" \
  --region us-east-1
```

**実行結果**:
```json
{
  "output": {
    "response": "1から100の和は **5050** です。\n\nこれは以下の公式でも確認できます：\n- **n(n+1)/2 = 100 × 101 / 2 = 5050**\n\nPythonの`sum(range(1, 101))`関数を使用して計算しました。\n"
  },
  "session_id": null
}
```

## トラブルシューティング

### 1. StartCodeInterpreterSessionで404エラー

**症状**:
```
http.status_code: 404
aws.remote.operation: StartCodeInterpreterSession
```

**原因**: Agent Runtime IAMロールに必要な権限がない

**解決方法**:
`infrastructure/modules/iam/main.tf`のAgent Runtime IAMポリシーに以下を追加：

```hcl
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
```

その後、`terraform apply`で再デプロイ。

### 2. Code Interpreter IDが設定されていない

**症状**: Agentがコード実行環境にアクセスできないと応答

**確認方法**:
```bash
cd infrastructure
terraform state show module.agent_runtime.aws_bedrockagentcore_agent_runtime.main | grep CODE_INTERPRETER_ID
```

**解決方法**:
1. Terraform outputから取得: `terraform output code_interpreter_id`
2. `main.tf`の`environment_variables`に追加：
   ```hcl
   CODE_INTERPRETER_ID = module.code_interpreter.code_interpreter_id
   ```
3. `terraform apply`で再デプロイ

### 3. ローカル開発時の設定

**.env**ファイルに追加：
```bash
CODE_INTERPRETER_ID=agentcore_hands_on_my_agent_code_interpreter-zuuXJLi5Dj
```

**取得方法**:
```bash
cd infrastructure
terraform output -raw code_interpreter_id
```

### 4. CloudWatch Logsでデバッグ

```bash
export AWS_PROFILE=239339588912_AdministratorAccess
aws logs tail /aws/bedrock-agentcore/runtimes/agentcore_hands_on_my_agent_runtime-VNBQgh67mr-DEFAULT --since 5m --follow
```
