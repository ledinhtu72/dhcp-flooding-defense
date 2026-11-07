#!/usr/bin/env bash
# =============================================================================
# inspect.sh - Khảo sát trạng thái hệ thống, Docker network và các container Labtainer
# =============================================================================
set -euo pipefail

echo "=== 1. THÔNG TIN HỆ ĐIỀU HÀNH & TÀI NGUYÊN MÁY ẢO ==="
uname -a
lscpu | grep -E "Model name|CPU\(s\):" || true
free -h
df -h /

echo ""
echo "=== 2. DANH SÁCH CONTAINER LABTAINER ĐANG CHẠY ==="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Networks}}"

echo ""
echo "=== 3. DANH SÁCH DOCKER NETWORK HIỆN TẠI ==="
docker network ls

echo ""
echo "=== 4. DANH SÁCH DOCKER IMAGE CỦA BÀI LAB ==="
docker images | grep -E "REPOSITORY|dhcp-lab|dhcp-flooding-defense" || true

