#!/bin/bash
# SessionStart Hook: 会话启动时记录基本信息到每日日志
# 轻量级，不调用 API，仅记录会话元数据
# 同一 session_id 每天只记录一次（避免 resume 时重复）

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi
JOURNAL_DIR="${JOURNAL_DIR:-$HOME/daily_journal}/raw"

TODAY=$(date +%Y-%m-%d)
NOW=$(date +"%H:%M")
RAW_LOG="$JOURNAL_DIR/$TODAY.md"

# 确保目录存在
mkdir -p "$JOURNAL_DIR"

# 从 stdin 读取 JSON
INPUT=$(cat)

# 提取字段
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)

# 如果没有 session_id，跳过
if [ -z "$SESSION_ID" ]; then
    echo '{"continue": true}'
    exit 0
fi

# 去重：如果今天的 raw 日志中已经记录过该 session_id，跳过
if [ -f "$RAW_LOG" ] && grep -q "$SESSION_ID" "$RAW_LOG" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

# 获取项目名称
PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "unknown")

# 追加到 raw 日志（仅记录会话开始，不含实际对话内容）
{
    echo ""
    echo "## 会话开始 - $NOW"
    echo "**项目**: $PROJECT_NAME"
    echo "**会话ID**: $SESSION_ID"
    echo ""
    echo "[会话启动，待会话结束后将记录完整工作摘要]"
    echo ""
    echo "---"
} >> "$RAW_LOG"

echo '{"continue": true}'
