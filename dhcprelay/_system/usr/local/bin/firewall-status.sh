#!/usr/bin/env bash
# =============================================================================
# firewall-status.sh - Kiểm tra trạng thái và bộ đếm (counters) của nftables
# =============================================================================
set -euo pipefail

STATUS_LOG="/var/log/firewall_status.log"
sudo touch "$STATUS_LOG"
sudo chmod 666 "$STATUS_LOG"

if ! sudo nft list table inet dhcp_defense >/dev/null 2>&1; then
    echo "=================================================================="
    echo "[Trạng thái] Tường lửa nftables (table inet dhcp_defense): ĐANG TẮT (INACTIVE)"
    echo "=================================================================="
    exit 0
fi

INGRESS_OUT=$(sudo nft list table netdev dhcp_defense_ingress 2>/dev/null || true)
DEFENSE_OUT=$(sudo nft list table inet dhcp_defense 2>/dev/null || true)

EXT_RX_PKTS=$(echo "$INGRESS_OUT" | awk '/external_dhcp_rx/ {for(i=1;i<=NF;i++) if($i=="counter" && $(i+1)=="packets") print $(i+2)}' | head -n1)
TRUSTED_PKTS=$(echo "$DEFENSE_OUT" | awk '/trusted_client_accept/ {for(i=1;i<=NF;i++) if($i=="counter" && $(i+1)=="packets") print $(i+2)}' | head -n1)
RATELIM_PKTS=$(echo "$DEFENSE_OUT" | awk '/dhcp_rate_limit_accept/ {for(i=1;i<=NF;i++) if($i=="counter" && $(i+1)=="packets") print $(i+2)}' | head -n1)
DROPPED_PKTS=$(echo "$DEFENSE_OUT" | awk '/dhcp_flood_drop/ {for(i=1;i<=NF;i++) if($i=="counter" && $(i+1)=="packets") print $(i+2)}' | head -n1)
DROPPED_BYTES=$(echo "$DEFENSE_OUT" | awk '/dhcp_flood_drop/ {for(i=1;i<=NF;i++) if($i=="bytes") print $(i+1)}' | head -n1)

EXT_RX_PKTS="${EXT_RX_PKTS:-0}"
TRUSTED_PKTS="${TRUSTED_PKTS:-0}"
RATELIM_PKTS="${RATELIM_PKTS:-0}"
DROPPED_PKTS="${DROPPED_PKTS:-0}"
DROPPED_BYTES="${DROPPED_BYTES:-0}"
TOTAL_ACCEPT=$((TRUSTED_PKTS + RATELIM_PKTS))

{
    echo "=================================================================="
    echo "BÁO CÁO BỘ ĐẾM TƯỜNG LỬA NFTABLES (DHCP FLOODING DEFENSE)"
    echo "Thời gian cập nhật: $(date -Iseconds)"
    echo "NFT_DEFENSE_ACTIVE=TRUE"
    echo "------------------------------------------------------------------"
    echo "1. Tổng gói DHCP nhận từ EXTERNAL_NET (external_dhcp_rx) : ${EXT_RX_PKTS} packets"
    echo "2. Gói DHCP hợp lệ từ Client (trusted_client_accept)     : ${TRUSTED_PKTS} packets"
    echo "3. Gói DHCP qua ngưỡng Rate-Limit (dhcp_rate_limit_accept): ${RATELIM_PKTS} packets"
    echo "4. Tổng gói DHCP cho phép chuyển tới Server (TOTAL_ACCEPT): ${TOTAL_ACCEPT} packets"
    echo "5. Gói DHCP Flooding bị CHẶN (dhcp_flood_drop)           : ${DROPPED_PKTS} packets (${DROPPED_BYTES} bytes)"
    if [[ "$DROPPED_PKTS" -gt 0 ]]; then
        echo "NFT_DEFENSE_VERIFIED_DROPS=TRUE (dropped_packets=${DROPPED_PKTS})"
    fi
    echo "------------------------------------------------------------------"
    echo "CHI TIẾT RULESET NFTABLES HIỆN TẠI:"
    echo "$INGRESS_OUT"
    echo "$DEFENSE_OUT"
    echo "=================================================================="
} | tee "$STATUS_LOG"

sudo chmod 666 "$STATUS_LOG" 2>/dev/null || true
cp -f "$STATUS_LOG" /home/ubuntu/.local/result/firewall_status.log 2>/dev/null || true
