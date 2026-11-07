#!/usr/bin/env bash
# =============================================================================
# reset-leases.sh - Sao lưu và làm sạch bảng dhcpd.leases trên DHCP Server
# Dùng trước khi chạy Kịch bản D (Flooding sau khi bật nftables) để so sánh công bằng
# =============================================================================
set -euo pipefail

LEASE_FILE="/var/lib/dhcp/dhcpd.leases"
BACKUP_DIR="/var/backups/dhcp-lab"
sudo mkdir -p "$BACKUP_DIR"

TS=$(date +%Y%m%d_%H%M%S)
if [[ -f "$LEASE_FILE" ]]; then
    sudo cp -f "$LEASE_FILE" "${BACKUP_DIR}/dhcpd.leases.bak.${TS}"
    echo "[*] Đã sao lưu file lease cũ tại: ${BACKUP_DIR}/dhcpd.leases.bak.${TS}"
fi

sudo pkill -f "/usr/sbin/dhcpd" 2>/dev/null || true
sleep 1
sudo truncate -s 0 "$LEASE_FILE"
sudo rm -f "${LEASE_FILE}~" /var/run/dhcpd.pid
sudo chown dhcpd:dhcpd "$LEASE_FILE" 2>/dev/null || true
sudo /usr/sbin/dhcpd -4 -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid eth0

echo "[OK] Đã làm mới bảng cấp phát DHCP Pool (31/31 IP trống) và khởi động lại dhcpd."
/usr/local/bin/status_dhcp.sh

