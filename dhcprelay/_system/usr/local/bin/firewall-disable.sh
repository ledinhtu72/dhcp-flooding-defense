#!/usr/bin/env bash
# =============================================================================
# firewall-disable.sh - Tắt và rollback chính xác chỉ các rule nftables của bài lab
# =============================================================================
set -euo pipefail

STATUS_LOG="/var/log/firewall_status.log"

echo "[*] Đang gỡ bỏ các bảng nftables của bài lab (dhcp_defense & dhcp_defense_ingress)..."
sudo nft delete table inet dhcp_defense 2>/dev/null || true
sudo nft delete table netdev dhcp_defense_ingress 2>/dev/null || true

echo "[OK] Đã tắt tường lửa nftables của bài lab và khôi phục trạng thái ban đầu."
echo "NFT_DEFENSE_DISABLED at $(date -Iseconds)" | sudo tee -a "$STATUS_LOG" >/dev/null
sudo chmod 666 "$STATUS_LOG" 2>/dev/null || true

