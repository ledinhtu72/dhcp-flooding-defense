#!/usr/bin/env bash
# =============================================================================
# scripts/package-lab.sh
# Đóng gói bài lab dhcp-flooding-defense thành duy nhất 1 file TAR chuẩn imodule:
#   dhcp-flooding-defense.tar (kèm dhcp-flooding-defense.tar.sha256)
# Khi người dùng chạy:
#   imodule <url_or_file>/dhcp-flooding-defense.tar
# Labtainers sẽ tự động giải nén vào $LABTAINER_DIR/labs/dhcp-flooding-defense.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAB_NAME="dhcp-flooding-defense"
RAW_VER="$(cat "${REPO_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")"
VERSION="v${RAW_VER#v}"

DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --version|-v)
            VERSION="v${2#v}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

TAR_OUT="${REPO_DIR}/${LAB_NAME}.tar"
SHA_OUT="${REPO_DIR}/${LAB_NAME}.tar.sha256"
RELEASE_DIR="${REPO_DIR}/release"

STAGE_BASE="$(mktemp -d /tmp/pkg-${LAB_NAME}.XXXXXX)"
STAGE_DIR="${STAGE_BASE}/${LAB_NAME}"
trap 'rm -rf "${STAGE_BASE}"' EXIT

mkdir -p "${STAGE_DIR}"

INCLUDE_ITEMS=(
    "config"
    "instr_config"
    "docs"
    "dockerfiles"
    "firewall"
    "dhcpserver"
    "dhcprelay"
    "attacker"
    "client"
    "scripts"
    "README.md"
    "TESTING_GUIDE.md"
    "TEST_PLAN.md"
    "RELEASE_TEST_REPORT.md"
    "VERSION"
    "MANIFEST.json"
    ".gitignore"
    ".env.example"
)

echo "======================================================================"
echo "  ĐÓNG GÓI BÀI LAB: ${LAB_NAME}.tar (${VERSION})"
echo "======================================================================"

for item in "${INCLUDE_ITEMS[@]}"; do
    if [[ -e "${REPO_DIR}/${item}" ]]; then
        cp -a "${REPO_DIR}/${item}" "${STAGE_DIR}/"
    fi
done

# Loại bỏ mọi file tạm, cache, log, pcap thực nghiệm, hoặc file nhạy cảm
find "${STAGE_DIR}" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "${STAGE_DIR}" \( -name "*.pyc" -o -name "*.pyo" -o -name "*.log" -o -name "*.swp" -o -name "*~" -o -name ".env" -o -name "*token*" -o -name "*.pcap*" \) -delete 2>/dev/null || true

# Quét bảo mật chống rò rỉ token
PAT_GH="gh""p_[A-Za-z0-9_]{20,}"
PAT_GH2="github""_pat_[A-Za-z0-9_]{20,}"
PAT_DC="dckr""_pat_[A-Za-z0-9_-]{15,}"
if grep -rnEI "(${PAT_GH}|${PAT_GH2}|${PAT_DC})" "${STAGE_DIR}" >/dev/null 2>&1; then
    echo "[ERROR] Phát hiện token hoặc dữ liệu nhạy cảm trong thư mục đóng gói!" >&2
    exit 1
fi

if [[ "${DRY_RUN}" == true ]]; then
    echo "[DRY-RUN] Kiểm tra staging đóng gói ${LAB_NAME}.tar thành công."
    exit 0
fi

# Tạo file TAR chuẩn với thư mục gốc là dhcp-flooding-defense/
tar --owner=0 --group=0 -cf "${TAR_OUT}" -C "${STAGE_BASE}" "${LAB_NAME}"
(cd "${REPO_DIR}" && sha256sum "${LAB_NAME}.tar" > "${SHA_OUT}")

mkdir -p "${RELEASE_DIR}"
cp -f "${TAR_OUT}" "${RELEASE_DIR}/${LAB_NAME}.tar"
cp -f "${SHA_OUT}" "${RELEASE_DIR}/${LAB_NAME}.tar.sha256"

# Đồng bộ sang /home/student/Desktop/labtainer/dhcp-labs nếu có
if [[ -d "/home/student/Desktop/labtainer/dhcp-labs" ]]; then
    cp -f "${TAR_OUT}" "/home/student/Desktop/labtainer/dhcp-labs/${LAB_NAME}.tar"
    cp -f "${SHA_OUT}" "/home/student/Desktop/labtainer/dhcp-labs/${LAB_NAME}.tar.sha256"
fi

TAR_SIZE="$(du -h "${TAR_OUT}" | awk '{print $1}')"
SHA_VAL="$(awk '{print $1}' "${SHA_OUT}")"
echo "[OK] Đã tạo file TAR chuẩn imodule : ${TAR_OUT} (${TAR_SIZE})"
echo "[OK] Checksum SHA256               : ${SHA_VAL}"
echo "======================================================================"

