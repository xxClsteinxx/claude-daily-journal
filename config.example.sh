#!/bin/bash
# Claude Daily Journal 配置文件
# 复制此文件为 config.sh 并填写你的配置：
#   cp config.example.sh config.sh

# ─── 飞书群机器人 Webhook ───────────────────────────────
# 在飞书群 → 群设置 → 群机器人 → 添加自定义机器人 获取
FEISHU_WEBHOOK_URL=""

# ─── 飞书应用凭证（云文档推送）─────────────────────────
# 在 https://open.feishu.cn/app 创建企业自建应用获取
# 需要开通权限：docx:document, docs:permission.setting:write_only
FEISHU_APP_ID=""
FEISHU_APP_SECRET=""

# ─── Claude API 配置（用于生成摘要，不经过 Claude Code）────
# 从 Claude Code settings.json 的 env 中获取，或手动填写
# 使用 API 直接调用，不会在 Claude Code 历史记录中产生会话
CLAUDE_API_KEY=""
CLAUDE_API_BASE="https://api.anthropic.com"
CLAUDE_MODEL="claude-sonnet-4-20250514"

# ─── 日志存储目录 ──────────────────────────────────────
JOURNAL_DIR="$HOME/daily_journal"

# ─── Git 仓库扫描目录 ─────────────────────────────────
# 收集这些目录下所有 git 仓库的今日提交
# 多个目录用冒号分隔，如 "$HOME/projects:$HOME/work"
GIT_REPO_DIRS="$HOME/myCode"

# ─── Cron 定时任务 ────────────────────────────────────
# 每日汇总的时间（24小时制）
CRON_HOUR=22
CRON_MINUTE=30
