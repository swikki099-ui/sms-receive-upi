#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# OpenPayUPI Termux Agent — Automated Setup & Installer
# One-line execution:
#   bash <(curl -fsSL https://raw.githubusercontent.com/<YOUR_USER>/<REPO>/main/install.sh)
# ==============================================================================

set -e

DIR="$HOME/openpayupi-termux"
CONFIG_FILE="$DIR/config.env"

echo -e "\033[1;33m"
cat << 'EOF'
  ___                    ____              _   _ ____ ___ 
 / _ \ _ __   ___ _ __ |  _ \ __ _ _   _| | | |  _ \_ _|
| | | | '_ \ / _ \ '_ \| |_) / _` | | | | | | | |_) | | 
| |_| | |_) |  __/ | | |  __/ (_| | |_| | |_| |  __/| | 
 \___/| .__/ \___|_| |_|_|   \__,_|\__, |\___/|_|  |___|
      |_|                          |___/                
         Termux SMS Interceptor & Gateway Forwarder
EOF
echo -e "\033[0m"

echo -e "\033[1;36m[1/4] Checking and installing dependencies...\033[0m"
pkg update -y
pkg install -y termux-api jq curl grep

echo -e "\033[1;36m[2/4] Setting up directories...\033[0m"
mkdir -p "$DIR"

# Download or create the listener script
cat << 'EOF' > "$DIR/listener.sh"
#!/data/data/com.termux/files/usr/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$DIR/config.env"
PROCESSED_FILE="$DIR/.processed_sms.log"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: config.env not found. Run ./install.sh first."
  exit 1
fi

source "$CONFIG_FILE"

touch "$PROCESSED_FILE"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN} OpenPayUPI SMS Interceptor Running                 ${NC}"
echo -e " Gateway: ${CYAN}$GATEWAY_URL${NC}"
echo -e " Device:  ${CYAN}$DEVICE_NAME${NC}"
echo -e "${GREEN}====================================================${NC}"

# Battery info helper
get_battery() {
  termux-battery-status 2>/dev/null | jq -r '.percentage // 100'
}

# Heartbeat loop counter
HB_COUNTER=0

while true; do
  # ── Send Heartbeat every 30 seconds (every 6 loops of 5s) ───
  if [ "$HB_COUNTER" -le 0 ]; then
    BATTERY=$(get_battery)
    curl -s --max-time 10 -X POST "$GATEWAY_URL/api/v1/device/heartbeat" \
      -H "Content-Type: application/json" \
      -H "X-Device-Secret: $DEVICE_SECRET" \
      -d "{\"deviceName\": \"$DEVICE_NAME\", \"metadata\": {\"battery\": $BATTERY}}" > /dev/null 2>&1 || true
    HB_COUNTER=6
  fi
  HB_COUNTER=$((HB_COUNTER - 1))

  # ── Fetch latest 5 SMS messages ─────────────────────────────
  SMS_JSON=$(termux-sms-list -l 5 -t inbox 2>/dev/null || echo "[]")

  # Loop through returned messages
  echo "$SMS_JSON" | jq -c '.[]' 2>/dev/null | while read -r SMS; do
    SMS_ID=$(echo "$SMS" | jq -r '._id // empty')
    BODY=$(echo "$SMS" | jq -r '.body // empty')
    SENDER=$(echo "$SMS" | jq -r '.number // empty')
    DATE=$(echo "$SMS" | jq -r '.received // empty')

    if [ -z "$SMS_ID" ] || [ -z "$BODY" ]; then
      continue
    fi

    # Check if already processed (literal match, no regex interpretation)
    if grep -qxF "$SMS_ID" "$PROCESSED_FILE" 2>/dev/null; then
      continue
    fi

    # Check if message contains UPI / Bank / Payment keywords
    LOWER_BODY=$(echo "$BODY" | tr '[:upper:]' '[:lower:]')
    if echo "$LOWER_BODY" | grep -qE "upi|credited|received|deposited|vpa|utr|inr|rs\.?"; then
      
      # Extract 12-digit UTR preceded by a reference label (utr/ref/txn)
      UTR=$(echo "$BODY" | grep -oiP '\b(?:utr|ref(?:erence)?(?:\s*no)?|txn|upi\s*ref)\b[ :#.\/\-]*([0-9]{12})\b' | grep -oE '[0-9]{12}' | head -n 1)

      # Fallback: any standalone 12 digit number
      if [ -z "$UTR" ]; then
        UTR=$(echo "$BODY" | grep -oE '\b[0-9]{12}\b' | head -n 1)
      fi

      # Extract Amount (supports: Rs. 100.05, INR 50.00, Rs 500, ₹120.45,
      # credited by 200.00). Match the full currency+amount token first,
      # THEN strip thousands separators — otherwise comma-formatted
      # amounts like 1,50,000 would be truncated at the first group.
      AMOUNT=$(echo "$BODY" | grep -oP '(?i)\b(?:rs\.?|inr\b|₹|credited\s+by\s+|received\s+)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?' | head -n 1 | tr -d ',' | grep -oE '[0-9]+(\.[0-9]{1,2})?' | head -n 1)

      if [ -n "$AMOUNT" ] && [ -n "$UTR" ]; then
        echo -e "${YELLOW}[UPI DETECTED]${NC} Amount: ₹$AMOUNT | UTR: $UTR | Sender: $SENDER"

        # Forward payload to OpenPayUPI Webhook
        PAYLOAD=$(jq -n \
          --arg amt "$AMOUNT" \
          --arg utr "$UTR" \
          --arg raw "$BODY" \
          --arg dev "$DEVICE_NAME" \
          '{amount: ($amt | tonumber), utr: $utr, rawText: $raw, deviceName: $dev}')

        RES=$(curl -s --max-time 15 -w "\n%{http_code}" -X POST "$GATEWAY_URL/api/v1/webhook/sms" \
          -H "Content-Type: application/json" \
          -H "X-Device-Secret: $DEVICE_SECRET" \
          -d "$PAYLOAD")

        HTTP_CODE=$(echo "$RES" | tail -n 1)
        RES_BODY=$(echo "$RES" | sed '$d')

        case "$HTTP_CODE" in
          200)
            echo -e "${GREEN}[PAID CONFIRMED]${NC} Order reconciled successfully: $RES_BODY"
            echo "$SMS_ID" >> "$PROCESSED_FILE"
            ;;
          4*)
            # Permanent rejection (invalid body, auth, no matching order,
            # conflict) — retrying will not help, so record and move on.
            echo -e "${RED}[GATEWAY RESPONSE ${HTTP_CODE}]${NC} $RES_BODY"
            echo "$SMS_ID" >> "$PROCESSED_FILE"
            ;;
          *)
            # Transient failure (5xx / timeout / network error). Do NOT
            # record the SMS so it is retried on the next poll cycle.
            echo -e "${RED}[TRANSIENT FAILURE ${HTTP_CODE}]${NC} Will retry: $RES_BODY"
            ;;
        esac
      fi
    fi

    # Limit log size to last 500 IDs
    if [ $(wc -l < "$PROCESSED_FILE" 2>/dev/null || echo 0) -gt 500 ]; then
      tail -n 300 "$PROCESSED_FILE" > "$PROCESSED_FILE.tmp" && mv "$PROCESSED_FILE.tmp" "$PROCESSED_FILE"
    fi
  done

  sleep 5
done
EOF

chmod +x "$DIR/listener.sh"

echo -e "\033[1;36m[3/4] Configuring Gateway Credentials...\033[0m"

# Prompt user for configuration if not existing
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
  echo -e "\033[1;32mExisting configuration found ($CONFIG_FILE)\033[0m"
  echo -e "Gateway URL: $GATEWAY_URL"
  echo -e "Device Name: $DEVICE_NAME"
  read -p "Do you want to re-configure? (y/N): " RECONF
  if [[ "$RECONF" =~ ^[Yy]$ ]]; then
    rm -f "$CONFIG_FILE"
  fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  read -p "Enter OpenPayUPI Gateway URL (e.g., https://pay.yourdomain.com): " USER_GATEWAY
  USER_GATEWAY="${USER_GATEWAY%/}"
  
  read -p "Enter Device Secret (from Admin -> API Keys -> DEVICE key): " USER_SECRET
  
  DEFAULT_NAME=$(getprop ro.product.model 2>/dev/null || hostname 2>/dev/null || echo "Termux-Device")
  read -p "Enter Device Name [$DEFAULT_NAME]: " USER_DEVNAME
  USER_DEVNAME="${USER_DEVNAME:-$DEFAULT_NAME}"

  cat << EOF > "$CONFIG_FILE"
GATEWAY_URL="$USER_GATEWAY"
DEVICE_SECRET="$USER_SECRET"
DEVICE_NAME="$USER_DEVNAME"
EOF
  echo -e "\033[1;32m✓ Configuration saved to $CONFIG_FILE\033[0m"
fi

# Create start launcher
cat << 'EOF' > "$DIR/start.sh"
#!/data/data/com.termux/files/usr/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
termux-wake-lock
exec "$DIR/listener.sh"
EOF
chmod +x "$DIR/start.sh"

# ── Register global commands so `start.sh` / `test-sms.sh` work from
#    any directory (Termux puts $PREFIX/bin on PATH) ────────────────
BIN_DIR="${PREFIX}/bin"
mkdir -p "$BIN_DIR"

for CMD in start.sh test-sms.sh; do
  cat << EOF > "$BIN_DIR/$CMD"
#!/data/data/com.termux/files/usr/bin/bash
# OpenPayUPI launcher — installed by install.sh
exec "$DIR/$CMD" "\$@"
EOF
  chmod +x "$BIN_DIR/$CMD"
done
echo -e "\033[1;32m✓ Global commands installed: start.sh, test-sms.sh\033[0m"

# Setup auto-start on boot (if termux-boot installed)
BOOT_DIR="$HOME/.termux/boot"
if [ -d "$BOOT_DIR" ]; then
  cp "$DIR/start.sh" "$BOOT_DIR/openpayupi-listener.sh"
  chmod +x "$BOOT_DIR/openpayupi-listener.sh"
  echo -e "\033[1;32m✓ Termux Boot auto-start configured!\033[0m"
fi

echo -e "\033[1;32m"
echo "============================================================"
echo "  OpenPayUPI Termux Setup Complete!"
echo "============================================================"
echo -e "\033[0m"
echo "To start listening for payments right now, run:"
echo -e "  \033[1;33mstart.sh\033[0m"
echo ""
echo "(works from any directory — test with: test-sms.sh)"
echo ""
echo "Important: Ensure Termux:API app is installed on Android"
echo "and SMS permissions are granted."
echo ""
read -p "Start the interceptor now? (Y/n): " START_NOW
if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
  "$DIR/start.sh"
fi
