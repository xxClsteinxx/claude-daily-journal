#!/bin/bash
# Claude API 辅助函数
# 直接调用 Anthropic API 生成摘要，不经过 Claude Code，不产生会话记录

# 调用 Claude API
# 用法: claude_api_call "prompt" "input_text"
# 输出: API 返回的文本内容
# 需要在调用前 source config.sh 以获取 CLAUDE_API_KEY 和 CLAUDE_API_BASE
claude_api_call() {
    local prompt="$1"
    local input_text="$2"
    local model="${CLAUDE_MODEL:-claude-sonnet-4-20250514}"
    local api_base="${CLAUDE_API_BASE:-https://api.anthropic.com}"
    local api_key="${CLAUDE_API_KEY:-}"

    if [ -z "$api_key" ]; then
        echo ""
        return 1
    fi

    # 构建 JSON payload（用 python3 安全转义）
    local json_payload
    json_payload=$(python3 -c "
import json, sys

prompt = sys.argv[1]
content = sys.argv[2]

payload = {
    'model': '$model',
    'max_tokens': 1024,
    'messages': [{
        'role': 'user',
        'content': prompt + '\n\n' + content
    }]
}
print(json.dumps(payload, ensure_ascii=False))
" "$prompt" "$input_text")

    # 调用 API
    local response
    response=$(curl -s --max-time 60 \
        -X POST "${api_base}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${api_key}" \
        -H "anthropic-version: 2023-06-01" \
        -d "$json_payload" 2>/dev/null)

    if [ -z "$response" ]; then
        echo ""
        return 1
    fi

    # 提取文本内容
    local result
    result=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('type') == 'error':
        print('', end='')
    else:
        for block in data.get('content', []):
            if block.get('type') == 'text':
                print(block['text'], end='')
                break
except:
    print('', end='')
" 2>/dev/null)

    echo "$result"
}
