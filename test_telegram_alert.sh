#!/usr/bin/env bash
set -e

# Verify Environment Variables
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "❌ Error: Both TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set in your environment."
    echo ""
    echo "Usage:"
    echo "  export TELEGRAM_BOT_TOKEN=\"123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ\""
    echo "  export TELEGRAM_CHAT_ID=\"123456789\""
    echo "  bash test_telegram_alert.sh"
    exit 1
fi

echo "🚀 Testing Telegram Bot credentials..."

RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "parse_mode=Markdown" \
    -d "text=🤖 *Ella MCP Agent Server - Telegram Alert Verification*%0A%0AEverything is configured correctly! You will receive real-time operational alerts here.")

if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "✅ Success! Test alert delivered to Telegram."
else
    echo "❌ Failed to send alert. Telegram API response:"
    echo "$RESPONSE"
    exit 1
fi
