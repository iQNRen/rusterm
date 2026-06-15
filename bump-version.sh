#!/bin/bash
# 自动递增版本号并推送 tag
# 用法: ./bump-version.sh [major|minor|patch]
# 默认: patch

set -e

cd "$(dirname "$0")"

# 获取当前最新 tag
CURRENT=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
echo "当前版本: $CURRENT"

# 解析版本号
VERSION=${CURRENT#v}
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

# 根据参数递增
case "${1:-patch}" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo "用法: $0 [major|minor|patch]"
        exit 1
        ;;
esac

NEW_VERSION="v${MAJOR}.${MINOR}.${PATCH}"
echo "新版本: $NEW_VERSION"

# 确保所有改动已提交
if [ -n "$(git status --porcelain)" ]; then
    echo "有未提交的改动，请先 commit"
    exit 1
fi

# 创建并推送 tag
git tag "$NEW_VERSION"
git push origin "$NEW_VERSION"
echo "已推送 tag: $NEW_VERSION"
echo "GitHub Actions 正在构建..."
echo "查看进度: https://github.com/iQNRen/rusterm/actions"
