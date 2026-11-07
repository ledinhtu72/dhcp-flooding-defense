#!/usr/bin/env bash
# =============================================================================
# cleanup.sh - Dọn dẹp an toàn chỉ các tài nguyên thuộc bài lab dhcp-flooding-defense
# Tuyệt đối không xóa image hay network của các bài lab khác
# =============================================================================
set -euo pipefail

cd /home/student/labtainer/trunk/scripts/labtainer-student
./bin/stoplab dhcp-flooding-defense 2>/dev/null || true

# Xóa container còn sót của riêng bài lab dhcp-flooding-defense nếu có
for c in $(docker ps -a --format "{{.Names}}" | grep "^dhcp-flooding-defense\." || true); do
    docker rm -f "$c" 2>/dev/null || true
done

for n in $(docker network ls --format "{{.Name}}" | grep "^dhcp-flooding-defense_" || true); do
    docker network rm "$n" 2>/dev/null || true
done

echo "[OK] Đã dọn dẹp sạch các container/network tạm của bài lab dhcp-flooding-defense."

