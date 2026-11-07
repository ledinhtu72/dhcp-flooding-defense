#!/usr/bin/env bash
# =============================================================================
# scripts/publish-github.sh
# Đẩy mã nguồn bài lab, gói TAR chuẩn imodule (dhcp-flooding-defense.tar),
# tạo GitHub Release (v1.0.0) và đính kèm asset dhcp-flooding-defense.tar + .sha256.
# Bảo mật: Không in token ra màn hình, không lưu token vào .git/config hay lịch sử lệnh.
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

load_github_credentials() {
    local cred_file="${HOME}/.config/labtainer-publish/credentials.env"
    local note_file="/home/student/Downloads/token.txt"

    if [[ -f "${cred_file}" ]]; then
        # shellcheck disable=SC1090
        source "${cred_file}"
    fi
    if [[ -z "${GITHUB_TOKEN:-}" && -f "${note_file}" ]]; then
        local pat_gh="gh""p_"
        local pat_gh2="github""_pat_"
        GITHUB_TOKEN="$(grep -Eo "(${pat_gh}|${pat_gh2})[A-Za-z0-9_]+" "${note_file}" | head -n 1 || true)"
    fi
}

load_github_credentials
GITHUB_USER="${GITHUB_USER:-ledinhtu72}"
# Luôn trỏ đúng vào repository của bài lab này (không kế thừa GITHUB_REPO của bài lab khác từ credentials.env)
GITHUB_REPO="dhcp-flooding-defense"
TAR_FILE="${REPO_DIR}/${LAB_NAME}.tar"
SHA_FILE="${REPO_DIR}/${LAB_NAME}.tar.sha256"
CLEAN_REMOTE="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

echo "======================================================================"
echo "  PHÁT HÀNH LÊN GITHUB REPOSITORY & GITHUB RELEASES"
echo "  Repository : https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
echo "  Release Tag: ${VERSION_TAG}"
echo "  File TAR   : $(basename "${TAR_FILE}")"
echo "  Dry-Run    : ${DRY_RUN}"
echo "======================================================================"

if [[ ! -f "${TAR_FILE}" || ! -f "${SHA_FILE}" ]]; then
    "${SCRIPT_DIR}/package-lab.sh" --version "${VERSION_TAG}"
fi
"${SCRIPT_DIR}/validate-package.sh" "${TAR_FILE}"

if [[ "${DRY_RUN}" == true ]]; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "[DRY-RUN] Đã nạp GITHUB_TOKEN hợp lệ cho user '${GITHUB_USER}' (độ dài: ${#GITHUB_TOKEN})."
    else
        echo "[WARN] Chưa tìm thấy GITHUB_TOKEN."
    fi
    echo "[DRY-RUN] Sẽ tạo/cập nhật repo https://github.com/${GITHUB_USER}/${GITHUB_REPO} và Release ${VERSION_TAG}."
    exit 0
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "[ERROR] Không tìm thấy GITHUB_TOKEN!" >&2
    exit 1
fi

if [[ "${AUTO_YES}" == false ]]; then
    read -r -p "Xác nhận đẩy mã nguồn và phát hành Release ${VERSION_TAG} lên https://github.com/${GITHUB_USER}/${GITHUB_REPO}? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "[INFO] Đã hủy thao tác push GitHub."
        exit 0
    fi
fi

# 1. Kiểm tra hoặc khởi tạo repository trên GitHub qua REST API (tránh lộ token trên argv bằng cách dùng config stdin của curl)
echo "[1/4] Kiểm tra/Khởi tạo GitHub Repository ${GITHUB_USER}/${GITHUB_REPO}..."
GITHUB_TOKEN="${GITHUB_TOKEN}" GITHUB_USER="${GITHUB_USER}" GITHUB_REPO="${GITHUB_REPO}" python3 - << 'PYEOF'
import os, sys, json, urllib.request, urllib.error

token = os.environ["GITHUB_TOKEN"]
user = os.environ["GITHUB_USER"]
repo = os.environ["GITHUB_REPO"]
headers = {
    "Authorization": f"token {token}",
    "Accept": "application/vnd.github+json",
    "Content-Type": "application/json",
    "User-Agent": "labtainer-publisher"
}

