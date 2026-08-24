# 📱 OpenPayUPI — Termux SMS Forwarder

Turn any Android phone into an automated UPI Payment Interceptor and gateway node.

---

## ⚡ Quick Start (1-Line Install in Termux)

Open the **Termux** app on your Android phone and paste this single command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/swikki099-ui/sms-receive-upi/main/termux-forwarder/install.sh)
```



Or if copying directly onto the device:
```bash
pkg update && pkg install -y git
git clone https://github.com/swikki099-ui/sms-receive-upi.git
cd sms-receive-upi
chmod +x install.sh
./install.sh
```

---

## 📋 Prerequisites on Android

1. **Install Termux**: Download from [F-Droid](https://f-droid.org/en/packages/com.termux/) (do NOT use Play Store version, it is deprecated).
2. **Install Termux:API**: Download from [F-Droid](https://f-droid.org/en/packages/com.termux.api/).
3. **Grant Permissions**: Open Android Settings → Apps → **Termux:API** → Permissions → Allow **SMS** (Read SMS).
4. **Disable Battery Optimization**: Android Settings → Battery → Apps → Termux & Termux:API → Set to **Unrestricted / Don't optimize** so it keeps running in the background.

---

## 🛠 Features

- **Real-Time SMS Interception**: Scans incoming SMS for PhonePe, GPay, Paytm, BHIM, and bank credit alerts.
- **Smart Regex Parser**: Automatically pulls out the 12-digit UTR and exact decimal amount (e.g. `₹100.07`).
- **Heartbeat & Telemetry**: Sends ping every 30 seconds with battery level to keep device marked as `ONLINE` in the Admin Dashboard.
- **Auto-Deduplication**: Tracks processed SMS IDs so no transaction is ever submitted twice.
- **Auto-Start on Boot**: Integrates with `termux-boot` if installed.

---

## 🕹 Manual Commands

After installation, these commands work from **any directory** (installed to `$PREFIX/bin`):

- **Start interceptor**:
  ```bash
  start.sh
  ```
- **Simulate / Test a payment SMS**:
  ```bash
  test-sms.sh
  ```
- **Edit gateway settings**:
  ```bash
  nano ~/openpayupi-termux/config.env
  ```

> Prefer the full paths? They still work: `~/openpayupi-termux/start.sh`

---

## 🔧 Troubleshooting

### Device not showing as ONLINE in the Admin Dashboard
The device sends a heartbeat every **30 seconds**; the dashboard marks it OFFLINE after **90 seconds** of silence. If it never appears:

1. **Verify your Device Secret is active** — Admin Panel → API Keys → your DEVICE key must not be revoked.
2. **Test connectivity** from Termux:
   ```bash
   source ~/openpayupi-termux/config.env
   curl -i --max-time 15 -X POST "$GATEWAY_URL/api/v1/device/heartbeat" \
     -H "Content-Type: application/json" \
     -H "X-Device-Secret: $DEVICE_SECRET" \
     -d "{\"deviceName\": \"$DEVICE_NAME\", \"metadata\": {\"battery\": 100}}"
   ```
   A `200 OK` response means telemetry works — refresh the dashboard within 90 seconds.
3. `401 Unauthorized` → wrong or revoked `DEVICE_SECRET` in `config.env`.
4. Connection refused / timeout → check `GATEWAY_URL` (no trailing slash) and that the gateway is publicly reachable.
5. Keep the Termux session alive: disable battery optimization for Termux (see Prerequisites) and use `start.sh` (it acquires a wake lock).
