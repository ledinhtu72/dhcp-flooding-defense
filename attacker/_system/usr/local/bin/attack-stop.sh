#!/usr/bin/env bash
# =============================================================================
# attack-stop.sh - Dừng khẩn cấp mọi tiến trình mô phỏng DHCP Flooding trên Attacker
# =============================================================================
set -euo pipefail

PID_FILE="/var/run/dhcp_attack.pid"
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        sudo kill -TERM "$PID" 2>/dev/null || true
    fi
    sudo rm -f "$PID_FILE"
fi

sudo pkill -f "attack-controlled.sh" 2>/dev/null || true
sudo pkill -f "dhcp_flood_scapy.py" 2>/dev/null || true
sudo pkill -f "yersinia" 2>/dev/null || true

echo "[OK] Đã dừng toàn bộ tiến trình tấn công DHCP Flooding trên Attacker."

