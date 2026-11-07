#!/usr/bin/env bash
# =============================================================================
# start-capture.sh - Bắt gói tin DHCP (PCAPNG) có kiểm soát trên DHCP Relay
# Cú pháp: start-capture.sh <tên_file_hoặc_kịch_bản> [thời_gian_tối_đa_giây] [dung_lượng_tối_đa_KB]
# Ví dụ:   start-capture.sh normal_dhcp
#          start-capture.sh attack_before
#          start-capture.sh attack_after
# =============================================================================
set -euo pipefail

NAME="${1:-normal_dhcp}"
MAX_DURATION="${2:-120}"
MAX_FILESIZE_KB="${3:-10240}"

# Chuẩn hóa tên file .pcapng
if [[ "$NAME" != *.pcapng && "$NAME" != *.pcap ]]; then
    FILENAME="${NAME}.pcapng"
else
    FILENAME="$NAME"
fi

CAPTURE_DIR="/home/ubuntu/captures"
LOG_CAPTURE_DIR="/var/log/captures"
PID_FILE="/var/run/dhcp_capture.pid"
META_FILE="/var/run/dhcp_capture.meta"

sudo mkdir -p "$CAPTURE_DIR" "$LOG_CAPTURE_DIR"
sudo chown -R ubuntu:ubuntu "$CAPTURE_DIR"
sudo chmod 755 "$CAPTURE_DIR" "$LOG_CAPTURE_DIR"

# Kiểm tra nếu đang có tiến trình capture chạy
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[WARN] Đang có phiên bắt gói tin chạy (PID: $OLD_PID). Đang dừng phiên cũ trước..."
        /usr/local/bin/stop-capture.sh || true
    fi
fi

# Tự động phát hiện interface nối với INTERNAL_NET (192.168.0.1 - hướng về DHCP Server sau Firewall)
# và EXTERNAL_NET (10.10.0.1 - hướng về Client/Attacker) thay vì hard-code eth0
INTERNAL_IF=$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.0\./ {print $2; exit}')
EXTERNAL_IF=$(ip -o -4 addr show | awk '$4 ~ /^10\.10\.0\./ {print $2; exit}')

if [[ -z "$INTERNAL_IF" ]]; then
    INTERNAL_IF="eth0"
fi
if [[ -z "$EXTERNAL_IF" ]]; then
    EXTERNAL_IF="eth1"
fi

# Mặc định bắt trên INTERNAL_IF (điểm ngay sau hook relay_out của nftables trên dhcprelay,
# ghi nhận chính xác lưu lượng DHCP thực tế đi tới và phản hồi từ DHCP Server 192.168.0.100).
CAPTURE_IF="${CAPTURE_IFACE:-$INTERNAL_IF}"
OUT_PATH="${CAPTURE_DIR}/${FILENAME}"
BPF_FILTER="udp port 67 or udp port 68"

sudo rm -f "$OUT_PATH"
sudo touch "$OUT_PATH"
sudo chmod 666 "$OUT_PATH"

echo "=================================================================="
echo "[*] KHỞI ĐỘNG PCAP SENSOR (TSHARK / DUMPCAP)"
echo "    - File lưu trữ : $OUT_PATH"
echo "    - Interface    : $CAPTURE_IF (INTERNAL_IF=$INTERNAL_IF, EXTERNAL_IF=$EXTERNAL_IF)"
echo "    - Điểm đo      : Sau hook lọc nftables relay_out -> đường truyền tới DHCP Server"
echo "    - BPF Filter   : $BPF_FILTER"
echo "    - Giới hạn     : Tối đa ${MAX_DURATION}s hoặc ${MAX_FILESIZE_KB} KB"
echo "=================================================================="

if command -v dumpcap >/dev/null 2>&1; then
    sudo nohup dumpcap -i "$CAPTURE_IF" -f "$BPF_FILTER" -w "$OUT_PATH" \
        -a "duration:${MAX_DURATION}" -a "filesize:${MAX_FILESIZE_KB}" \
        >/tmp/dhcp_capture.log 2>&1 &
    CAP_PID=$!
else
    sudo nohup tshark -i "$CAPTURE_IF" -f "$BPF_FILTER" -w "$OUT_PATH" \
        -a "duration:${MAX_DURATION}" -a "filesize:${MAX_FILESIZE_KB}" \
        >/tmp/dhcp_capture.log 2>&1 &
    CAP_PID=$!
fi

echo "$CAP_PID" | sudo tee "$PID_FILE" >/dev/null
printf "FILE=%s\nIFACE=%s\nSTART_TIME=%s\n" "$OUT_PATH" "$CAPTURE_IF" "$(date -Iseconds)" | sudo tee "$META_FILE" >/dev/null

# Đợi 1s để đảm bảo dumpcap/tshark đã mở socket thành công
sleep 1
if kill -0 "$CAP_PID" 2>/dev/null; then
    echo "[OK] Đang bắt gói tin DHCP (PID: $CAP_PID). Chạy 'stop-capture.sh' khi hoàn tất kịch bản."
else
    echo "[ERROR] Không thể khởi động tiến trình bắt gói tin. Kiểm tra /tmp/dhcp_capture.log:"
    cat /tmp/dhcp_capture.log || true
    exit 1
fi

