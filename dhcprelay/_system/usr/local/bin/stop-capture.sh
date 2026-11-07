#!/usr/bin/env bash
# =============================================================================
# stop-capture.sh - Dừng bắt gói tin DHCP, kiểm tra tính toàn vẹn và phân quyền
# =============================================================================
set -euo pipefail

CAPTURE_DIR="/home/ubuntu/captures"
LOG_CAPTURE_DIR="/var/log/captures"
STATUS_LOG="${LOG_CAPTURE_DIR}/capture_status.log"
PID_FILE="/var/run/dhcp_capture.pid"
META_FILE="/var/run/dhcp_capture.meta"

sudo mkdir -p "$CAPTURE_DIR" "$LOG_CAPTURE_DIR"

if [[ -f "$PID_FILE" ]]; then
    CAP_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$CAP_PID" ]] && kill -0 "$CAP_PID" 2>/dev/null; then
        echo "[*] Đang dừng tiến trình bắt gói tin (PID: $CAP_PID)..."
        sudo kill -INT "$CAP_PID" 2>/dev/null || sudo kill -TERM "$CAP_PID" 2>/dev/null || true
        sleep 1
    fi
    sudo rm -f "$PID_FILE"
fi

# Dừng mọi tiến trình dumpcap/tshark chạy nền còn sót nếu có
sudo pkill -INT -f "dumpcap.*udp port 67" 2>/dev/null || true
sudo pkill -INT -f "tshark.*udp port 67" 2>/dev/null || true
sleep 1

# Đồng bộ normal.pcapng <-> normal_dhcp.pcapng
if [[ -f "${CAPTURE_DIR}/normal.pcapng" && ! -f "${CAPTURE_DIR}/normal_dhcp.pcapng" ]]; then
    sudo cp -f "${CAPTURE_DIR}/normal.pcapng" "${CAPTURE_DIR}/normal_dhcp.pcapng"
elif [[ -f "${CAPTURE_DIR}/normal_dhcp.pcapng" && ! -f "${CAPTURE_DIR}/normal.pcapng" ]]; then
    sudo cp -f "${CAPTURE_DIR}/normal_dhcp.pcapng" "${CAPTURE_DIR}/normal.pcapng"
fi

# Phân quyền đọc/ghi cho user ubuntu và Wireshark/TShark/Zeek
sudo chown -R ubuntu:ubuntu "$CAPTURE_DIR" 2>/dev/null || true
sudo chmod 777 "$CAPTURE_DIR" 2>/dev/null || true
sudo chmod 666 "$CAPTURE_DIR"/*.pcap* 2>/dev/null || true

# Đồng bộ bản sao sang /var/log/captures phục vụ kiểm tra và lưu trữ
sudo cp -f "$CAPTURE_DIR"/*.pcap* "$LOG_CAPTURE_DIR"/ 2>/dev/null || true
sudo chmod 666 "$LOG_CAPTURE_DIR"/*.pcap* 2>/dev/null || true

LAST_FILE=""
if [[ -f "$META_FILE" ]]; then
    LAST_FILE=$(awk -F= '/^FILE=/ {print $2}' "$META_FILE" 2>/dev/null || true)
fi

echo "=================================================================="
echo "[*] TRẠNG THÁI CÁC FILE PCAP HIỆN CÓ TRONG $CAPTURE_DIR:"
echo "=================================================================="

sudo truncate -s 0 "$STATUS_LOG"
COUNT_VALID=0

for f in "$CAPTURE_DIR"/*.pcapng "$CAPTURE_DIR"/*.pcap; do
    [[ -e "$f" ]] || continue
    bname=$(basename "$f")
    fsize=$(stat -c%s "$f" 2>/dev/null || echo 0)
    pkt_count=$(tshark -r "$f" 2>/dev/null | wc -l || echo 0)
    echo "  - $bname : ${fsize} bytes | ${pkt_count} gói tin DHCP"
    echo "CAPTURED: $bname size=${fsize} packets=${pkt_count}" | sudo tee -a "$STATUS_LOG" >/dev/null
done

if [[ -f "${CAPTURE_DIR}/normal_dhcp.pcapng" && -f "${CAPTURE_DIR}/attack_before.pcapng" && -f "${CAPTURE_DIR}/attack_after.pcapng" ]]; then
    echo "ALL_3_PCAPS_CAPTURED=TRUE" | sudo tee -a "$STATUS_LOG" >/dev/null
    echo "[OK] Đã thu thập đủ cả 3 file PCAPNG chuẩn: normal_dhcp.pcapng, attack_before.pcapng, attack_after.pcapng!"
fi

if [[ -n "$LAST_FILE" && -f "$LAST_FILE" ]]; then
    echo "------------------------------------------------------------------"
    echo "[*] Chi tiết nhanh file vừa bắt ($LAST_FILE):"
    tshark -r "$LAST_FILE" -Y "dhcp or bootp" | head -n 10 || true
fi
sudo chmod 666 "$STATUS_LOG" 2>/dev/null || true
echo "=================================================================="

