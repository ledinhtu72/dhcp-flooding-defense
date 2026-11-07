#!/usr/bin/env bash
# =============================================================================
# scripts/release.sh
# Script điều phối tổng hợp quy trình build, đóng gói, xác minh, kiểm thử imodule
# và phát hành bài lab dhcp-flooding-defense lên Docker Hub và GitHub.
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

echo "======================================================================"
echo "  QUY TRÌNH PHÁT HÀNH TỔNG HỢP: ${LAB_NAME} (${VERSION_TAG})"
echo "  Chế độ Dry-Run: ${DRY_RUN}"
echo "======================================================================"

echo ">>> [1/6] Build & gắn tag các Docker image..."
"${SCRIPT_DIR}/build-images.sh"

echo ">>> [2/6] Đóng gói ${LAB_NAME}.tar và sinh SHA256..."
"${SCRIPT_DIR}/package-lab.sh" --version "${VERSION_TAG}"

echo ">>> [3/6] Kiểm tra tính toàn vẹn và bảo mật của gói TAR..."
"${SCRIPT_DIR}/validate-package.sh" "${REPO_DIR}/${LAB_NAME}.tar"

echo ">>> [4/6] Kiểm thử import thực tế bằng lệnh 'imodule'..."
"${SCRIPT_DIR}/test-import.sh" "${REPO_DIR}/${LAB_NAME}.tar"

PUB_ARGS=("--version" "${VERSION_TAG}")
[[ "${DRY_RUN}" == true ]] && PUB_ARGS+=("--dry-run")
[[ "${AUTO_YES}" == true ]] && PUB_ARGS+=("--yes")

echo ">>> [5/6] Phát hành Docker image lên Docker Hub..."
"${SCRIPT_DIR}/publish-dockerhub.sh" "${PUB_ARGS[@]}"

echo ">>> [6/6] Phát hành mã nguồn & gói TAR lên GitHub Releases..."
"${SCRIPT_DIR}/publish-github.sh" "${PUB_ARGS[@]}"

echo "======================================================================"
echo "  [HOÀN TẤT QUY TRÌNH RELEASE ${LAB_NAME} (${VERSION_TAG})]"
echo "======================================================================"

