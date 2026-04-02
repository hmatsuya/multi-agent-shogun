#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Telegram Bot Listener
# Long-polls Telegram Bot API getUpdates, writes to ntfy_inbox.yaml, wakes shogun.
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"
INBOX="$SCRIPT_DIR/queue/ntfy_inbox.yaml"
LOCKFILE="${INBOX}.lock"
CORRUPT_DIR="$SCRIPT_DIR/logs/ntfy_inbox_corrupt"
OFFSET_FILE="$SCRIPT_DIR/queue/telegram_offset.txt"
PYTHON="$SCRIPT_DIR/.venv/bin/python3"

BOT_TOKEN=$(grep 'telegram_bot_token:' "$SETTINGS" | awk '{print $2}' | tr -d '"')

if [ -z "$BOT_TOKEN" ]; then
    echo "[telegram_listener] telegram_bot_token not configured in settings.yaml" >&2
    exit 1
fi

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    echo "inbox:" > "$INBOX"
fi

# Initialize offset
if [ ! -f "$OFFSET_FILE" ]; then
    echo "0" > "$OFFSET_FILE"
fi

append_ntfy_inbox() {
    local msg_id="$1"
    local ts="$2"
    local msg="$3"

    (
        if command -v flock &>/dev/null; then
            flock -w 5 200 || exit 1
        else
            _ld="${LOCKFILE}.d"; _i=0
            while ! mkdir "$_ld" 2>/dev/null; do sleep 0.1; _i=$((_i+1)); [ $_i -ge 50 ] && exit 1; done
            trap "rmdir '$_ld' 2>/dev/null" EXIT
        fi
        NTFY_INBOX_PATH="$INBOX" \
        NTFY_CORRUPT_DIR="$CORRUPT_DIR" \
        MSG_ID="$msg_id" \
        MSG_TS="$ts" \
        MSG_TEXT="$msg" \
        "$PYTHON" - << 'PY'
import datetime, os, shutil, sys, tempfile, yaml

path = os.environ["NTFY_INBOX_PATH"]
corrupt_dir = os.environ.get("NTFY_CORRUPT_DIR", "")
entry = {
    "id": os.environ.get("MSG_ID", ""),
    "timestamp": os.environ.get("MSG_TS", ""),
    "message": os.environ.get("MSG_TEXT", ""),
    "status": "pending",
}

data = {}
parse_error = False

if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            loaded = yaml.safe_load(f)
        data = loaded if isinstance(loaded, dict) else {}
        if not isinstance(loaded, (dict, type(None))):
            parse_error = True
    except Exception:
        parse_error = True

if parse_error and os.path.exists(path):
    try:
        if corrupt_dir:
            os.makedirs(corrupt_dir, exist_ok=True)
            backup = os.path.join(corrupt_dir,
                f"ntfy_inbox_corrupt_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.yaml")
            shutil.copy2(path, backup)
    except Exception:
        pass
    data = {}

items = data.get("inbox")
if not isinstance(items, list):
    items = []
items.append(entry)
data["inbox"] = items

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    os.replace(tmp_path, path)
except Exception as e:
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    print(f"[telegram_listener] failed to write inbox: {e}", file=sys.stderr)
    sys.exit(1)
PY
    ) 200>"$LOCKFILE"
}

record_chat_id() {
    local chat_id="$1"
    SETTINGS_PATH="$SETTINGS" CHAT_ID="$chat_id" "$PYTHON" - << 'PY'
import os, re
path = os.environ["SETTINGS_PATH"]
chat_id = os.environ["CHAT_ID"]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
if re.search(r'telegram_chat_id:\s*""', content):
    content = re.sub(r'(telegram_chat_id:\s*)""', f'\\g<1>"{chat_id}"', content)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[telegram_listener] chat_id recorded: {chat_id}", file=__import__('sys').stderr)
PY
}

process_response() {
    local response_file="$1"
    local offset_file="$2"
    # Parse updates, output: chat_id|update_id|text per line, update offset file
    RESPONSE_FILE="$response_file" OFFSET_FILE="$offset_file" "$PYTHON" - << 'PY'
import json, os, sys

response_file = os.environ["RESPONSE_FILE"]
offset_file = os.environ["OFFSET_FILE"]

with open(response_file, "r", encoding="utf-8") as f:
    data = json.load(f)

if not data.get("ok"):
    print(f"[telegram_listener] API error: {data}", file=sys.stderr)
    sys.exit(1)

updates = data.get("result", [])
max_update_id = 0

for update in updates:
    update_id = update.get("update_id", 0)
    if update_id > max_update_id:
        max_update_id = update_id
    message = update.get("message", {})
    text = message.get("text", "")
    if not text:
        continue
    chat_id = str(message.get("chat", {}).get("id", ""))
    # Escape | in text to avoid IFS split issues (replace with \x01)
    safe_text = text.replace("|", "\x01")
    print(f"{chat_id}|{update_id}|{safe_text}")

if max_update_id > 0:
    with open(offset_file, "w") as f:
        f.write(str(max_update_id + 1))
PY
}

echo "[$(date)] Telegram listener started" >&2

RESPONSE_TMP=$(mktemp)
trap "rm -f '$RESPONSE_TMP'" EXIT

while true; do
    OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null || echo "0")
    API_URL="https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?timeout=30&offset=${OFFSET}"

    if ! curl -s --max-time 35 -o "$RESPONSE_TMP" "$API_URL" 2>/dev/null; then
        echo "[$(date)] curl failed, reconnecting in 5s..." >&2
        sleep 5
        continue
    fi

    if [ ! -s "$RESPONSE_TMP" ]; then
        echo "[$(date)] Empty response, reconnecting in 5s..." >&2
        sleep 5
        continue
    fi

    while IFS='|' read -r CHAT_ID UPDATE_ID SAFE_TEXT; do
        [ -z "$UPDATE_ID" ] && continue
        # Restore | from \x01
        MSG_TEXT="${SAFE_TEXT//$'\x01'/|}"
        MSG_ID="telegram_${UPDATE_ID}"
        TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S%:z")

        echo "[$(date)] Received from chat $CHAT_ID: $MSG_TEXT" >&2

        # Record chat_id on first message
        CURRENT_CHAT_ID=$(grep 'telegram_chat_id:' "$SETTINGS" | awk '{print $2}' | tr -d '"')
        if [ -z "$CURRENT_CHAT_ID" ] && [ -n "$CHAT_ID" ]; then
            record_chat_id "$CHAT_ID"
        fi

        if ! append_ntfy_inbox "$MSG_ID" "$TIMESTAMP" "$MSG_TEXT"; then
            echo "[$(date)] WARNING: failed to append inbox entry" >&2
            continue
        fi

        bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun \
            "Telegramから新しいメッセージ受信。queue/ntfy_inbox.yaml を確認し処理せよ。" \
            ntfy_received telegram_listener

    done < <(process_response "$RESPONSE_TMP" "$OFFSET_FILE")

done
