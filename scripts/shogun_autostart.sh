#!/usr/bin/env bash
# Shogun System Auto-Start for Shepherd
# Starts tmux shogun session + kiro-cli + telegram_listener

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/..)" && pwd)"
KIRO_CLI="${HOME}/.local/bin/kiro-cli"
TMUX_SESSION="shogun"

# ── 1. tmux shogun session ──────────────────────────────────────────────────
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "[shogun_autostart] tmux session '$TMUX_SESSION' already exists — skip"
else
    tmux new-session -d -s "$TMUX_SESSION" -c "$SCRIPT_DIR"
    echo "[shogun_autostart] tmux session '$TMUX_SESSION' created"

    # ── 2. kiro-cli in shogun pane ──────────────────────────────────────────
    if pgrep -f "kiro-cli chat" > /dev/null 2>&1; then
        echo "[shogun_autostart] kiro-cli already running — skip"
    else
        tmux send-keys -t "${TMUX_SESSION}:0.0" \
            "kiro-cli chat --trust-all-tools --resume" Enter
        echo "[shogun_autostart] kiro-cli started in tmux ${TMUX_SESSION}:0.0"
    fi
fi

# ── 3. telegram_listener ────────────────────────────────────────────────────
if pgrep -f "telegram_listener.sh" > /dev/null 2>&1; then
    echo "[shogun_autostart] telegram_listener already running — skip"
else
    nohup bash "$SCRIPT_DIR/scripts/telegram_listener.sh" \
        > /tmp/telegram_listener.log 2>&1 &
    echo "[shogun_autostart] telegram_listener started (PID: $!)"
fi

# ── 4. startup notification ─────────────────────────────────────────────────
bash "$SCRIPT_DIR/scripts/telegram_send.sh" \
    "🏯 Shepherd将軍システム自動起動完了でござる。"
