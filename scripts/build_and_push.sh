#!/bin/bash
# シンプルなビルド＆プッシュスクリプト

set -e

if [ -z "$1" ]; then
    echo "使い方: ./build_and_push.sh <ECR_REPOSITORY_URL> [TAG]"
    echo "例: ./build_and_push.sh 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-agent latest"
    exit 1
fi

ECR_REPO_URL="$1"
TAG="${2:-latest}"
IMAGE_URI="${ECR_REPO_URL}:${TAG}"
REGION=$(echo "${ECR_REPO_URL}" | cut -d'.' -f4)

# プロジェクトルートへ移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

cd "${PROJECT_ROOT}"

echo "==> ECRにログイン中..."
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ECR_REPO_URL}"

echo "==> ARM64イメージをビルド＆プッシュ中..."
docker buildx build --platform linux/arm64 --tag "${IMAGE_URI}" --push .

echo ""
echo "==> 完了！"
echo "イメージURI: ${IMAGE_URI}"
echo ""
echo "次のステップ:"
echo "  cd ${SCRIPT_DIR}/../infrastructure"
echo "  terraform apply -var=\"container_image_uri=${IMAGE_URI}\""

