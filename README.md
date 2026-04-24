# Claude Daily Journal

自动记录 Claude Code 每日工作内容，生成精美日报，推送至飞书云文档。

## 功能

- **会话自动记录**：每次 Claude Code 会话开始/结束时，自动记录工作摘要
- **每日汇总**：定时汇总当天所有会话记录 + Git 提交，生成结构化日报
- **飞书推送**：自动创建飞书云文档，并在群里发送卡片通知
- **零依赖**：仅使用 Python 标准库，无需 pip install
- **不污染历史**：使用 Anthropic API 直接调用，不会在 Claude Code 历史记录中产生会话

## 工作原理

```
会话开始 → 记录元数据到 raw 日志
会话结束 → 用 Claude API 生成摘要（不经过 Claude Code，不产生会话记录）
每天定时 → 汇总 raw 日志 + git 提交 → 生成日报 → 推送飞书
```

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/xxx/claude-daily-journal.git
cd claude-daily-journal
```

### 2. 一键安装

```bash
bash install.sh
```

安装脚本会自动：
- 检查依赖（bash, python3, git, curl）
- 复制脚本到 `~/.claude/hooks/`
- 注册 Claude Code hooks
- 设置 crontab 定时任务

### 3. 配置飞书（可选）

编辑配置文件：

```bash
vim ~/.claude/hooks/config.sh
```

填入飞书相关配置：

```bash
# 飞书群机器人 Webhook（群设置 → 群机器人 → 添加自定义机器人）
FEISHU_WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-id"

# 飞书应用凭证（https://open.feishu.cn/app 创建应用）
FEISHU_APP_ID="cli_xxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxx"
```

### 4. 重启 Claude Code

重启 Claude Code 使 hook 配置生效。

## 配置说明

配置文件位于 `~/.claude/hooks/config.sh`：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `FEISHU_WEBHOOK_URL` | 飞书群机器人 Webhook URL | 空（不推送群消息） |
| `FEISHU_APP_ID` | 飞书应用 App ID | 空（不创建云文档） |
| `FEISHU_APP_SECRET` | 飞书应用 App Secret | 空 |
| `CLAUDE_API_KEY` | Anthropic API Key（优先使用，不产生会话记录） | 空（自动从 settings.json 读取） |
| `CLAUDE_API_BASE` | Anthropic API Base URL | `https://api.anthropic.com` |
| `CLAUDE_MODEL` | 摘要生成使用的模型 | `claude-sonnet-4-20250514` |
| `JOURNAL_DIR` | 日志存储目录 | `$HOME/daily_journal` |
| `CLAUDE_BIN` | Claude CLI 路径（兜底用） | 自动检测 |
| `GIT_REPO_DIRS` | Git 仓库扫描目录（冒号分隔） | `$HOME/myCode` |
| `CRON_HOUR` | 每日汇总小时（24h） | `22` |
| `CRON_MINUTE` | 每日汇总分钟 | `30` |

## 飞书应用配置

如需使用飞书云文档推送功能，需要创建飞书应用：

1. 打开 [飞书开放平台](https://open.feishu.cn/app)，创建企业自建应用
2. 获取 **App ID** 和 **App Secret**
3. 在「权限管理」中开通：
   - `docx:document` — 创建、编辑云文档
   - `docs:permission.setting:write_only` — 设置文档权限
4. 发布应用并等待审批
5. 将凭证填入 `~/.claude/hooks/config.sh`

## 文件结构

```
~/.claude/hooks/
├── config.sh                 # 配置文件（安装时自动生成）
├── on-session-start.sh       # 会话开始 hook
├── on-session-end.sh         # 会话结束 hook
├── daily-journal-cron.sh     # 每日汇总脚本
└── lib/
    └── feishu_doc_push.py    # 飞书云文档推送

~/daily_journal/
├── raw/                      # 当日原始会话记录（汇总后自动清理）
├── YYYY-MM-DD.md             # 每日工作日报
└── cron.log                  # cron 执行日志
```

## 卸载

```bash
bash uninstall.sh
```

## 依赖

- bash
- python3（3.6+，仅使用标准库）
- git
- curl
- Claude Code CLI（可选，用于生成智能摘要）

## License

MIT
