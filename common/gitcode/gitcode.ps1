#!/usr/bin/env pwsh
# GitCode API CLI - Windows PowerShell version
# 封装 GitCode OpenAPI (api.gitcode.com/api/v5) 常用接口
# 凭证优先从环境变量 GITCODE_TOKEN 读取，未设置则交互提示输入

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = "SilentlyContinue"

$ApiBase = $env:GITCODE_API_BASE
if (-not $ApiBase) { $ApiBase = "https://api.gitcode.com/api/v5" }

# ---------- 工具函数 ----------

function Get-GitCodeToken {
    param([string]$TokenArg)
    $token = $TokenArg
    if (-not $token) { $token = $env:GITCODE_TOKEN }
    if (-not $token) {
        if ([Console]::IsOutputRedirected) {
            Write-Error "GITCODE_TOKEN 未设置，且当前为非交互环境无法提示输入。请设置环境变量 GITCODE_TOKEN 或使用 --token 参数。"
            exit 1
        }
        $token = Read-Host "GITCODE_TOKEN 未设置，请输入 GitCode 个人访问令牌"
    }
    return $token
}

function Invoke-GitCodeApi {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Token)
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers.Add("Accept", "application/json")
    $wc.Headers.Add("Authorization", "Bearer $Token")
    try {
        return $wc.DownloadString($Url)
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp) {
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $body = $sr.ReadToEnd()
            $code = [int]$resp.StatusCode
            Write-Error "HTTP $code : $body"
        } else {
            Write-Error $_.Exception.Message
        }
        exit 1
    }
}

function Format-Output {
    param([string]$Json, [switch]$Raw)
    if ($Raw) { Write-Output $Json; return }
    try {
        $obj = $Json | ConvertFrom-Json
        Write-Output ($obj | ConvertTo-Json -Depth 100)
    } catch {
        Write-Output $Json
    }
}

function Show-Help {
    Write-Output @'
GitCode API CLI (PowerShell)

Usage: .\gitcode.ps1 <command> [options]

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
'@
}

# ---------- 主逻辑 ----------

if ($args.Count -eq 0) { Show-Help; exit 0 }

$cmd = [string]$args[0]
$rest = @()
if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }

$tokenArg = ""
$raw = $false
$owner = ""
$repo = ""
$query = ""
$state = "all"
$page = 1
$perPage = 50

$i = 0
while ($i -lt $rest.Count) {
    $a = [string]$rest[$i]
    if ($a -eq "-o" -or $a -eq "--owner") { $owner = [string]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "-r" -or $a -eq "--repo") { $repo = [string]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "-q" -or $a -eq "--query") { $query = [string]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "-s" -or $a -eq "--state") { $state = [string]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "-p" -or $a -eq "--page") { $page = [int]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "-n" -or $a -eq "--per-page") { $perPage = [int]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "--token") { $tokenArg = [string]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "--base") { $ApiBase = [string]$rest[$i + 1]; $i += 2 }
    elseif ($a -eq "--raw") { $raw = $true; $i += 1 }
    elseif ($a -eq "-h" -or $a -eq "--help") { Show-Help; exit 0 }
    else { Write-Error "未知参数: $a"; exit 1 }
}

if ($cmd -eq "-h" -or $cmd -eq "--help") { Show-Help; exit 0 }

$token = Get-GitCodeToken -TokenArg $tokenArg

switch ($cmd) {
    "user" {
        $url = "$ApiBase/user"
        $json = Invoke-GitCodeApi -Url $url -Token $token
        Format-Output -Json $json -Raw:$raw
    }
    "repo" {
        if (-not $owner -or -not $repo) { Write-Error "repo 命令需要 -o <owner> -r <repo>"; exit 1 }
        $url = "$ApiBase/repos/$owner/$repo"
        $json = Invoke-GitCodeApi -Url $url -Token $token
        Format-Output -Json $json -Raw:$raw
    }
    "search-repos" {
        if (-not $query) { Write-Error "search-repos 命令需要 -q <keyword>"; exit 1 }
        $encoded = [uri]::EscapeDataString($query)
        $url = "$ApiBase/search/repositories?q=$encoded"
        $json = Invoke-GitCodeApi -Url $url -Token $token
        Format-Output -Json $json -Raw:$raw
    }
    "issues" {
        if (-not $owner -or -not $repo) { Write-Error "issues 命令需要 -o <owner> -r <repo>"; exit 1 }
        $url = "$ApiBase/repos/$owner/$repo/issues?state=$state&page=$page&per_page=$perPage"
        $json = Invoke-GitCodeApi -Url $url -Token $token
        Format-Output -Json $json -Raw:$raw
    }
    default {
        Write-Error "未知命令: $cmd（可用: user, repo, search-repos, issues）"
        Show-Help
        exit 1
    }
}
