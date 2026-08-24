# 📱 OpenPayUPI — Termux SMS Forwarder

Turn any Android phone into an automated UPI Payment Interceptor and gateway node.

---

## ⚡ Quick Start (1-Line Install in Termux)

Open the **Termux** app on your Android phone and paste this single command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<YOUR_GITHUB_USER>/<REPO_NAME>/main/termux-forwarder/install.sh)
```

*(Replace `<YOUR_GITHUB_USER>/<REPO_NAME>` with your GitHub repo details after pushing)*

Or if copying directly onto the device:
```bash
pkg update && pkg install -y git
git clone https://github.com/<YOUR_GITHUB_USER>/<REPO_NAME>.git
cd <REPO_NAME>/termux-forwarder
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

- **Start interceptor manually**:
  ```bash
  ~/openpayupi-termux/start.sh
  ```
- **Simulate / Test a payment SMS**:
  ```bash
  ~/openpayupi-termux/test-sms.sh
  ```
- **Edit gateway settings**:
  ```bash
  nano ~/openpayupi-termux/config.env
  ```
