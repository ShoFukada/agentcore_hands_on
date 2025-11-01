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
    parser.add_argument("--session-id", help="Agent Session ID (オプション、指定しない場合は自動生成)")
    parser.add_argument("--actor-id", help="Actor ID (オプション、指定しない場合は自動生成)")
    args = parser.parse_args()

    # Session IDとActor ID(指定されていない場合は自動生成)
    # Session IDはRuntime呼び出しとAgent内部で同じものを使用
    session_id = args.session_id or f"session-{uuid.uuid4().hex}"
    actor_id = args.actor_id or f"user-{uuid.uuid4().hex}"

    print(f"==> 呼び出し中: {args.prompt}")
    print(f"    Session ID: {session_id}")
    print(f"    Actor ID: {actor_id}")

    # boto3 クライアント
    agent_core_client = boto3.client("bedrock-agentcore", region_name=args.region)

    # ペイロード
    payload = json.dumps(
        {
            "prompt": args.prompt,
            "session_id": session_id,
            "actor_id": actor_id,
        }
    )

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
