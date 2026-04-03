#!/usr/bin/env bash
# Shogun System Auto-Start for Shepherd (systemd-compatible)
# Starts tmux sessions + kiro-cli agents + telegram_listener

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
KIRO="${HOME}/.local/bin/kiro-cli"
export TERM="${TERM:-xterm-256color}"

log() { echo "[shogun_autostart] $*"; }

# ── 1. shogun session ───────────────────────────────────────────────────────
if tmux has-session -t shogun 2>/dev/null; then
    log "shogun session already exists — skip"
else
    tmux new-session -d -s shogun -n main -x 220 -y 50 -c "$SCRIPT_DIR"
    tmux set-option -p -t "shogun:main" @agent_id "shogun"
    tmux send-keys -t shogun:main \
        "cd \"$SCRIPT_DIR\" && $KIRO chat --trust-all-tools --agent shogun-system" Enter
    log "shogun session created, kiro-cli (shogun-system) started"
fi

# ── 2. multiagent session ───────────────────────────────────────────────────
if tmux has-session -t multiagent 2>/dev/null; then
    log "multiagent session already exists — skip"
else
    tmux new-session -d -s multiagent -n agents -x 220 -y 50 -c "$SCRIPT_DIR"

    # Create 8 additional panes (total 9: pane 0-8)
    for i in $(seq 1 8); do
        tmux split-window -t multiagent:agents -c "$SCRIPT_DIR"
    done
    tmux select-layout -t multiagent:agents tiled

    # Agent definitions: id and --agent name
    AGENT_IDS=(karo ashigaru1 ashigaru2 ashigaru3 ashigaru4 ashigaru5 ashigaru6 ashigaru7 gunshi)
    AGENT_OPTS=(karo-system ashigaru-system ashigaru-system ashigaru-system ashigaru-system ashigaru-system ashigaru-system ashigaru-system gunshi-system)

    for i in "${!AGENT_IDS[@]}"; do
        agent="${AGENT_IDS[$i]}"
        opt="${AGENT_OPTS[$i]}"
        tmux set-option -p -t "multiagent:agents.$i" @agent_id "$agent"
        tmux send-keys -t "multiagent:agents.$i" \
            "cd \"$SCRIPT_DIR\" && $KIRO chat --trust-all-tools --agent $opt" Enter
    done
    log "multiagent session created (9 panes: karo + ashigaru1-7 + gunshi)"
fi

# ── 3. telegram_listener ────────────────────────────────────────────────────
if pgrep -f "telegram_listener.sh" > /dev/null 2>&1; then
    log "telegram_listener already running — skip"
else
    nohup bash "$SCRIPT_DIR/scripts/telegram_listener.sh" \
        > /tmp/telegram_listener.log 2>&1 &
    log "telegram_listener started (PID: $!)"
fi

# ── 4. startup notification ─────────────────────────────────────────────────
bash "$SCRIPT_DIR/scripts/telegram_send.sh" \
    "🏯 Shepherd将軍システム自動起動完了でござる。"
