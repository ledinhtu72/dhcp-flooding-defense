#!/usr/bin/env bash
# =============================================================================
# scripts/validate-package.sh
# Xác minh tính toàn vẹn, cấu trúc Labtainers chuẩn imodule, checksum SHA256
# và quét bảo mật cho gói phát hành dhcp-flooding-defense.tar.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAB_NAME="dhcp-flooding-defense"
TAR_FILE="${1:-${REPO_DIR}/${LAB_NAME}.tar}"
SHA_FILE="${TAR_FILE}.sha256"

ERRORS=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1" >&2; ERRORS=$((ERRORS + 1)); }

echo "======================================================================"
echo "  KIỂM TRA GÓI PHÁT HÀNH TAR: ${TAR_FILE}"
echo "======================================================================"

if [[ ! -f "${TAR_FILE}" ]]; then
    fail "Không tìm thấy file TAR: ${TAR_FILE}"
    exit 1
fi
pass "File TAR tồn tại ($(du -h "${TAR_FILE}" | awk '{print $1}'))"

if [[ -f "${SHA_FILE}" ]]; then
    if (cd "$(dirname "${TAR_FILE}")" && sha256sum -c "$(basename "${SHA_FILE}")" >/dev/null 2>&1); then
        pass "Checksum SHA256 khớp hoàn toàn: $(awk '{print $1}' "${SHA_FILE}")"
    else
        fail "Checksum SHA256 KHÔNG khớp!"
    fi
else
    fail "Thiếu file checksum SHA256: ${SHA_FILE}"
fi

# Giải nén thử vào thư mục tạm để kiểm tra cấu trúc
VERIFY_DIR="$(mktemp -d /tmp/validate-${LAB_NAME}.XXXXXX)"
trap 'rm -rf "${VERIFY_DIR}"' EXIT

if tar -xf "${TAR_FILE}" -C "${VERIFY_DIR}"; then
    pass "Giải nén thử bằng 'tar -xf' thành công"
else
    fail "File TAR bị hỏng, không thể giải nén!"
    exit 1
fi

EXTRACTED_LAB="${VERIFY_DIR}/${LAB_NAME}"
if [[ -d "${EXTRACTED_LAB}" ]]; then
    pass "Thư mục gốc trong TAR đúng chuẩn imodule: ${LAB_NAME}/"
else
    fail "Thư mục gốc trong TAR không phải là ${LAB_NAME}/"
fi

REQUIRED_FILES=(
    "config/start.config"
    "config/parameter.config"
    "config/about.txt"
    "config/keywords.txt"
    "instr_config/results.config"
    "instr_config/goals.config"
    "docs/instruction.md"
    "docs/lab_diagram.txt"
    "firewall/nftables_dhcp_defense.nft"
    "dockerfiles/Dockerfile.dhcp-flooding-defense.dhcpserver.student"
    "dockerfiles/Dockerfile.dhcp-flooding-defense.dhcprelay.student"
    "dockerfiles/Dockerfile.dhcp-flooding-defense.attacker.student"
    "dockerfiles/Dockerfile.dhcp-flooding-defense.client.student"
    "dhcprelay/_system/etc/nftables_dhcp_defense.nft"
    "dhcprelay/_system/usr/local/bin/zeek"
    "dhcprelay/_system/usr/local/bin/analyze_dhcp.py"
    "attacker/_system/home/ubuntu/dhcp_flood_scapy.py"
    "README.md"
    "TESTING_GUIDE.md"
    "VERSION"
    "MANIFEST.json"
)

for rf in "${REQUIRED_FILES[@]}"; do
    if [[ -s "${EXTRACTED_LAB}/${rf}" ]]; then
        pass "File bắt buộc tồn tại và khác rỗng: ${rf}"
    else
        fail "Thiếu hoặc rỗng file bắt buộc: ${rf}"
    fi
done

# Quét bảo mật token trong bản giải nén
PAT_GH="gh""p_[A-Za-z0-9_]{20,}"
PAT_GH2="github""_pat_[A-Za-z0-9_]{20,}"
PAT_DC="dckr""_pat_[A-Za-z0-9_-]{15,}"
if grep -rnEI "(${PAT_GH}|${PAT_GH2}|${PAT_DC})" "${EXTRACTED_LAB}" >/dev/null 2>&1; then
    fail "Phát hiện token bị đóng gói bên trong TAR!"
else
    pass "Quét bảo mật: 0 token/secret bên trong gói TAR"
fi

# Kiểm tra REGISTRY trong config/start.config
if grep -qE "^[[:space:]]*REGISTRY[[:space:]]+zeus183" "${EXTRACTED_LAB}/config/start.config"; then
    pass "config/start.config tham chiếu đúng REGISTRY zeus183"
else
    fail "config/start.config chưa trỏ về REGISTRY zeus183"
fi

echo "======================================================================"
if [[ ${ERRORS} -eq 0 ]]; then
    echo "  [KẾT QUẢ] GÓI TAR ĐẠT CHUẨN 100% (0 lỗi)"
    echo "======================================================================"
    exit 0
else
    echo "  [KẾT QUẢ] GÓI TAR CÓ ${ERRORS} LỖI!"
    echo "======================================================================"
    exit 1
fi

