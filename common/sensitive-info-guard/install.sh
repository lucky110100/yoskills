#!/bin/bash
#
# install.sh — 将 sensitive-info-guard pre-commit hook 安装到 Git 仓库或全局
#
# 用法：
#   # 安装到当前仓库
#   cd /path/to/your/repo
#   bash /path/to/sensitive-info-guard/install.sh
#
#   # 全局安装（所有仓库生效）
#   bash /path/to/sensitive-info-guard/install.sh --global
#
# 选项：
#   -f, --force    强制覆盖已有的 pre-commit hook
#   -g, --global   安装到全局 hooks 目录（~/.git-hooks），所有仓库生效
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SOURCE="$SCRIPT_DIR/pre-commit"
FORCE=false
GLOBAL=false

# 解析参数
for arg in "$@"; do
  case "$arg" in
    -f|--force)
      FORCE=true
      ;;
    -g|--global)
      GLOBAL=true
      ;;
    *)
      echo "未知参数: $arg"
      echo "用法: bash install.sh [-f|--force] [-g|--global]"
      exit 1
      ;;
  esac
done

# 检查 hook 源文件是否存在
if [ ! -f "$HOOK_SOURCE" ]; then
  echo "❌ 找不到 pre-commit hook 文件: $HOOK_SOURCE"
  exit 1
fi

if [ "$GLOBAL" = true ]; then
  # ── 全局安装模式 ──
  GLOBAL_HOOKS_DIR="$HOME/.git-hooks"
  TARGET="$GLOBAL_HOOKS_DIR/pre-commit"

  # 检查目标是否已存在
  if [ -f "$TARGET" ] && [ "$FORCE" = false ]; then
    echo "⚠️  已存在全局 pre-commit hook: $TARGET"
    echo "   使用 --force 参数强制覆盖，或手动合并"
    echo ""
    echo "   现有 hook 内容预览："
    head -5 "$TARGET"
    exit 1
  fi

  # 创建全局 hooks 目录
  mkdir -p "$GLOBAL_HOOKS_DIR"

  # 复制 hook 文件
  cp "$HOOK_SOURCE" "$TARGET"
  chmod +x "$TARGET"

  # 设置全局 hooks 路径
  git config --global core.hooksPath "$GLOBAL_HOOKS_DIR"

  echo "✅ sensitive-info-guard pre-commit hook 已全局安装！"
  echo ""
  echo "   Hook 位置: $TARGET"
  echo "   core.hooksPath: $(git config --global core.hooksPath)"
  echo ""
  echo "   📌 所有 Git 仓库的 git commit 都将自动进行敏感信息检查"
  echo ""
  echo "📋 检测规则："
  echo "   - API Key (OpenAI sk-xxx, AWS AKIA, GitHub ghp_/gho_)"
  echo "   - 密码 (password, YAML password:)"
  echo "   - Secret Key / Token / JWT Secret"
  echo "   - Private Key / Bearer Token"
  echo ""
  echo "🔄 卸载全局 hook："
  echo "   git config --global --unset core.hooksPath"
  echo "   rm ~/.git-hooks/pre-commit"
  echo ""
  echo "⏭️  跳过检查（紧急时）："
  echo "   git commit --no-verify"

else
  # ── 单仓库安装模式 ──
  # 检查是否在 Git 仓库中
  if [ ! -d ".git" ]; then
    echo "❌ 当前目录不是 Git 仓库根目录，请在仓库根目录下运行此脚本"
    echo "   或使用 --global 参数进行全局安装"
    exit 1
  fi

  HOOKS_DIR=".git/hooks"
  TARGET="$HOOKS_DIR/pre-commit"

  # 检查目标是否已存在
  if [ -f "$TARGET" ] && [ "$FORCE" = false ]; then
    echo "⚠️  已存在 pre-commit hook: $TARGET"
    echo "   使用 --force 参数强制覆盖，或手动合并"
    echo ""
    echo "   现有 hook 内容预览："
    head -5 "$TARGET"
    exit 1
  fi

  # 创建 hooks 目录（如果不存在）
  mkdir -p "$HOOKS_DIR"

  # 复制 hook 文件
  cp "$HOOK_SOURCE" "$TARGET"
  chmod +x "$TARGET"

  echo "✅ sensitive-info-guard pre-commit hook 已安装到: $TARGET"
  echo ""
  echo "📋 检测规则："
  echo "   - API Key (OpenAI sk-xxx, AWS AKIA, GitHub ghp_/gho_)"
  echo "   - 密码 (password, YAML password:)"
  echo "   - Secret Key / Token / JWT Secret"
  echo "   - Private Key / Bearer Token"
  echo ""
  echo "🧪 测试："
  echo "   bash $TARGET"
  echo ""
  echo "⏭️  跳过检查（紧急时）："
  echo "   git commit --no-verify"
fi
