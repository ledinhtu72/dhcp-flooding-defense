#!/usr/bin/env bash
# =============================================================================
# scripts/test-import.sh
# Kiểm thử thực tế quy trình import bài lab bằng công cụ `imodule` của Labtainers
# trên môi trường sạch (tạm thời cất thư mục bài lab hiện có, import từ file TAR
# độc lập bằng `imodule`, xác minh Labtainers nhận diện bài lab).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAB_NAME="dhcp-flooding-defense"
LABTAINER_DIR="${LABTAINER_DIR:-/home/student/labtainer/trunk}"
LABS_ROOT="${LABTAINER_DIR}/labs"
TARGET_LAB_DIR="${LABS_ROOT}/${LAB_NAME}"

TAR_SRC="${1:-${REPO_DIR}/${LAB_NAME}.tar}"
TMP_TAR="/tmp/test_import_${LAB_NAME}.tar"

if [[ "${TAR_SRC}" =~ ^https?:// || "${TAR_SRC}" =~ ^file:// ]]; then
    IMODULE_URI="${TAR_SRC}"
else
    if [[ ! -f "${TAR_SRC}" ]]; then
        echo "[ERROR] Không tìm thấy file TAR để kiểm thử import: ${TAR_SRC}" >&2
        exit 1
    fi
    cp -f "${TAR_SRC}" "${TMP_TAR}"
    IMODULE_URI="file://${TMP_TAR}"
fi

BACKUP_DIR="/tmp/backup_lab_${LAB_NAME}.$$"
IMODULE_BACKUP="/tmp/imodules.txt.bak.$$"
IMODULE_FILE="${HOME}/.local/share/labtainers/imodules.txt"

if [[ -f "${IMODULE_FILE}" ]]; then
    cp -f "${IMODULE_FILE}" "${IMODULE_BACKUP}"
fi

restore_env() {
    rm -f "${TMP_TAR}"
    if [[ -f "${IMODULE_BACKUP}" ]]; then
        mv -f "${IMODULE_BACKUP}" "${IMODULE_FILE}"
    fi
    if [[ -d "${BACKUP_DIR}" && ! -d "${TARGET_LAB_DIR}" ]]; then
        mv "${BACKUP_DIR}" "${TARGET_LAB_DIR}"
    else
        rm -rf "${BACKUP_DIR}"
    fi
}
trap restore_env EXIT

echo "======================================================================"
echo "  KIỂM THỬ IMPORT BẰNG LỆNH 'imodule' TRÊN MÔI TRƯỜNG SẠCH"
echo "======================================================================"

echo "[1/4] Tạm thời di chuyển ${TARGET_LAB_DIR} ra ngoài để giả lập môi trường sạch..."
if [[ -d "${TARGET_LAB_DIR}" ]]; then
    mv "${TARGET_LAB_DIR}" "${BACKUP_DIR}"
fi

if [[ -d "${TARGET_LAB_DIR}" ]]; then
    echo "[ERROR] Không thể làm sạch ${TARGET_LAB_DIR}" >&2
    exit 1
fi
echo "  [OK] Thư mục ${TARGET_LAB_DIR} hiện không tồn tại (môi trường sạch)."

echo "[2/4] Thực thi lệnh chuẩn của Labtainers: imodule ${IMODULE_URI} ..."
export LABTAINER_DIR
/home/student/labtainer/trunk/scripts/labtainer-student/bin/imodule "${IMODULE_URI}"

echo "[3/4] Xác minh thư mục bài lab đã được imodule giải nén vào ${TARGET_LAB_DIR}..."
if [[ ! -f "${TARGET_LAB_DIR}/config/start.config" ]]; then
    echo "[ERROR] imodule không giải nén ra ${TARGET_LAB_DIR}/config/start.config!" >&2
    exit 1
fi
echo "  [OK] Tìm thấy ${TARGET_LAB_DIR}/config/start.config sau khi chạy imodule."

echo "[4/4] Xác minh Labtainers nhận diện bài lab '${LAB_NAME}' qua 'labtainer -l'..."
if /home/student/labtainer/trunk/scripts/labtainer-student/bin/labtainer -l | grep -q "${LAB_NAME}"; then
    echo "  [OK] Lệnh 'labtainer -l' đã liệt kê bài lab '${LAB_NAME}'."
else
    echo "[ERROR] 'labtainer -l' không tìm thấy bài lab '${LAB_NAME}'!" >&2
    exit 1
fi

# Khôi phục thêm thư mục .git hoặc release nếu có từ bản backup
if [[ -d "${BACKUP_DIR}/.git" ]]; then
    cp -a "${BACKUP_DIR}/.git" "${TARGET_LAB_DIR}/"
fi
if [[ -d "${BACKUP_DIR}/release" ]]; then
    cp -a "${BACKUP_DIR}/release" "${TARGET_LAB_DIR}/"
fi
if [[ -f "${BACKUP_DIR}/${LAB_NAME}.tar" ]]; then
    cp -a "${BACKUP_DIR}/${LAB_NAME}.tar"* "${TARGET_LAB_DIR}/"
fi
rm -rf "${BACKUP_DIR}"

echo "======================================================================"
echo "  [PASS] KIỂM THỬ IMPORT BẰNG 'imodule' THÀNH CÔNG 100%!"
echo "======================================================================"