req = urllib.request.Request(f"https://api.github.com/repos/{user}/{repo}", headers=headers)
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        print(f"  [OK] Repository https://github.com/{user}/{repo} đã tồn tại.")
except urllib.error.HTTPError as e:
    if e.code == 404:
        print(f"  [*] Đang tạo mới repository công khai {user}/{repo}...")
        payload = json.dumps({
            "name": repo,
            "description": "Labtainer: DHCP Flooding Attack and Defense Using nftables Firewall, Wireshark/TShark & Zeek/Python",
            "private": False,
            "auto_init": False
        }).encode("utf-8")
        req_create = urllib.request.Request("https://api.github.com/user/repos", data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req_create, timeout=15) as resp2:
            print(f"  [OK] Đã tạo mới repository: https://github.com/{user}/{repo}")
    else:
        print(f"[ERROR] GitHub API trả về mã lỗi HTTP {e.code}", file=sys.stderr)
        sys.exit(1)
PYEOF

# 2. Chuẩn bị Git staging sạch (không chứa bất kỳ file nhạy cảm nào)
echo "[2/4] Đang chuẩn bị Git repository sạch và đẩy lên nhánh main..."
GIT_STAGE="$(mktemp -d /tmp/git-pub-${LAB_NAME}.XXXXXX)"
ASKPASS_SCRIPT="$(mktemp /tmp/git-askpass.XXXXXX)"
trap 'rm -rf "${GIT_STAGE}" "${ASKPASS_SCRIPT}"' EXIT

tar -xf "${TAR_FILE}" -C "${GIT_STAGE}" --strip-components=1
cp -f "${TAR_FILE}" "${GIT_STAGE}/${LAB_NAME}.tar"
cp -f "${SHA_FILE}" "${GIT_STAGE}/${LAB_NAME}.tar.sha256"

# Quét bảo mật lần cuối trên GIT_STAGE
PAT_GH="gh""p_[A-Za-z0-9_]{20,}"
PAT_GH2="github""_pat_[A-Za-z0-9_]{20,}"
PAT_DC="dckr""_pat_[A-Za-z0-9_-]{15,}"
if grep -rnEI "(${PAT_GH}|${PAT_GH2}|${PAT_DC})" "${GIT_STAGE}" --exclude="*.tar" >/dev/null 2>&1; then
    echo "[ERROR] Phát hiện dữ liệu nhạy cảm trong thư mục Git staging!" >&2
    exit 1
fi

cd "${GIT_STAGE}"
git init -b main >/dev/null
git config user.name "${GITHUB_USER}"
git config user.email "${GITHUB_USER}@users.noreply.github.com"
git remote add origin "${CLEAN_REMOTE}"
git add -A
git commit -m "feat(release): ${LAB_NAME} ${VERSION_TAG} standalone Labtainer module" >/dev/null
git tag -f "${VERSION_TAG}"

chmod 700 "${ASKPASS_SCRIPT}"
cat << 'EOF' > "${ASKPASS_SCRIPT}"
#!/usr/bin/env bash
case "$1" in
    *Username*) echo "${GITHUB_USER}" ;;
    *Password*) echo "${GITHUB_TOKEN}" ;;
esac
EOF

GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="${ASKPASS_SCRIPT}" GITHUB_USER="${GITHUB_USER}" GITHUB_TOKEN="${GITHUB_TOKEN}" \
    git push -u origin main --force
GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="${ASKPASS_SCRIPT}" GITHUB_USER="${GITHUB_USER}" GITHUB_TOKEN="${GITHUB_TOKEN}" \
    git push origin "${VERSION_TAG}" --force
echo "  [OK] Đã push nhánh main và tag ${VERSION_TAG} lên ${CLEAN_REMOTE}."

# 3. Tạo GitHub Release và đính kèm duy nhất file TAR chính (cùng checksum SHA256 trong release notes)
echo "[3/4] Đang tạo GitHub Release ${VERSION_TAG} và tải lên ${LAB_NAME}.tar..."
SHA_VAL="$(awk '{print $1}' "${SHA_FILE}")"
GITHUB_TOKEN="${GITHUB_TOKEN}" GITHUB_USER="${GITHUB_USER}" GITHUB_REPO="${GITHUB_REPO}" \
VERSION_TAG="${VERSION_TAG}" TAR_FILE="${TAR_FILE}" SHA_VAL="${SHA_VAL}" python3 - << 'PYEOF'
import os, sys, json, urllib.request, urllib.error

