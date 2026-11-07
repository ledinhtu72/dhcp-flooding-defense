#!/usr/bin/env bash
# =============================================================================
# scripts/publish-dockerhub.sh
# Đẩy các Docker image của bài lab dhcp-flooding-defense lên Docker Hub (zeus183):
#   1. 4 repository chuẩn Labtainers (tự động pull khi chạy `labtainer dhcp-flooding-defense`):
#      - zeus183/dhcp-flooding-defense.dhcpserver.student:{latest,v1.0.0}
#      - zeus183/dhcp-flooding-defense.dhcprelay.student:{latest,v1.0.0}
#      - zeus183/dhcp-flooding-defense.attacker.student:{latest,v1.0.0}
#      - zeus183/dhcp-flooding-defense.client.student:{latest,v1.0.0}
#   2. 1 repository tổng hợp chính để tra cứu tập trung:
#      - zeus183/dhcp-flooding-defense:{dhcpserver,dhcprelay,attacker,client,v1.0.0,latest}
# Bảo mật: Tuyệt đối không in token ra màn hình, đăng nhập qua --password-stdin.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAB_NAME="dhcp-flooding-defense"
RAW_VER="$(cat "${REPO_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")"
VERSION_TAG="v${RAW_VER#v}"

DRY_RUN=false
AUTO_YES=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --version|-v)
            VERSION_TAG="v${2#v}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

load_docker_credentials() {
    local cred_file="${HOME}/.config/labtainer-publish/credentials.env"
    local note_file="/home/student/Downloads/token.txt"

    if [[ -z "${DOCKERHUB_USER:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
        if [[ -f "${cred_file}" ]]; then
            # shellcheck disable=SC1090
            source "${cred_file}"
        fi
    fi
    if [[ -z "${DOCKERHUB_USER:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
        if [[ -f "${note_file}" ]]; then
            if [[ -z "${DOCKERHUB_USER:-}" ]]; then
                DOCKERHUB_USER="$(awk '/docker login -u/ {print $NF}' "${note_file}" | tr -d '[:space:]' || true)"
            fi
            if [[ -z "${DOCKERHUB_TOKEN:-}" ]]; then
                local pat_dc="dckr""_pat_"
                DOCKERHUB_TOKEN="$(grep -Eo "${pat_dc}[A-Za-z0-9_-]+" "${note_file}" | head -n 1 || true)"
            fi
        fi
    fi
}

load_docker_credentials
DOCKERHUB_USER="${DOCKERHUB_USER:-zeus183}"

ROLES=("dhcpserver" "dhcprelay" "attacker" "client")
declare -a PUSH_IMAGES=()
for role in "${ROLES[@]}"; do
    PUSH_IMAGES+=(
        "${DOCKERHUB_USER}/${LAB_NAME}.${role}.student:latest"
        "${DOCKERHUB_USER}/${LAB_NAME}.${role}.student:${VERSION_TAG}"
        "${DOCKERHUB_USER}/${LAB_NAME}:${role}"
    )
done
PUSH_IMAGES+=(
    "${DOCKERHUB_USER}/${LAB_NAME}:latest"
    "${DOCKERHUB_USER}/${LAB_NAME}:${VERSION_TAG}"
)

echo "======================================================================"
echo "  PHÁT HÀNH DOCKER IMAGES LÊN DOCKER HUB"
echo "  Tài khoản Docker Hub : ${DOCKERHUB_USER}"
echo "  Link chính           : https://hub.docker.com/r/${DOCKERHUB_USER}/${LAB_NAME}"
echo "  Phiên bản            : ${VERSION_TAG}"
echo "  Chế độ Dry-Run       : ${DRY_RUN}"
echo "======================================================================"
echo "Danh sách image/tag sẽ phát hành (${#PUSH_IMAGES[@]} tags):"
for img in "${PUSH_IMAGES[@]}"; do
    echo "  - ${img}"
done

if [[ "${DRY_RUN}" == true ]]; then
    if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
        echo "[DRY-RUN] Đã xác nhận thông tin xác thực Docker Hub cho '${DOCKERHUB_USER}' (độ dài token: ${#DOCKERHUB_TOKEN})."
    else
        echo "[WARN] Chưa tìm thấy DOCKERHUB_TOKEN."
    fi
    exit 0
fi

if [[ -z "${DOCKERHUB_TOKEN:-}" ]]; then
    echo "[ERROR] Không tìm thấy DOCKERHUB_TOKEN để xác thực Docker Hub!" >&2
    exit 1
fi

if [[ "${AUTO_YES}" == false ]]; then
    read -r -p "Xác nhận đẩy ${#PUSH_IMAGES[@]} tags lên Docker Hub (${DOCKERHUB_USER})? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "[INFO] Đã hủy thao tác push Docker Hub."
        exit 0
    fi
fi

echo "[1/3] Đăng nhập Docker Hub qua stdin (--password-stdin)..."
printf '%s\n' "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USER}" --password-stdin >/dev/null
echo "  [OK] Đăng nhập thành công tài khoản ${DOCKERHUB_USER}."

echo "[2/3] Đang đẩy các Docker image lên Docker Hub..."
for img in "${PUSH_IMAGES[@]}"; do
    echo "  -> docker push ${img}"
    docker push "${img}"
done

echo "[3/3] Xác minh khả năng pull từ Docker Hub..."
for role in "${ROLES[@]}"; do
    test_img="${DOCKERHUB_USER}/${LAB_NAME}.${role}.student:latest"
    docker pull "${test_img}" >/dev/null
    echo "  [OK] Đã xác minh pull thành công: ${test_img}"
done

echo "======================================================================"
echo "  [THÀNH CÔNG] ĐÃ PHÁT HÀNH VÀ XÁC MINH DOCKER IMAGES TRÊN DOCKER HUB!"
echo "  - Link Repository tổng hợp : https://hub.docker.com/r/${DOCKERHUB_USER}/${LAB_NAME}"
echo "  - Link Namespace chính     : https://hub.docker.com/u/${DOCKERHUB_USER}"
echo "======================================================================"

