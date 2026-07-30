# Sensitive Info Guard — 敏感信息防护 Skill

> 防止密码、API Key、凭证等敏感信息被提交到 Git 仓库

## 适用场景

- 提交代码前自动检查是否包含敏感信息
- 新项目初始化时安装 pre-commit hook
- CI/CD 流水线中作为安全门禁
- 代码审查时快速扫描敏感信息

## 核心原理

通过 Git `pre-commit` hook，在 `git commit` 执行前自动扫描暂存区（staged）文件内容，匹配预定义的敏感信息模式（正则表达式），发现匹配则阻止提交并输出详细报告。

## 检测规则

| 规则名 | 模式 | 说明 |
|--------|------|------|
| `API_Key_OpenAI` | `sk-[A-Za-z0-9]{20,}` | OpenAI/类似格式的 API Key |
| `API_Key_Hardcoded` | `api_key := <value>` | 硬编码的 api_key 值 (≥16字符) |
| `Password_Hardcoded` | `password := <value>` | 硬编码的 password 值 (≥6字符) |
| `Password_YML` | `password: <value>` | YAML 中的 password 值 |
| `Secret_Hardcoded` | `secret_key := <value>` | 硬编码的 secret_key 值 |
| `Token_Hardcoded` | `token := <value>` | 硬编码的 token 值 (≥20字符) |
| `Private_Key` | `private_key := <value>` | 硬编码的 private_key 值 |
| `AWS_Access_Key` | `AKIA[0-9A-Z]{16}` | AWS Access Key ID |
| `GitHub_PAT` | `ghp_[A-Za-z0-9]{36,}` | GitHub Personal Access Token |
| `GitHub_OAuth` | `gho_[A-Za-z0-9]{36,}` | GitHub OAuth Token |
| `JWT_Secret` | `jwt_secret := <value>` | 硬编码的 JWT Secret |
| `Bearer_Token` | `Bearer <value>` | HTTP Bearer Token 值 |

## 白名单（允许的占位符）

以下值被视为安全的占位符，不会触发告警（**精确匹配**，非子串匹配）：

```
password, 123456, admin123, admin123456, root, test, demo, example,
placeholder, your_password, your-password, CHANGE_ME, xxx,
your_api_key, your-api-key, your_secret, your-secret,
your_token, your-token, sk-placeholder, sk-test, sk-example,
sk-your-api-key, none, null, empty, default, changeme
```

## 安装

### 方式一：全局安装（推荐，所有仓库立即生效）

通过 `core.hooksPath` 将 hook 安装到全局目录，所有 Git 仓库的 `git commit` 都会自动检查：

```bash
# 1. 创建全局 hooks 目录
mkdir -p ~/.git-hooks

# 2. 复制 pre-commit hook
cp pre-commit ~/.git-hooks/pre-commit
chmod +x ~/.git-hooks/pre-commit

# 3. 设置全局 hooks 路径（Git 2.9+）
git config --global core.hooksPath ~/.git-hooks
```

> ⚠️ 设置 `core.hooksPath` 后，所有仓库将使用全局 hooks 目录，不再读取各自的 `.git/hooks/`。
> 如需恢复默认行为：`git config --global --unset core.hooksPath`

### 方式二：单仓库安装 — 直接复制 hook 文件

```bash
# 将 pre-commit hook 复制到目标仓库的 .git/hooks/ 目录
cp pre-commit /path/to/repo/.git/hooks/pre-commit
chmod +x /path/to/repo/.git/hooks/pre-commit
```

### 方式三：单仓库安装 — 使用 install.sh 一键安装

```bash
cd /path/to/repo
bash /path/to/sensitive-info-guard/install.sh
```

## 使用

### 正常提交（自动检查）

```bash
git add .
git commit -m "feat: add new feature"
# → 如果有敏感信息，提交会被阻止
# → 如果没有敏感信息，正常提交
```

### 临时跳过检查（紧急情况）

```bash
git commit --no-verify -m "feat: add new feature"
```