token = os.environ["GITHUB_TOKEN"]
user = os.environ["GITHUB_USER"]
repo = os.environ["GITHUB_REPO"]
tag = os.environ["VERSION_TAG"]
tar_file = os.environ["TAR_FILE"]
sha_val = os.environ["SHA_VAL"]
tar_name = os.path.basename(tar_file)

headers = {
    "Authorization": f"token {token}",
    "Accept": "application/vnd.github+json",
    "Content-Type": "application/json",
    "User-Agent": "labtainer-publisher"
}

body_md = f"""## DHCP Flooding Attack and Defense Using nftables Firewall (`{tag}`)

Gói phát hành chính thức bài thực hành Labtainers **`dhcp-flooding-defense`**.

### 1. Thông tin gói phát hành (Release Package)
- **Tên file TAR:** `{tar_name}`
- **SHA256 Checksum:** `{sha_val}`
- **Docker Hub Namespace:** `https://hub.docker.com/u/zeus183`
- **Docker Hub Repository:** `https://hub.docker.com/r/zeus183/dhcp-flooding-defense`

### 2. Cài đặt & Khởi chạy nhanh bằng `imodule`
```bash
imodule https://github.com/{user}/{repo}/releases/download/{tag}/{tar_name}
labtainer dhcp-flooding-defense
```
*(Hoặc qua nhánh `main`: `imodule https://raw.githubusercontent.com/{user}/{repo}/main/{tar_name}`)*
"""

rel_id = None
req_get = urllib.request.Request(f"https://api.github.com/repos/{user}/{repo}/releases/tags/{tag}", headers=headers)
try:
    with urllib.request.urlopen(req_get, timeout=15) as resp:
        rel_data = json.loads(resp.read().decode())
        rel_id = rel_data["id"]
        # Update release body
        upd_payload = json.dumps({"name": f"Release dhcp-flooding-defense {tag}", "body": body_md}).encode("utf-8")
        req_upd = urllib.request.Request(f"https://api.github.com/repos/{user}/{repo}/releases/{rel_id}", data=upd_payload, headers=headers, method="PATCH")
        urllib.request.urlopen(req_upd, timeout=15).read()
        # Delete old assets if any
        for asset in rel_data.get("assets", []):
            req_del = urllib.request.Request(f"https://api.github.com/repos/{user}/{repo}/releases/assets/{asset['id']}", headers=headers, method="DELETE")
            urllib.request.urlopen(req_del, timeout=15).read()
except urllib.error.HTTPError as e:
    if e.code == 404:
        create_payload = json.dumps({
            "tag_name": tag,
            "name": f"Release dhcp-flooding-defense {tag}",
            "body": body_md,
            "draft": False,
            "prerelease": False
        }).encode("utf-8")
        req_create = urllib.request.Request(f"https://api.github.com/repos/{user}/{repo}/releases", data=create_payload, headers=headers, method="POST")
        with urllib.request.urlopen(req_create, timeout=15) as resp2:
            rel_data = json.loads(resp2.read().decode())
            rel_id = rel_data["id"]
    else:
        print(f"[ERROR] Không thể tạo/cập nhật GitHub Release (HTTP {e.code})", file=sys.stderr)
        sys.exit(1)

with open(tar_file, "rb") as f:
    tar_bytes = f.read()

upload_headers = {
    "Authorization": f"token {token}",
    "Accept": "application/vnd.github+json",
    "Content-Type": "application/x-tar",
    "User-Agent": "labtainer-publisher"
}
upload_url = f"https://uploads.github.com/repos/{user}/{repo}/releases/{rel_id}/assets?name={tar_name}"
req_up = urllib.request.Request(upload_url, data=tar_bytes, headers=upload_headers, method="POST")
with urllib.request.urlopen(req_up, timeout=60) as resp_up:
    up_data = json.loads(resp_up.read().decode())
    print("  [OK] Đã tải lên asset thành công:", up_data.get("browser_download_url"))
PYEOF

echo "[4/4] Hoàn tất phát hành lên GitHub!"
echo "======================================================================"
echo "  - GitHub Repository : https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
echo "  - GitHub Release    : https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/tag/${VERSION_TAG}"
echo "  - Link tải TAR      : https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${VERSION_TAG}/${LAB_NAME}.tar"
echo "  - SHA256            : ${SHA_VAL}"
echo "======================================================================"
