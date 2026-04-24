#!/bin/bash
# Claude Daily Journal - 卸载脚本

set -euo pipefail

INSTALL_DIR="$HOME/.claude/hooks"
CONFIG_FILE="$INSTALL_DIR/config.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Daily Journal - 卸载程序"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── 1. 移除 crontab ─────────────────────────────────
info "移除 crontab 条目..."
(crontab -l 2>/dev/null || true) | grep -v "daily-journal-cron.sh" | crontab - 2>/dev/null || true
ok "crontab 条目已移除"

# ─── 2. 移除 Claude Code hooks ────────────────────────
info "移除 Claude Code hooks..."
if [ -f "$SETTINGS_FILE" ]; then
    python3 -c "
import json

settings_file = '$SETTINGS_FILE'
with open(settings_file) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})

# 只移除我们注册的 hook（通过命令路径匹配）
for event in ['SessionStart', 'SessionEnd']:
    if event in hooks:
        filtered = []
        for entry in hooks[event]:
            filtered_hooks = [h for h in entry.get('hooks', [])
                            if 'daily-journal' not in h.get('command', '')
                            and 'on-session-start.sh' not in h.get('command', '')
                            and 'on-session-end.sh' not in h.get('command', '')]
            if filtered_hooks:
                entry['hooks'] = filtered_hooks
                filtered.append(entry)
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]

settings['hooks'] = hooks

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print('hooks 已移除')
"
fi
ok "Claude Code hooks 已移除"

# ─── 3. 删除脚本文件 ──────────────────────────────────
info "删除脚本文件..."
rm -f "$INSTALL_DIR/on-session-start.sh"
rm -f "$INSTALL_DIR/on-session-end.sh"
rm -f "$INSTALL_DIR/daily-journal-cron.sh"
rm -f "$INSTALL_DIR/lib/feishu_doc_push.py"
rmdir "$INSTALL_DIR/lib" 2>/dev/null || true
ok "脚本文件已删除"

# ─── 4. 配置文件 ──────────────────────────────────────
if [ -f "$CONFIG_FILE" ]; then
    echo ""
    read -p "是否删除配置文件 $CONFIG_FILE？[y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
        ok "配置文件已删除"
    else
        warn "保留配置文件: $CONFIG_FILE"
    fi
fi

# ─── 5. 日志目录 ──────────────────────────────────────
if [ -d "$HOME/daily_journal" ]; then
    echo ""
    read -p "是否删除日志目录 $HOME/daily_journal/？[y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$HOME/daily_journal"
        ok "日志目录已删除"
    else
        warn "保留日志目录: $HOME/daily_journal/"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}卸载完成！${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
