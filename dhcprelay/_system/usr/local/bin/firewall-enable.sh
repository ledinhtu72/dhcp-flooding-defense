#!/usr/bin/env bash
# =============================================================================
# firewall-enable.sh - Kích hoạt tường lửa nftables chống DHCP Flooding trên Relay
# Thiết kế an toàn:
#   - Tạo bảng riêng (table inet dhcp_defense & table netdev dhcp_defense_ingress)
#   - TUYỆT ĐỐI KHÔNG dùng 'nft flush ruleset' hay 'iptables -F'
#   - Áp dụng tại điểm thực tế gói tin đi qua trên dhcprelay:
#       + Hook ingress trên EXTERNAL_IF (eth1) để đếm tổng gói DHCP broadcast đến
#       + Hook output trên INTERNAL_IF (eth0) để lọc gói DHCP Relay chuyển tới Server
# =============================================================================
set -euo pipefail

RATE_LIMIT="${1:-2/second}"
BURST_PACKETS="${2:-3}"
TRUSTED_CLIENT_MAC_HEX="0x02420a0a0032"
DHCP_SERVER_IP="192.168.0.100"
STATUS_LOG="/var/log/firewall_status.log"

INTERNAL_IF=$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.0\./ {print $2; exit}')
EXTERNAL_IF=$(ip -o -4 addr show | awk '$4 ~ /^10\.10\.0\./ {print $2; exit}')
[[ -z "$INTERNAL_IF" ]] && INTERNAL_IF="eth0"
[[ -z "$EXTERNAL_IF" ]] && EXTERNAL_IF="eth1"

# Chỉ xóa bảng riêng của bài lab nếu đã tồn tại (Idempotent, không ảnh hưởng hệ thống)
sudo nft delete table inet dhcp_defense 2>/dev/null || true
sudo nft delete table netdev dhcp_defense_ingress 2>/dev/null || true

# 1. Bảng netdev giám sát tổng lưu lượng DHCP Broadcast đi vào từ EXTERNAL_NET (eth1)
sudo nft add table netdev dhcp_defense_ingress
sudo nft "add chain netdev dhcp_defense_ingress external_rx { type filter hook ingress device \"${EXTERNAL_IF}\" priority -450; policy accept; }"
sudo nft "add rule netdev dhcp_defense_ingress external_rx udp sport 68 udp dport 67 counter accept comment \"external_dhcp_rx\""

# 2. Bảng inet kiểm soát & chặn DHCP Flooding tại hook output trước khi dhcrelay đẩy ra INTERNAL_IF (eth0)
sudo nft add table inet dhcp_defense
sudo nft "add chain inet dhcp_defense relay_out { type filter hook output priority 0; policy accept; }"

# Rule 1: Ưu tiên cho phép Client hợp lệ đã xác thực MAC trong trường BOOTP chaddr (@th,288,48 = 02:42:0a:0a:00:32)
# với ngưỡng an toàn 10/second để Client hợp lệ luôn nhận được IP ngay cả khi mạng đang bị bão gói tin.
sudo nft "add rule inet dhcp_defense relay_out oifname \"${INTERNAL_IF}\" ip daddr ${DHCP_SERVER_IP} udp dport 67 @th,288,48 ${TRUSTED_CLIENT_MAC_HEX} limit rate 10/second burst 10 packets counter accept comment \"trusted_client_accept\""

# Rule 2: Giới hạn tốc độ (Rate-limit) nghiêm ngặt cho các yêu cầu DHCP từ MAC lạ (tối đa ${RATE_LIMIT}, burst ${BURST_PACKETS})
sudo nft "add rule inet dhcp_defense relay_out oifname \"${INTERNAL_IF}\" ip daddr ${DHCP_SERVER_IP} udp dport 67 limit rate ${RATE_LIMIT} burst ${BURST_PACKETS} packets counter accept comment \"dhcp_rate_limit_accept\""

# Rule 3: Ghi log có kiểm soát (tối đa 5 bản ghi/phút để chống log flood) cho các gói vượt ngưỡng
sudo nft "add rule inet dhcp_defense relay_out oifname \"${INTERNAL_IF}\" ip daddr ${DHCP_SERVER_IP} udp dport 67 limit rate 5/minute burst 5 packets counter log prefix \"[NFT-DHCP-FLOOD-DROP] \" comment \"dhcp_flood_log\""

# Rule 4: Chặn (Drop) toàn bộ gói tin DHCP Flooding vượt ngưỡng và đếm bộ đếm (counter)
sudo nft "add rule inet dhcp_defense relay_out oifname \"${INTERNAL_IF}\" ip daddr ${DHCP_SERVER_IP} udp dport 67 counter drop comment \"dhcp_flood_drop\""

echo "=================================================================="
echo "[OK] ĐÃ BẬT TƯỜNG LỬA NFTABLES PHÒNG THỦ DHCP FLOODING TRÊN RELAY"
echo "    - Giao diện ngoài (EXTERNAL) : ${EXTERNAL_IF} (10.10.0.1)"
echo "    - Giao diện trong (INTERNAL) : ${INTERNAL_IF} (192.168.0.1 -> ${DHCP_SERVER_IP})"
echo "    - Ngưỡng Rate-Limit          : ${RATE_LIMIT} (burst ${BURST_PACKETS} packets)"
echo "=================================================================="

/usr/local/bin/firewall-status.sh

