#!/bin/bash
# SessionEnd Hook: 会话结束时记录工作摘要到每日日志
# 读取 transcript JSONL，用 Claude CLI 生成中文摘要，追加到 raw 日志

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi
JOURNAL_DIR="${JOURNAL_DIR:-$HOME/daily_journal}/raw"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "")}"
PYTHON3="python3"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +"%H:%M")
RAW_LOG="$JOURNAL_DIR/$TODAY.md"

# 确保目录存在
mkdir -p "$JOURNAL_DIR"

# 从 stdin 读取 JSON
INPUT=$(cat)

# 提取字段
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('transcript_path',''))")
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))")
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))")
REASON=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('reason',''))")

# 如果没有 transcript_path，跳过
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# 检查 transcript 文件是否有内容
if [ ! -s "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# 提取对话内容（最后100行，只取 user 和 assistant 的文本消息）
CONVERSATION=$(tail -n 100 "$TRANSCRIPT_PATH" | "$PYTHON3" -c "
import sys, json

messages = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue

    msg_type = obj.get('type', '')
    if msg_type not in ('user', 'assistant'):
        continue

    msg = obj.get('message', {})
    content = msg.get('content', [])

    text_parts = []
    for item in content:
        if isinstance(item, dict) and item.get('type') == 'text':
            text = item.get('text', '')
            # 跳过系统标签和过长的内容
            if text.startswith('<') and '>' in text[:50]:
                continue
            if len(text) > 500:
                text = text[:500] + '...'
            text_parts.append(text)

    if text_parts:
        role = '用户' if msg_type == 'user' else '助手'
        messages.append(f'{role}: {\" \".join(text_parts)}')

# 只取最后20条消息，避免过长
for m in messages[-20:]:
    print(m)
" 2>/dev/null)

# 如果没有有效对话内容，跳过
if [ -z "$CONVERSATION" ]; then
    exit 0
fi

# 获取项目名称（从 cwd 提取最后一级目录名）
PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "unknown")

# 用 Claude CLI 生成摘要
SUMMARY=""
if [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ]; then
    SUMMARY=$(echo "$CONVERSATION" | timeout 100 "$CLAUDE_BIN" --print -p "请根据以下 Claude Code 会话记录，用中文生成一段简短的工作摘要（3-5句话）。说明用户在这个项目中让 Claude 帮忙做了什么。只输出摘要内容，不要加标题或前缀。项目名：$PROJECT_NAME" 2>/dev/null)
fi

# 如果 Claude CLI 调用失败，使用原始对话的简要概括作为 fallback
if [ -z "$SUMMARY" ]; then
    SUMMARY="[自动记录] 会话发生在 $PROJECT_NAME 项目中，对话包含 $(echo "$CONVERSATION" | wc -l) 条消息。"
fi

# 追加到 raw 日志
{
    echo ""
    echo "## 会话记录 - $NOW"
    echo "**项目**: $PROJECT_NAME"
    echo "**会话ID**: $SESSION_ID"
    echo ""
    echo "$SUMMARY"
    echo ""
    echo "---"
} >> "$RAW_LOG"

# 输出 hook 格式的 JSON
echo '{"continue": true}'
