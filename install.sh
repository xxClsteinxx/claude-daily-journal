#!/bin/bash
# Claude Daily Journal - 一键安装脚本
# 用法: bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/hooks"
CONFIG_FILE="$INSTALL_DIR/config.sh"

# ─── 颜色 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Daily Journal - 安装程序"
echo "  自动记录 Claude Code 每日工作内容"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── 1. 检查依赖 ──────────────────────────────────────
info "检查依赖..."

MISSING=()

if ! command -v bash &>/dev/null; then
    MISSING+=("bash")
fi

if ! command -v python3 &>/dev/null; then
    MISSING+=("python3")
fi

if ! command -v git &>/dev/null; then
    MISSING+=("git")
fi

if ! command -v curl &>/dev/null; then
    MISSING+=("curl")
fi

# Claude CLI
CLAUDE_BIN=""
if command -v claude &>/dev/null; then
    CLAUDE_BIN="$(command -v claude)"
    ok "Claude CLI: $CLAUDE_BIN"
elif [ -x "$HOME/.npm-global/bin/claude" ]; then
    CLAUDE_BIN="$HOME/.npm-global/bin/claude"
    ok "Claude CLI: $CLAUDE_BIN"
else
    warn "Claude CLI 未找到（会话摘要功能将降级为基础记录）"
    warn "安装方式: npm install -g @anthropic-ai/claude-code"
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    error "缺少必要依赖: ${MISSING[*]}"
    echo "  请先安装后重试。"
    exit 1
fi

ok "python3: $(python3 --version 2>&1)"
ok "git: $(git --version 2>&1)"
ok "curl: $(curl --version 2>&1 | head -1)"

echo ""

# ─── 2. 创建目录 ──────────────────────────────────────
info "创建目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$HOME/daily_journal/raw"
ok "目录创建完成"

# ─── 3. 复制脚本 ──────────────────────────────────────
info "安装脚本..."

cp "$SCRIPT_DIR/hooks/on-session-start.sh" "$INSTALL_DIR/on-session-start.sh"
cp "$SCRIPT_DIR/hooks/on-session-end.sh"   "$INSTALL_DIR/on-session-end.sh"
cp "$SCRIPT_DIR/hooks/daily-journal-cron.sh" "$INSTALL_DIR/daily-journal-cron.sh"
cp "$SCRIPT_DIR/lib/feishu_doc_push.py"    "$INSTALL_DIR/lib/feishu_doc_push.py"

chmod +x "$INSTALL_DIR/on-session-start.sh"
chmod +x "$INSTALL_DIR/on-session-end.sh"
chmod +x "$INSTALL_DIR/daily-journal-cron.sh"

ok "脚本安装完成"

# ─── 4. 配置文件 ──────────────────────────────────────
if [ -f "$CONFIG_FILE" ]; then
    warn "配置文件已存在: $CONFIG_FILE（跳过）"
else
    info "创建配置文件..."
    cp "$SCRIPT_DIR/config.example.sh" "$CONFIG_FILE"
    ok "配置文件已创建: $CONFIG_FILE"
    echo ""
    echo -e "  ${YELLOW}请编辑配置文件，填入你的飞书凭证：${NC}"
    echo "  vim $CONFIG_FILE"
    echo ""
fi

# ─── 5. 注册 Claude Code hooks ────────────────────────
info "注册 Claude Code hooks..."

SETTINGS_FILE="$HOME/.claude/settings.json"
START_HOOK_CMD="bash $INSTALL_DIR/on-session-start.sh"
END_HOOK_CMD="bash $INSTALL_DIR/on-session-end.sh"

if [ ! -f "$SETTINGS_FILE" ]; then
    # 创建最小 settings.json
    cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "hooks": {}
}
SETTINGS_EOF
    ok "创建 settings.json"
fi

# 用 Python 更新 settings.json（安全地合并 hooks）
python3 -c "
import json, sys

settings_file = '$SETTINGS_FILE'
start_cmd = '$START_HOOK_CMD'
end_cmd = '$END_HOOK_CMD'

with open(settings_file) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})

# 注册 SessionStart hook
hooks['SessionStart'] = [{
    'matcher': '*',
    'hooks': [{
        'type': 'command',
        'command': start_cmd,
        'timeout': 10
    }]
}]

# 注册 SessionEnd hook
hooks['SessionEnd'] = [{
    'matcher': '*',
    'hooks': [{
        'type': 'command',
        'command': end_cmd,
        'timeout': 120
    }]
}]

settings['hooks'] = hooks

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print('hooks 注册成功')
"

ok "Claude Code hooks 注册完成"

# ─── 6. 设置 crontab ──────────────────────────────────
CRON_HOUR="${CRON_HOUR:-22}"
CRON_MINUTE="${CRON_MINUTE:-30}"
CRON_CMD="bash $INSTALL_DIR/daily-journal-cron.sh"

# 读取 config 中的 cron 时间
if [ -f "$CONFIG_FILE" ]; then
    h=$(grep '^CRON_HOUR=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'")
    m=$(grep '^CRON_MINUTE=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'")
    [ -n "$h" ] && CRON_HOUR="$h"
    [ -n "$m" ] && CRON_MINUTE="$m"
fi

info "设置 crontab（每天 ${CRON_HOUR}:${CRON_MINUTE} 执行）..."

# 移除旧的条目（如果有）
(crontab -l 2>/dev/null || true) | grep -v "daily-journal-cron.sh" | crontab - 2>/dev/null || true

# 添加新条目
(crontab -l 2>/dev/null || true; echo "$CRON_MINUTE $CRON_HOUR * * * $CRON_CMD >> $HOME/daily_journal/cron.log 2>&1") | crontab -

ok "crontab 设置完成"

# ─── 7. 完成 ──────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}安装完成！${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  安装位置: $INSTALL_DIR"
echo "  配置文件: $CONFIG_FILE"
echo "  日志目录: $HOME/daily_journal/"
echo "  Cron 时间: 每天 ${CRON_HOUR}:${CRON_MINUTE}"
echo ""
echo -e "  ${YELLOW}下一步：${NC}"
echo "  1. 编辑配置文件: vim $CONFIG_FILE"
echo "  2. 重启 Claude Code 使 hook 生效"
echo ""
echo "  如需飞书云文档推送，请在配置文件中填入："
echo "  - FEISHU_WEBHOOK_URL（飞书群机器人 Webhook）"
echo "  - FEISHU_APP_ID + FEISHU_APP_SECRET（飞书应用凭证）"
echo ""
