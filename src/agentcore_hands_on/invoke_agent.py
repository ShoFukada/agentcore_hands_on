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
    parser.add_argument("--session-id", help="セッションID(指定しない場合は自動生成)")
    parser.add_argument("--actor-id", help="アクターID(Memory機能で使用)")
    args = parser.parse_args()

    session_id = args.session_id or f"dfmeoagmreaklgmrkleafremoigrmtesogmtrskhmtkrlshmt{uuid.uuid4().hex[:10]}"

    print(f"==> 呼び出し中: {args.prompt}")
    print(f"    Session ID: {session_id}")
    if args.actor_id:
        print(f"    Actor ID: {args.actor_id}")

    # boto3 クライアント
    agent_core_client = boto3.client("bedrock-agentcore", region_name=args.region)

    # ペイロード
    payload_data = {"input": {"prompt": args.prompt}}
    if args.actor_id:
        payload_data["actorId"] = args.actor_id
    payload = json.dumps(payload_data)

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
