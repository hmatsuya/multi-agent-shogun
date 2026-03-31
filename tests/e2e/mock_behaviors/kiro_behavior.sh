#!/usr/bin/env bash
# kiro_behavior.sh — Kiro CLI specific mock behaviors
# Handles /clear, /quit, and Kiro-specific prompts.

# Kiro CLI startup banner
kiro_startup_banner() {
    echo "╭────────────────────────────────────────╮"
    echo "│        Kiro CLI (mock)                 │"
    echo "│        trust-all-tools                 │"
    echo "╰────────────────────────────────────────╯"
}

# Handle /clear command (Kiro CLI behavior)
# Resets conversation history and re-checks task YAML
kiro_handle_clear() {
    local agent_id="$1"
    local project_root="$2"

    echo "[mock] /clear received — resetting session for $agent_id"
    local task_file="$project_root/queue/tasks/${agent_id}.yaml"
    if [ -f "$task_file" ]; then
        local status
        status=$(yaml_read "$task_file" "task.status")
        if [ "$status" = "assigned" ]; then
            echo "[mock] Found assigned task after /clear — resuming"
            return 0  # signal: task available
        fi
    fi
    return 1  # signal: no task
}

# Kiro idle prompt pattern (matches agent_is_busy() detection)
kiro_idle_prompt() {
    echo -ne "\033[0m"
    echo ""
    echo "> "
}
