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

# ─── 日志存储目录 ──────────────────────────────────────
JOURNAL_DIR="$HOME/daily_journal"

# ─── Claude CLI 路径 ──────────────────────────────────
# 留空则自动检测（推荐）
CLAUDE_BIN=""

# ─── Git 仓库扫描目录 ─────────────────────────────────
# 收集这些目录下所有 git 仓库的今日提交
# 多个目录用冒号分隔，如 "$HOME/projects:$HOME/work"
GIT_REPO_DIRS="$HOME/myCode"

# ─── Cron 定时任务 ────────────────────────────────────
# 每日汇总的时间（24小时制）
CRON_HOUR=22
CRON_MINUTE=30
