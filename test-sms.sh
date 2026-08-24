#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# OpenPayUPI Termux — Test SMS Simulator
# Use this to verify that your Termux phone can communicate with OpenPayUPI Gateway.
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: config.env not found. Please run install.sh first."
  exit 1
fi

source "$CONFIG_FILE"

echo "=== OpenPayUPI SMS Simulation Test ==="
echo "Gateway: $GATEWAY_URL"
echo "Device:  $DEVICE_NAME"
echo ""

read -p "Enter test amount (e.g. 100.07): " TEST_AMOUNT
TEST_AMOUNT="${TEST_AMOUNT:-100.07}"

read -p "Enter 12-digit UTR (or press Enter for random): " TEST_UTR
if [ -z "$TEST_UTR" ]; then
  TEST_UTR=$(shuf -i 100000000000-999999999999 -n 1 2>/dev/null || echo "4321$(date +%s)")
fi

FAKE_SMS="Dear Customer, your A/C has been credited with Rs.$TEST_AMOUNT on $(date +%d-%b-%y) by UPI ref no $TEST_UTR - Bank"

echo ""
echo "Sending fake SMS to Gateway:"
echo "Body: $FAKE_SMS"
echo ""

PAYLOAD=$(jq -n \
  --arg amt "$TEST_AMOUNT" \
  --arg utr "$TEST_UTR" \
  --arg raw "$FAKE_SMS" \
  --arg dev "$DEVICE_NAME" \
  '{amount: ($amt | tonumber), utr: $utr, rawText: $raw, deviceName: $dev}')

curl -i -X POST "$GATEWAY_URL/api/v1/webhook/sms" \
  -H "Content-Type: application/json" \
  -H "X-Device-Secret: $DEVICE_SECRET" \
  -d "$PAYLOAD"

echo ""
echo ""
echo "Test completed."
