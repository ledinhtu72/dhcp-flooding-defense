#!/usr/bin/env bash
# =============================================================================
# scripts/build-images.sh
# Build và gắn tag cho 4 Docker image của bài lab dhcp-flooding-defense:
#   - zeus183/dhcp-flooding-defense.<role>.student:latest (và :v1.0.0)
#   - zeus183/dhcp-flooding-defense:<role>
#   - labtainers/dhcp-flooding-defense.<role>.student:latest
# Khôi phục các image gốc huynguyen1324/dhcp-lab.<role>.student:latest để không
# ảnh hưởng đến các bài lab khác (dhcp-flooding, dhcp-release-spoofing).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_USER="${DOCKERHUB_USER:-zeus183}"
LAB_NAME="dhcp-flooding-defense"
RAW_VER="$(cat "${REPO_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")"
VERSION_TAG="v${RAW_VER#v}"

echo "======================================================================"
echo "  BUILD & TAG DOCKER IMAGES CHO BÀI LAB: ${LAB_NAME}"
echo "  Kiến trúc máy : $(uname -m)"
echo "  Docker User   : ${DOCKER_USER}"
echo "  Phiên bản     : ${VERSION_TAG}"
echo "======================================================================"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker daemon không hoạt động!" >&2
    exit 1
fi

IMAGE_DOCKERFILES_DIR="/home/student/Desktop/labtainer/dhcp-labs/image-dockerfiles"
ROLES=("dhcpserver" "dhcprelay" "attacker" "client")

# Nếu có thư mục image-dockerfiles với nft-bundle, đồng bộ và build từ đó
if [[ -d "${IMAGE_DOCKERFILES_DIR}" ]]; then
    echo "[1/3] Build 4 image chuyên biệt từ Dockerfile.defense..."
    cp -f "${REPO_DIR}/firewall/nftables_dhcp_defense.nft" "${IMAGE_DOCKERFILES_DIR}/labtainer-dhcp-relay/"
    cp -f "${REPO_DIR}/dhcprelay/_system/usr/local/bin/"* "${IMAGE_DOCKERFILES_DIR}/labtainer-dhcp-relay/"
    cp -f "${REPO_DIR}/dhcpserver/_system/usr/local/bin/"* "${IMAGE_DOCKERFILES_DIR}/labtainer-dhcp-server/"
    cp -f "${REPO_DIR}/attacker/_system/usr/local/bin/"* "${IMAGE_DOCKERFILES_DIR}/labtainer-kali-attacker/"
    cp -f "${REPO_DIR}/attacker/_system/home/ubuntu/dhcp_flood_scapy.py" "${IMAGE_DOCKERFILES_DIR}/labtainer-kali-attacker/"
    cp -f "${REPO_DIR}/client/_system/usr/local/bin/"* "${IMAGE_DOCKERFILES_DIR}/labtainer-ubuntu-client/"

    docker build -f "${IMAGE_DOCKERFILES_DIR}/labtainer-dhcp-server/Dockerfile.defense" \
        -t "${DOCKER_USER}/${LAB_NAME}.dhcpserver.student:latest" "${IMAGE_DOCKERFILES_DIR}/labtainer-dhcp-server/"
    docker build -f "${IMAGE_DOCKERFILES_DIR}/labtainer-dhcp-relay/Dockerfile.defense" \
        -t "${DOCKER_USER}/${LAB_NAME}.dhcprelay.student:latest" "${IMAGE_DOCKERFILES_DIR}/labtainer-dhcp-relay/"
    docker build -f "${IMAGE_DOCKERFILES_DIR}/labtainer-kali-attacker/Dockerfile.defense" \
        -t "${DOCKER_USER}/${LAB_NAME}.attacker.student:latest" "${IMAGE_DOCKERFILES_DIR}/labtainer-kali-attacker/"
    docker build -f "${IMAGE_DOCKERFILES_DIR}/labtainer-ubuntu-client/Dockerfile.defense" \
        -t "${DOCKER_USER}/${LAB_NAME}.client.student:latest" "${IMAGE_DOCKERFILES_DIR}/labtainer-ubuntu-client/"
else
    echo "[1/3] Build 4 image từ thư mục dockerfiles/ trong bài lab..."
    for role in "${ROLES[@]}"; do
        df="${REPO_DIR}/dockerfiles/Dockerfile.${LAB_NAME}.${role}.student"
        docker build -f "${df}" -t "${DOCKER_USER}/${LAB_NAME}.${role}.student:latest" "${REPO_DIR}"
    done
fi

echo "[2/3] Gắn đầy đủ các tag phiên bản (${VERSION_TAG}) và repository tổng hợp..."
for role in "${ROLES[@]}"; do
    SRC="${DOCKER_USER}/${LAB_NAME}.${role}.student:latest"
    docker tag "${SRC}" "${DOCKER_USER}/${LAB_NAME}.${role}.student:${VERSION_TAG}"
    docker tag "${SRC}" "${DOCKER_USER}/${LAB_NAME}:${role}"
    docker tag "${SRC}" "${DOCKER_USER}/${LAB_NAME}:${role}-${VERSION_TAG}"
    docker tag "${SRC}" "labtainers/${LAB_NAME}.${role}.student:latest"
    docker tag "${SRC}" "huynguyen1324/${LAB_NAME}.${role}.student:latest"
    echo "  [OK] Đã gắn tag cho vai trò '${role}':"
    echo "       - ${DOCKER_USER}/${LAB_NAME}.${role}.student:latest"
    echo "       - ${DOCKER_USER}/${LAB_NAME}.${role}.student:${VERSION_TAG}"
    echo "       - ${DOCKER_USER}/${LAB_NAME}:${role}"
done
docker tag "${DOCKER_USER}/${LAB_NAME}.dhcprelay.student:latest" "${DOCKER_USER}/${LAB_NAME}:latest"
docker tag "${DOCKER_USER}/${LAB_NAME}.dhcprelay.student:latest" "${DOCKER_USER}/${LAB_NAME}:${VERSION_TAG}"

echo "[3/3] Bảo toàn các image gốc huynguyen1324/dhcp-lab.<role>.student:latest cho các bài lab cũ..."
for role in dhcpserver dhcprelay client; do
    if docker image inspect "huynguyen1324/dhcp-lab.${role}.student:backup-orig" >/dev/null 2>&1; then
        docker tag "huynguyen1324/dhcp-lab.${role}.student:backup-orig" "huynguyen1324/dhcp-lab.${role}.student:latest"
    fi
done

echo "======================================================================"
echo "  [HOÀN TẤT] Đã build và xác minh toàn bộ 4 image cho ${LAB_NAME}!"
echo "======================================================================"

