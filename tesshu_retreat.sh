#!/usr/bin/env bash
# 🏯 multi-agent-shogun 撤退スクリプト（セッション終了用）
# Retreat Script — Gracefully shuts down all agents and background processes
#
# 使用方法:
#   ./teppei_retreat.sh        # 全プロセス停止・セッション終了
#   ./teppei_retreat.sh -q     # 静かに終了（バナーなし）
#   ./teppei_retreat.sh -h     # ヘルプ表示

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════════════════════
# オプション解析
# ═══════════════════════════════════════════════════════════════════════════════
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            echo ""
            echo "🏯 multi-agent-shogun 撤退スクリプト"
            echo ""
            echo "使用方法: ./teppei_retreat.sh [オプション]"
            echo ""
            echo "オプション:"
            echo "  -q, --quiet   静かに終了（バナーなし）"
            echo "  -h, --help    このヘルプを表示"
            echo ""
            exit 0
            ;;
        *)
            echo "不明なオプション: $1"
            echo "./teppei_retreat.sh -h でヘルプを表示"
            exit 1
            ;;
    esac
done

# 色付きログ関数
log_info() {
    echo -e "\033[1;33m【報】\033[0m $1"
}
log_success() {
    echo -e "\033[1;32m【成】\033[0m $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 撤退バナー
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$QUIET" = false ]; then
    echo ""
    echo -e "\033[1;34m╔══════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;34m║\033[0m  \033[1;37m🏯 撤退じゃ！ 全軍、陣を引け！\033[0m                          \033[1;34m║\033[0m"
    echo -e "\033[1;34m║\033[0m  \033[1;36m   Retreat! All forces, fall back!\033[0m                      \033[1;34m║\033[0m"
    echo -e "\033[1;34m╚══════════════════════════════════════════════════════════════╝\033[0m"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: バックグラウンドプロセス停止
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🔇 背後の忍びを撤収中... (Stopping background processes)"

# inbox_watcher
KILLED_WATCHERS=$(pkill -fc "inbox_watcher.sh" 2>/dev/null || echo "0")
log_info "  └─ inbox_watcher: ${KILLED_WATCHERS} プロセス停止"

# inotifywait / fswatch (inbox_watcher の子プロセス)
pkill -f "inotifywait.*queue/inbox" 2>/dev/null || true
pkill -f "fswatch.*queue/inbox" 2>/dev/null || true

# ntfy_listener
pkill -f "ntfy_listener.sh" 2>/dev/null || true
log_info "  └─ ntfy_listener 停止"

# telegram_listener
pkill -f "telegram_listener.sh" 2>/dev/null || true
log_info "  └─ telegram_listener 停止"

# watcher_supervisor
pkill -f "watcher_supervisor.sh" 2>/dev/null || true
log_info "  └─ watcher_supervisor 停止"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: tmux セッション終了
# ═══════════════════════════════════════════════════════════════════════════════
log_info "⛺ 陣を撤収中... (Killing tmux sessions)"

tmux kill-session -t multiagent 2>/dev/null \
    && log_info "  └─ multiagent陣、撤収完了" \
    || log_info "  └─ multiagent陣は存在せず"

tmux kill-session -t shogun 2>/dev/null \
    && log_info "  └─ shogun本陣、撤収完了" \
    || log_info "  └─ shogun本陣は存在せず"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: idle フラグファイル掃除
# ═══════════════════════════════════════════════════════════════════════════════
IDLE_FLAG_DIR="${IDLE_FLAG_DIR:-/tmp}"
rm -f "${IDLE_FLAG_DIR}"/shogun_idle_* 2>/dev/null || true
log_info "  └─ idle フラグクリア"

# ═══════════════════════════════════════════════════════════════════════════════
# 完了
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
log_success "🏯 全軍撤退完了。お疲れ様でござった。"
if [ "$QUIET" = false ]; then
    echo ""
fi
