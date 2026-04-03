#!/usr/bin/env bash
# Shogun System Auto-Start for Shepherd
# Wrapper: delegates full startup to shutsujin_departure.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/..)" && pwd)"

# Skip if shogun session already exists (service restart safety)
if tmux has-session -t shogun 2>/dev/null; then
    echo "[shogun_autostart] shogun session already running — skip"
    exit 0
fi

# Full army startup
bash "$SCRIPT_DIR/shutsujin_departure.sh"
