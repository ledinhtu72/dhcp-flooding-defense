#!/usr/bin/env bash
# =============================================================================
# status_dhcp.sh - Kiểm tra trạng thái dịch vụ ISC DHCP Server & dung lượng Pool Lease
# Pool cấu hình trong /etc/dhcp/dhcpd.conf: 10.10.0.100 -> 10.10.0.130 (Tổng: 31 IP)
# =============================================================================
set -euo pipefail

LEASE_FILE="/var/lib/dhcp/dhcpd.leases"
STATUS_LOG="/var/log/dhcp_server_status.log"
POOL_TOTAL=31

sudo touch "$LEASE_FILE" "$STATUS_LOG"
sudo chmod 666 "$STATUS_LOG"

ACTIVE_IPS=$(awk '
    /^lease 10\.10\.0\./ { ip=$2 }
    /binding state active/ { active[ip]=1 }
    /hardware ethernet/ { mac[ip]=$3 }
    END {
        for (i in active) {
            gsub(";", "", mac[i])
            print i, (mac[i] ? mac[i] : "unknown")
        }
    }
' "$LEASE_FILE" | sort -V)

if [[ -z "$ACTIVE_IPS" ]]; then
    ACTIVE_COUNT=0
else
    ACTIVE_COUNT=$(echo "$ACTIVE_IPS" | wc -l)
fi
FREE_COUNT=$((POOL_TOTAL - ACTIVE_COUNT))
[[ "$FREE_COUNT" -lt 0 ]] && FREE_COUNT=0

DHCPD_PID=$(pgrep -f "/usr/sbin/dhcpd" | head -n1 || true)
if [[ -n "$DHCPD_PID" ]]; then
    SVC_STATE="RUNNING (PID $DHCPD_PID)"
else
    SVC_STATE="STOPPED"
fi

{
    echo "=================================================================="
    echo "TRẠNG THÁI MÁY CHỦ ISC DHCP SERVER (192.168.0.100)"
    echo "Thời gian kiểm tra : $(date -Iseconds)"
    echo "Trạng thái dịch vụ : ${SVC_STATE}"
    echo "Dải Pool cấp phát  : 10.10.0.100 - 10.10.0.130 (Tổng: ${POOL_TOTAL} địa chỉ IP)"
    echo "Số Lease đang cấp  : ${ACTIVE_COUNT} / ${POOL_TOTAL}"
    echo "Số IP còn trống    : ${FREE_COUNT} / ${POOL_TOTAL}"
    echo "------------------------------------------------------------------"
    echo "Danh sách các IP đang được cấp phát (Active Leases):"
    if [[ "$ACTIVE_COUNT" -gt 0 ]]; then
        echo "$ACTIVE_IPS" | awk '{printf "  - IP: %-15s | MAC: %s\n", $1, $2}'
    else
        echo "  (Chưa có lease nào đang hoạt động)"
    fi
    echo "=================================================================="
} | tee "$STATUS_LOG"
