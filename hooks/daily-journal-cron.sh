#!/bin/bash
# Cron 汇总脚本：读取当日 raw 日志 + git 提交，生成精美日报，推送到飞书
# 由 crontab 调用，默认每天 22:30 执行

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 确保 cron 环境能找到所有需要的命令
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export HOME="$HOME"

JOURNAL_DIR="${JOURNAL_DIR:-$HOME/daily_journal}"
RAW_DIR="$JOURNAL_DIR/raw"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "")}"
PYTHON3="python3"
GIT_REPO_DIRS="${GIT_REPO_DIRS:-$HOME/myCode}"
TODAY=$(date +%Y-%m-%d)
TODAY_UNIX=$(date -d "$TODAY" +%s 2>/dev/null || date +%s)
RAW_LOG="$RAW_DIR/$TODAY.md"
FINAL_REPORT="$JOURNAL_DIR/$TODAY.md"

# 如果今天的 raw 日志不存在且没有 git 提交，不生成日报
HAS_RAW=false
HAS_GIT=false

if [ -f "$RAW_LOG" ] && [ -s "$RAW_LOG" ]; then
    HAS_RAW=true
fi

# 收集所有 git 仓库的今日提交
GIT_COMMITS=$("$PYTHON3" -c "
import subprocess, os, glob

repo_dirs = '''${GIT_REPO_DIRS}'''.split(':')
repos = []
for base_dir in repo_dirs:
    base_dir = os.path.expanduser(base_dir.strip())
    if not os.path.isdir(base_dir):
        continue
    for d in glob.glob(os.path.join(base_dir, '*')):
        if os.path.isdir(os.path.join(d, '.git')):
            repos.append(d)
        for sub in glob.glob(os.path.join(d, '*/.git')):
            repos.append(os.path.dirname(sub))

commits = []
for repo in repos:
    try:
        result = subprocess.run(
            ['git', 'log', '--oneline', '--since=midnight', '--author=.', '-50'],
            cwd=repo, capture_output=True, text=True, timeout=10
        )
        if result.stdout.strip():
            repo_name = os.path.basename(repo)
            commits.append(f'### {repo_name}')
            for line in result.stdout.strip().split('\n'):
                commits.append(f'- {line}')
            commits.append('')
    except Exception:
        continue

if commits:
    print('\n'.join(commits))
" 2>/dev/null) || GIT_COMMITS=""

if [ -n "$GIT_COMMITS" ]; then
    HAS_GIT=true
fi

# 扫描仍在运行的会话（SessionEnd hook 尚未触发）
RUNNING_SESSIONS=""
if [ -d "$HOME/.claude/projects" ]; then
    RUNNING_SESSIONS=$("$PYTHON3" -c "
import os, glob, json, time

today_start = $TODAY_UNIX
raw_log = '$RAW_LOG'

# 读取已记录的 session IDs
recorded_ids = set()
if os.path.exists(raw_log):
    with open(raw_log) as f:
        for line in f:
            if '会话ID' in line:
                sid = line.split('会话ID')[-1].strip().strip('*').strip()
                if sid:
                    recorded_ids.add(sid)

# 扫描所有项目的 transcript 文件
found = []
for proj_dir in glob.glob(os.path.expanduser('~/.claude/projects/*')):
    for jsonl in glob.glob(os.path.join(proj_dir, '*.jsonl')):
        mtime = os.path.getmtime(jsonl)
        if mtime < today_start:
            continue
        sid = os.path.splitext(os.path.basename(jsonl))[0]
        if sid in recorded_ids:
            continue
        try:
            last_lines = []
            with open(jsonl, 'rb') as f:
                f.seek(0, 2)
                size = f.tell()
                f.seek(max(0, size - 2000))
                last_lines = f.read().decode('utf-8', errors='ignore').split('\n')
            cwd = ''
            for line in reversed(last_lines):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    cwd = obj.get('cwd', '')
                    if cwd:
                        break
                except:
                    continue
            project = os.path.basename(cwd) if cwd else 'unknown'
            found.append(f'- 项目: {project} (会话ID: {sid[:8]}...)')
        except Exception:
            continue

if found:
    print('\n'.join(found))
" 2>/dev/null) || RUNNING_SESSIONS=""
fi

# 如果既没有 raw 日志也没有 git 提交，也没有运行中的会话，退出
if [ "$HAS_RAW" = false ] && [ "$HAS_GIT" = false ] && [ -z "$RUNNING_SESSIONS" ]; then
    exit 0
fi

# 组装 prompt
PROMPT="请根据以下信息，用中文生成一份精美的每日工作日报。要求：
1. 用 Markdown 格式
2. 按项目分类总结工作内容
3. 语言简洁专业
4. 如果有 git 提交记录，列出关键提交
5. 最后加一段简短的今日总结

格式参考：
# 工作日报 - $TODAY

## 今日工作总结
（按项目分类的工作内容）

## Git 提交记录
（关键提交列表）

## 今日总结
（1-2句话总结今天的工作重点）

--- 以下是原始数据 ---"

if [ "$HAS_RAW" = true ]; then
    PROMPT="$PROMPT

【Claude Code 会话记录】"
    PROMPT="$PROMPT
$(cat "$RAW_LOG")"
fi

if [ "$HAS_GIT" = true ]; then
    PROMPT="$PROMPT

【Git 提交记录】
$GIT_COMMITS"
fi

if [ -n "$RUNNING_SESSIONS" ]; then
    PROMPT="$PROMPT

【仍在运行的会话（时尚未结束，仅有部分记录）】
$RUNNING_SESSIONS"
fi

# 调用 Claude CLI 生成日报
REPORT=""
if [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ]; then
    REPORT=$(echo "$PROMPT" | timeout 120 "$CLAUDE_BIN" --print -p "" 2>/dev/null) || true
fi

# 如果 Claude CLI 失败，生成简单的纯文本日报
if [ -z "$REPORT" ]; then
    REPORT="# 工作日报 - $TODAY

## 原始记录

"
    if [ "$HAS_RAW" = true ]; then
        REPORT="$REPORT
$(cat "$RAW_LOG")
"
    fi
    if [ "$HAS_GIT" = true ]; then
        REPORT="$REPORT
## Git 提交记录

$GIT_COMMITS
"
    fi
fi

# 写入最终日报
echo "$REPORT" > "$FINAL_REPORT"

# === 飞书云文档 + 群消息推送 ===
push_to_feishu() {
    local report_file="$1"
    local report_date="$2"

    if [ ! -f "$report_file" ] || [ ! -s "$report_file" ]; then
        echo "日报文件为空，跳过飞书推送"
        return 0
    fi

    # 从 config 读取飞书配置（已由顶部 source 加载）
    if [ -z "${FEISHU_APP_ID:-}" ] || [ -z "${FEISHU_APP_SECRET:-}" ]; then
        echo "飞书应用凭证未配置，跳过云文档推送"
        return 0
    fi

    # 1. 创建飞书云文档
    local doc_url
    export FEISHU_APP_ID FEISHU_APP_SECRET
    doc_url=$(python3 "$SCRIPT_DIR/../lib/feishu_doc_push.py" "$report_file" "$report_date" 2>/dev/null)

    if [ -z "$doc_url" ] || [[ ! "$doc_url" =~ ^https:// ]]; then
        echo "创建飞书云文档失败"
        return 1
    fi
    echo "飞书云文档已创建: $doc_url"

    # 2. 通过 Webhook 发送文档链接到群
    if [ -z "${FEISHU_WEBHOOK_URL:-}" ] || [[ "$FEISHU_WEBHOOK_URL" == *"YOUR_WEBHOOK"* ]]; then
        echo "飞书 Webhook URL 未配置，仅创建云文档"
        return 0
    fi

    if ! command -v curl &>/dev/null; then
        echo "curl 未安装，跳过群消息推送"
        return 0
    fi

    local msg_json
    msg_json=$(python3 -c "
import json
card = {
    'msg_type': 'interactive',
    'card': {
        'header': {
            'title': {'tag': 'plain_text', 'content': '📋 工作日报 - $report_date'},
            'template': 'blue'
        },
        'elements': [
            {
                'tag': 'div',
                'text': {
                    'tag': 'lark_md',
                    'content': '今日工作日报已生成，点击查看飞书云文档：\n[📄 工作日报 - $report_date]($doc_url)'
                }
            }
        ]
    }
}
print(json.dumps(card, ensure_ascii=False))
")

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$FEISHU_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$msg_json" \
        --connect-timeout 10 \
        --max-time 15)

    if [ "$http_code" = "200" ]; then
        echo "飞书群消息推送成功"
    else
        echo "飞书群消息推送失败，HTTP 状态码: $http_code"
    fi
}

push_to_feishu "$FINAL_REPORT" "$TODAY"

# 清理 raw 日志
if [ "$HAS_RAW" = true ]; then
    rm -f "$RAW_LOG"
fi

exit 0