> ⚠️ 仅在确认无敏感信息时使用 `--no-verify`

### 手动运行检查（不触发提交）

```bash
bash .git/hooks/pre-commit
```

## 输出示例

### 检测到敏感信息时

```
🚨🚨🚨  检测到 3 处敏感信息！提交已被阻止  🚨🚨🚨

详细报告：

  ❌ [API_Key_OpenAI] sql/ai_model.sql
     规则: OpenAI/类似格式的 API Key (sk-xxx...)
     匹配: sk-W***iztg (长度=25)

  ❌ [Password_YML] ruoyi-admin/src/main/resources/application-druid.yml
     规则: YAML 中的 password 值
     匹配: pass***3456 (长度=18)

  ❌ [API_Key_OpenAI] AGENTS.md
     规则: OpenAI/类似格式的 API Key (sk-xxx...)
     匹配: sk-W***iztg (长度=25)

处理建议：
  1. 将真实密码/Key 替换为占位符（如 password: CHANGE_ME, api_key: <your_api_key>）
  2. 将敏感配置移到环境变量或 .env 文件（并确保 .env 已加入 .gitignore）
  3. SQL 初始化数据中的 API Key 使用占位符，首次部署时由管理员手动录入
  4. 文档中的示例使用虚构值（如 http://example.com/v1, sk-placeholder1234）
```

### 检查通过时

```
✅ 敏感信息检查通过：未发现密码、API Key、凭证等敏感数据
```

## 处理敏感信息的最佳实践

### 1. 配置文件中的密码

```yaml
# ❌ 错误：硬编码真实密码
spring:
  datasource:
    password: ry111111

# ✅ 正确：使用占位符
spring:
  datasource:
    password: ${DB_PASSWORD:CHANGE_ME}
```

### 2. SQL 初始化数据中的 API Key

```sql
-- ❌ 错误：包含真实 API Key
INSERT INTO sys_ai_model (api_key) VALUES ('sk-asdfg123456JKLKLGKJGI');

-- ✅ 正确：使用占位符，部署时手动录入
INSERT INTO sys_ai_model (api_key) VALUES ('sk-your-api-key');
```

### 3. 文档中的示例

```markdown
<!-- ❌ 错误：包含真实服务器地址和 Key -->
API_BASE: http://123.123.123.123:8080/v1
API_KEY: sk-asdfg123456JKLKLGKJGI

<!-- ✅ 正确：使用虚构示例值 -->
API_BASE: http://example.com/v1
API_KEY: sk-your-api-key
```

### 4. .env 文件管理

```bash
# .env（加入 .gitignore）
DB_PASSWORD=ry111111
API_KEY=sk-asdfg123456JKLKLGKJGI

# .env.example（提交到仓库）
DB_PASSWORD=CHANGE_ME
API_KEY=sk-your-api-key
```

## 自定义

### 添加新规则

编辑 `pre-commit` 文件中的 `RULES` 数组：

```bash
RULES=(
  # ... 现有规则 ...
  "My_Custom_Rule|my_secret_\d{10,}|自定义的敏感信息模式"
)
```

### 添加白名单值

编辑 `ALLOWED_EXACT` 数组：

```bash
ALLOWED_EXACT=(
  # ... 现有白名单 ...
  "my_safe_placeholder"
)
```

## 文件清单

| 文件 | 说明 |
|------|------|
| `SKILL.md` | 本文档 |
| `pre-commit` | Git pre-commit hook 脚本 |
| `install.sh` | 安装脚本（支持 `--global` 全局安装和 `--force` 强制覆盖） |

## 注意事项

1. **白名单使用精确匹配**：`ry111111` 不会因为包含 `123456` 而被放行
2. **只检查文本文件**：自动排除二进制文件（图片、jar、class 等）
3. **只检查新增/修改行**：不会对未变更的历史代码报错
4. **脱敏显示**：报告中只显示敏感值的前4+后4字符，中间用 `***` 替代
5. **`--no-verify` 可跳过**：紧急情况下可绕过检查，但请谨慎使用
