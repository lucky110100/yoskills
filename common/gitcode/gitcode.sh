#!/usr/bin/env bash
# GitCode API CLI - Linux Bash version
# 封装 GitCode OpenAPI (api.gitcode.com/api/v5) 常用接口
# 凭证优先从环境变量 GITCODE_TOKEN 读取，未设置则交互提示输入
set -euo pipefail

API_BASE="${GITCODE_API_BASE:-https://api.gitcode.com/api/v5}"

# ---------- 工具函数 ----------

get_token() {
    local token="${GITCODE_TOKEN:-}"
    if [ -n "${TOKEN_ARG:-}" ]; then token="$TOKEN_ARG"; fi
    if [ -z "$token" ]; then
        if [ -t 0 ] && [ -t 1 ]; then
            read -s -p "GITCODE_TOKEN 未设置，请输入 GitCode 个人访问令牌: " token >&2
            echo >&2
        else
            echo "ERROR: GITCODE_TOKEN 未设置，且当前为非交互环境无法提示输入。请设置环境变量 GITCODE_TOKEN 或使用 --token 参数。" >&2
            exit 1
        fi
    fi
    echo "$token"
}

api_call() {
    local url="$1"
    local token="$2"
    local resp http_code body
    resp=$(curl -sS -w $'\n%{http_code}' \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $token" \
        "$url") || { echo "ERROR: 请求失败: $url" >&2; exit 1; }
    http_code=$(printf '%s' "$resp" | tail -n1)
    body=$(printf '%s' "$resp" | sed '$d')
    if [ "$http_code" -ge 400 ] 2>/dev/null; then
        echo "ERROR: HTTP $http_code: $body" >&2
        exit 1
    fi
    printf '%s' "$body"
}

pretty_json() {
    if [ "$RAW" = "true" ]; then
        cat
    elif command -v jq >/dev/null 2>&1; then
        jq .
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m json.tool
    else
        cat
    fi
}

url_encode() {
    local str="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$str" | jq -sRr @uri
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=''),end='')" "$str"
    else
        printf '%s' "$str"
    fi
}

json_field() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg k "$key" '.[$k] // ""'
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$key',''))"
    else
        echo ""
    fi
}

show_help() {
    cat <<'EOF'
GitCode API CLI (Bash)

Usage: ./gitcode.sh <command> [options]

Commands:
  user                              获取当前认证用户信息（验证令牌）
  repo    -o <owner> -r <repo>      获取仓库详情
  search-repos -q <keyword>         搜索仓库
  issues  -o <owner> -r <repo> [-s state] [-p page] [-n perPage]
                                    列出仓库 issue

Options:
  -o, --owner <owner>      仓库所有者
  -r, --repo <repo>        仓库名称
  -q, --query <keyword>    搜索关键词
  -s, --state <state>      issue 状态: open|closed|all (默认: all)
  -p, --page <n>           页码 (默认: 1)
  -n, --per-page <n>       每页数量 (默认: 50, 最大: 100)
  --token <token>          GitCode 访问令牌 (默认: $GITCODE_TOKEN)
  --base <url>             API 基础地址 (默认: https://api.gitcode.com/api/v5)
  --raw                    输出原始 JSON (不格式化)
  -h, --help               显示帮助
EOF
}

# ---------- 主逻辑 ----------

if [ "$#" -eq 0 ]; then show_help; exit 0; fi

CMD="$1"; shift

TOKEN_ARG=""
RAW="false"
OWNER=""
REPO=""
QUERY=""
STATE="all"
PAGE=1
PER_PAGE=50
ISSUE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -o|--owner)    OWNER="$2"; shift 2 ;;
        -r|--repo)     REPO="$2"; shift 2 ;;
        -q|--query)    QUERY="$2"; shift 2 ;;
        -s|--state)    STATE="$2"; shift 2 ;;
        -p|--page)     PAGE="$2"; shift 2 ;;
        -n|--per-page) PER_PAGE="$2"; shift 2 ;;
        -i|--issue)    ISSUE="$2"; shift 2 ;;
        --token)       TOKEN_ARG="$2"; shift 2 ;;
        --base)        API_BASE="$2"; shift 2 ;;
        --raw)         RAW="true"; shift ;;
        -h|--help)     show_help; exit 0 ;;
        *)             echo "ERROR: 未知参数: $1" >&2; exit 1 ;;
    esac
done

case "$CMD" in
    -h|--help) show_help; exit 0 ;;
    user)
        TOKEN="$(get_token)"
        api_call "$API_BASE/user" "$TOKEN" | pretty_json
        ;;
    repo)
        if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
            echo "ERROR: repo 命令需要 -o <owner> -r <repo>" >&2; exit 1
        fi
        TOKEN="$(get_token)"
        api_call "$API_BASE/repos/$OWNER/$REPO" "$TOKEN" | pretty_json
        ;;
    search-repos)
        if [ -z "$QUERY" ]; then
            echo "ERROR: search-repos 命令需要 -q <keyword>" >&2; exit 1
        fi
        TOKEN="$(get_token)"
        ENCODED="$(url_encode "$QUERY")"
        api_call "$API_BASE/search/repositories?q=$ENCODED" "$TOKEN" | pretty_json
        ;;
    issues)
        if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
            echo "ERROR: issues 命令需要 -o <owner> -r <repo>" >&2; exit 1
        fi
        TOKEN="$(get_token)"
        api_call "$API_BASE/repos/$OWNER/$REPO/issues?state=$STATE&page=$PAGE&per_page=$PER_PAGE" "$TOKEN" | pretty_json
        ;;
    *)
        echo "ERROR: 未知命令: $CMD（可用: user, repo, search-repos, issues）" >&2
        show_help
        exit 1
        ;;
esac
