#!/usr/bin/env bash
# Telegram Bot 送信スクリプト
# 使い方: bash scripts/telegram_send.sh "メッセージ本文"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"

TOKEN=$(grep 'telegram_bot_token:' "$SETTINGS" | awk '{print $2}' | tr -d '"')
CHAT_ID=$(grep 'telegram_chat_id:' "$SETTINGS" | awk '{print $2}' | tr -d '"')

if [ -z "$CHAT_ID" ]; then
  echo "telegram_chat_id not configured in settings.yaml" >&2
  exit 1
fi

curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\": \"${CHAT_ID}\", \"text\": \"$1\"}" > /dev/null
