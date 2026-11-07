#!/usr/bin/env bash
# =============================================================================
# client-test.sh - Kiểm thử xin cấp phát IP động trên Client và đo thời gian phản hồi
# Cú pháp: client-test.sh [nhãn_kịch_bản]
# =============================================================================
set -euo pipefail

STAGE_LABEL="${1:-manual_test}"
IFACE=$(ip -o link show | awk -F': ' '/02:42:0a:0a:/ {print $2; exit}' | cut -d@ -f1)
[[ -z "$IFACE" ]] && IFACE="eth0"
TEST_LOG="/var/log/client_dhcp_test.log"

sudo touch "$TEST_LOG"
sudo chmod 666 "$TEST_LOG"

echo "=================================================================="
echo "[*] KIỂM THỬ XIN CẤP PHÁT IP TRÊN CLIENT (Kịch bản: $STAGE_LABEL)"
echo "    - Giao diện mạng: $IFACE"
echo "=================================================================="

echo "[1/3] Giải phóng địa chỉ IP hiện tại (dhclient -r $IFACE)..."
sudo dhclient -r "$IFACE" 2>/dev/null || true
sudo ip -4 addr flush dev "$IFACE" 2>/dev/null || true
sleep 1

echo "[2/3] Đang gửi yêu cầu xin cấp IP mới (timeout tối đa 10 giây)..."
START_MS=$(date +%s%3N)
if sudo timeout 10 dhclient -v "$IFACE" 2>&1 | tee /tmp/dhclient_last.out; then
    RC=0
else
    RC=$?
fi
END_MS=$(date +%s%3N)
ELAPSED_MS=$((END_MS - START_MS))

ASSIGNED_IP=$(ip -o -4 addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
GW_IP=$(ip route show default | awk '/default/ {print $3; exit}' || true)

echo "------------------------------------------------------------------"
if [[ -n "$ASSIGNED_IP" ]]; then
    echo "[OK] CLIENT NHẬN IP THÀNH CÔNG!"
    echo "    - Địa chỉ IP nhận được : $ASSIGNED_IP"
    echo "    - Default Gateway      : ${GW_IP:-10.10.0.1}"
    echo "    - Thời gian cấp phát   : ${ELAPSED_MS} ms"
    echo "CLIENT_DHCP_OK stage=${STAGE_LABEL} ip=${ASSIGNED_IP} gw=${GW_IP:-10.10.0.1} time_ms=${ELAPSED_MS}" | tee -a "$TEST_LOG"
else
    echo "[FAIL] CLIENT KHÔNG NHẬN ĐƯỢC IP (Timeout sau ${ELAPSED_MS} ms)!"
    echo "CLIENT_DHCP_FAIL stage=${STAGE_LABEL} rc=${RC} time_ms=${ELAPSED_MS}" | tee -a "$TEST_LOG"
fi
echo "=================================================================="

