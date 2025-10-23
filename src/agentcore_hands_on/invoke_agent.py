"""AgentCore Runtime 呼び出しスクリプト"""

import argparse
import json
import uuid

import boto3


def main() -> None:
    parser = argparse.ArgumentParser(description="AgentCore Runtime を呼び出す")
    parser.add_argument("--runtime-arn", required=True, help="Agent Runtime ARN")
    parser.add_argument("--prompt", required=True, help="プロンプト")
    parser.add_argument("--region", default="us-east-1", help="AWS リージョン")
    args = parser.parse_args()

    # セッションID生成(33文字以上必要)
    session_id = f"dfmeoagmreaklgmrkleafremoigrmtesogmtrskhmtkrlshmt{uuid.uuid4().hex[:10]}"

    print(f"==> 呼び出し中: {args.prompt}")
    print(f"    Session ID: {session_id}")

    # boto3 クライアント
    agent_core_client = boto3.client("bedrock-agentcore", region_name=args.region)

    # ペイロード
    payload = json.dumps({"input": {"prompt": args.prompt}})

    # 呼び出し
    response = agent_core_client.invoke_agent_runtime(
        agentRuntimeArn=args.runtime_arn, runtimeSessionId=session_id, payload=payload, qualifier="DEFAULT"
    )

    # レスポンス
    response_body = response["response"].read()
    response_data = json.loads(response_body)

    print("\n==> Agent Response:")
    print(json.dumps(response_data, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
