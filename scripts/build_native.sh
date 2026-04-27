#!/usr/bin/env bash
# Build kvm_display (LCD UI LVGL binary) with custom Compuzone logo.
#
# Source:  https://github.com/luckfox-eng29/kvm_display
# Toolchain: arm-rockchip830-linux-uclibcgnueabihf (same as jetkvm rv1106)
# We reuse the jetkvm buildkit already installed at /opt/jetkvm-native-buildkit
# by synthesizing a minimal fake LUCKFOX_SDK_PATH directory tree expected by
# the kvm_display Makefile.
#
# Run inside WSL Ubuntu (or any Ubuntu 22.04+ environment).
#
# Usage:
#   bash scripts/build_native.sh /mnt/d/Projects/compuzone-kvm/compuzone-logo-153x42.png
#   (any PNG with alpha channel works; will be resized to 64x64)
#
# Output:
#   resource/jetkvm_native          (re-used path; contains new kvm_display binary)
#   resource/jetkvm_native.sha256
#
# Deploy with:   .\scripts\deploy.ps1 -DeviceIp <IP> -DeployDisplay

set -euo pipefail

LOGO_PNG="${1:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${PROJECT_ROOT}/.build-native"
DISPLAY_REPO="${WORK_DIR}/kvm_display"
DISPLAY_REPO_URL="https://github.com/luckfox-eng29/kvm_display.git"

BUILDKIT_DIR="/opt/jetkvm-native-buildkit"
BUILDKIT_VERSION="v0.2.5"
BUILDKIT_URL="https://github.com/jetkvm/rv1106-system/releases/download/${BUILDKIT_VERSION}/buildkit.tar.zst"

# Synthetic LuckFox SDK path that maps to the jetkvm buildkit toolchain.
# kvm_display Makefile expects:
#   $(LUCKFOX_SDK_PATH)/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-gcc
FAKE_SDK="/opt/luckfox-fake-sdk"

# LCD logo target (square LVGL image used by Main/Network/Version screens)
LOGO_SIZE=64
LOGO_VAR_NAME="_LOGO_alpha_64x64"
LOGO_TARGET_FILE="kvmui/_LOGO_alpha_64x64.c"

color_red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
color_green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
color_cyan()  { printf '\033[0;36m%s\033[0m\n' "$*"; }
step() { echo; color_cyan "==> $*"; }
fail() { color_red "ERROR: $*" >&2; exit 1; }

# --- Validate args ---
[[ -n "${LOGO_PNG}" ]] || fail "Usage: $0 <path-to-logo.png>"
[[ -f "${LOGO_PNG}" ]] || fail "Logo file not found: ${LOGO_PNG}"

# --- Validate environment ---
step "Checking environment"
[[ "$(uname -s)" == "Linux" ]] || fail "Run on Linux (use WSL Ubuntu on Windows)."
command -v sudo >/dev/null || fail "sudo required"
command -v git  >/dev/null || fail "git required"

# --- Install dependencies (idempotent) ---
step "Installing build dependencies (sudo password may be required)"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    build-essential \
    wget zstd ca-certificates \
    nodejs npm \
    imagemagick librsvg2-bin \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev libpixman-1-dev librsvg2-dev pkg-config

# --- Download jetkvm rv1106 buildkit (only if missing) ---
if [[ ! -x "${BUILDKIT_DIR}/bin/arm-rockchip830-linux-uclibcgnueabihf-gcc" ]]; then
    step "Downloading Rockchip buildkit ${BUILDKIT_VERSION} (large, one-time)"
    sudo mkdir -p "${BUILDKIT_DIR}"
    TMP_TAR="$(mktemp --suffix=.tar.zst)"
    wget -O "${TMP_TAR}" "${BUILDKIT_URL}"
    sudo tar --use-compress-program="unzstd --long=31" -xf "${TMP_TAR}" -C "${BUILDKIT_DIR}"
    rm -f "${TMP_TAR}"
else
    color_green "Buildkit present at ${BUILDKIT_DIR}"
fi

# --- Synthesize fake LuckFox SDK tree expected by kvm_display Makefile ---
# Makefile reads:
#   $(LUCKFOX_SDK_PATH)/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-gcc
# We symlink that path to the jetkvm buildkit root (which has bin/, lib/, libexec/, share/).
step "Preparing synthetic LUCKFOX_SDK_PATH at ${FAKE_SDK}"
sudo mkdir -p "${FAKE_SDK}/tools/linux/toolchain"
sudo ln -sfn "${BUILDKIT_DIR}" "${FAKE_SDK}/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf"

# --- Clone or update kvm_display ---
mkdir -p "${WORK_DIR}"
if [[ ! -d "${DISPLAY_REPO}/.git" ]]; then
    step "Cloning kvm_display"
    git clone --depth 1 "${DISPLAY_REPO_URL}" "${DISPLAY_REPO}"
else
    step "Updating kvm_display"
    git -C "${DISPLAY_REPO}" fetch --depth 1 origin master || true
    git -C "${DISPLAY_REPO}" reset --hard origin/master || true
fi

# --- Install lv_img_conv (LVGL image converter) ---
LV_CONV="${WORK_DIR}/node_modules/.bin/lv_img_conv"
SWC_CORE="${WORK_DIR}/node_modules/@swc/core"
if [[ ! -x "${LV_CONV}" ]] || [[ ! -d "${SWC_CORE}" ]]; then
    step "Installing lv_img_conv"
    pushd "${WORK_DIR}" >/dev/null
    cat > package.json <<'JSON'
{ "name": "build-native-tools", "version": "1.0.0", "private": true }
JSON
    rm -rf node_modules package-lock.json
    npm install --no-fund --no-audit lv_img_conv ts-node typescript @swc/core
    popd >/dev/null
fi

# --- Resize logo to LOGO_SIZE x LOGO_SIZE (square, centered, transparent pad) ---
RESIZED_PNG="${WORK_DIR}/compuzone-logo-${LOGO_SIZE}x${LOGO_SIZE}.png"
step "Preparing logo image (${LOGO_SIZE}x${LOGO_SIZE})"
convert "${LOGO_PNG}" \
    -resize "${LOGO_SIZE}x${LOGO_SIZE}" \
    -background none -gravity center \
    -extent "${LOGO_SIZE}x${LOGO_SIZE}" \
    "PNG32:${RESIZED_PNG}"
color_green "Resized logo: ${RESIZED_PNG}"

# --- Convert PNG to LVGL C array (LV_IMG_CF_TRUE_COLOR_ALPHA) ---
step "Converting PNG to LVGL C array (TRUE_COLOR_ALPHA)"
TARGET_FILE="${DISPLAY_REPO}/${LOGO_TARGET_FILE}"
[[ -f "${TARGET_FILE}" ]] || fail "Target file not found: ${TARGET_FILE}"
[[ -f "${TARGET_FILE}.orig" ]] || cp "${TARGET_FILE}" "${TARGET_FILE}.orig"

"${LV_CONV}" \
    --output-file "${TARGET_FILE}" \
    --image-name "${LOGO_VAR_NAME}" \
    --color-format CF_TRUE_COLOR_ALPHA \
    --output-format c \
    --force \
    "${RESIZED_PNG}"
color_green "Replaced ${LOGO_TARGET_FILE} with new logo data"

# --- Patch update.c for Korean weekday display ---
step "Patching update.c for Korean weekday output"
UPDATE_C="${DISPLAY_REPO}/update.c"
[[ -f "${UPDATE_C}.orig" ]] || cp "${UPDATE_C}" "${UPDATE_C}.orig"
# Always restore from .orig before patching (idempotent)
cp "${UPDATE_C}.orig" "${UPDATE_C}"
python3 - "${UPDATE_C}" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path, 'r', encoding='utf-8').read()
new_body = (
    'void get_current_date_weekday_str(char* buffer, size_t size)\n'
    '{\n'
    '    time_t now = time(NULL);\n'
    '    struct tm* tm_info = localtime(&now);\n'
    '    static const char* kr_weekday[] = {"\\xec\\x9d\\xbc","\\xec\\x9b\\x94","\\xed\\x99\\x94","\\xec\\x88\\x98","\\xeb\\xaa\\xa9","\\xea\\xb8\\x88","\\xed\\x86\\xa0"};\n'
    '    snprintf(buffer, size, "%04d-%02d-%02d %s",\n'
    '             tm_info->tm_year + 1900, tm_info->tm_mon + 1, tm_info->tm_mday,\n'
    '             kr_weekday[tm_info->tm_wday]);\n'
    '}\n'
)
# Locate function signature
m = re.search(r'void\s+get_current_date_weekday_str\s*\([^)]*\)', src)
if not m:
    print('ERROR: signature not found', file=sys.stderr); sys.exit(1)
start = m.start()
# Walk braces to find matching close
brace_open = src.index('{', m.end())
depth = 1
i = brace_open + 1
while i < len(src) and depth > 0:
    if src[i] == '{': depth += 1
    elif src[i] == '}': depth -= 1
    i += 1
if depth != 0:
    print('ERROR: unbalanced braces', file=sys.stderr); sys.exit(1)
new_src = src[:start] + new_body + src[i:]
open(path, 'w', encoding='utf-8').write(new_src)
print('Patched get_current_date_weekday_str() for Korean output')
PYEOF

# --- Korean label translations for LCD UI ---
step "Patching LCD UI labels to Korean"
python3 - "${DISPLAY_REPO}" <<'PYEOF_LABELS'
import os, sys
repo = sys.argv[1]

# Map: (filename, english, korean)
targets = [
    ("kvmui/setup_scr_Monitor.c", '"CPU Used\\n"',  '"CPU \xec\x82\xac\xec\x9a\xa9\xeb\x9f\x89\\n"'),
    ("kvmui/setup_scr_Monitor.c", '"RAM Used\\n"',  '"RAM \xec\x82\xac\xec\x9a\xa9\xeb\x9f\x89\\n"'),
    ("kvmui/setup_scr_Monitor.c", '"CPU Temp"',     '"CPU \xec\x98\xa8\xeb\x8f\x84"'),
    ("kvmui/setup_scr_Network.c", '"IP address"',   '"IP \xec\xa3\xbc\xec\x86\x8c"'),
    ("kvmui/setup_scr_Network.c", '"Mac address\\n"','"MAC \xec\xa3\xbc\xec\x86\x8c\\n"'),
    ("kvmui/setup_scr_Network.c", '"Disconnected"', '"\xec\x97\xb0\xea\xb2\xb0 \xeb\x81\x8a\xea\xb9\x80"'),
    ("kvmui/setup_scr_Version.c", '"Hostname"',     '"\xed\x98\xb8\xec\x8a\xa4\xed\x8a\xb8 \xec\x9d\xb4\xeb\xa6\x84"'),
    ("kvmui/setup_scr_Version.c", '"App Version"',  '"\xec\x95\xb1 \xeb\xb2\x84\xec\xa0\x84"'),
]

# Group by file, restore from .orig, then apply all substitutions
files = {}
for fn, _, _ in targets:
    files.setdefault(fn, [])
for fn, en, kr in targets:
    files[fn].append((en, kr))

for fn, subs in files.items():
    path = os.path.join(repo, fn)
    orig = path + '.orig'
    if not os.path.exists(orig):
        import shutil; shutil.copy(path, orig)
    with open(orig, 'r', encoding='utf-8') as f:
        src = f.read()
    total = 0
    for en, kr in subs:
        # kr contains UTF-8 bytes expressed as \xNN escapes in python source.
        # Those escapes become Latin-1 codepoints; round-trip via latin-1 -> utf-8
        # turns them into proper Korean characters.
        kr_text = kr.encode('latin-1').decode('utf-8')
        n = src.count(en)
        if n == 0:
            print(f'WARN: no match for {en!r} in {fn}', file=sys.stderr)
            continue
        src = src.replace(en, kr_text)
        total += n
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print(f'Patched {fn}: {total} replacement(s)')
PYEOF_LABELS

# --- Build Korean-aware font ---
bash "${PROJECT_ROOT}/scripts/build_korean_font.sh"

# --- Build kvm_display ---
step "Building kvm_display"
pushd "${DISPLAY_REPO}" >/dev/null
LUCKFOX_SDK_PATH="${FAKE_SDK}" make clean >/dev/null 2>&1 || true
LUCKFOX_SDK_PATH="${FAKE_SDK}" make -j"$(nproc)"
popd >/dev/null

NATIVE_BIN="${DISPLAY_REPO}/build/bin/kvm_display"
[[ -x "${NATIVE_BIN}" ]] || fail "Built binary not found: ${NATIVE_BIN}"

# --- Copy into resource/ (keep legacy filename for compatibility with deploy.ps1) ---
step "Updating resource/jetkvm_native (new kvm_display binary)"
cp "${NATIVE_BIN}" "${PROJECT_ROOT}/resource/jetkvm_native"
chmod +x "${PROJECT_ROOT}/resource/jetkvm_native"
( cd "${PROJECT_ROOT}/resource" && sha256sum jetkvm_native | awk '{print $1}' > jetkvm_native.sha256 )

SIZE_KB=$(( $(stat -c%s "${PROJECT_ROOT}/resource/jetkvm_native") / 1024 ))
color_green "Done. resource/jetkvm_native (${SIZE_KB} KB)"
color_green "SHA256: $(cat "${PROJECT_ROOT}/resource/jetkvm_native.sha256")"

cat <<'EOF'

Next steps:
  1. From Windows PowerShell, deploy to the device (both kvm_app and kvm_display):
       .\scripts\deploy.ps1 -DeviceIp <KVM_IP> -DeployDisplay

  2. The device's /etc/init.d/S20updatedata will try to restore the OEM
     kvm_display on reboot. To persist the new binary, also overwrite the
     master at /usr/bin/kvm_display on-device (rootfs is ext4 rw):
       scp resource/jetkvm_native root@<IP>:/usr/bin/kvm_display.new
       ssh  root@<IP> "killall -9 kvm_display kvm_app 2>/dev/null; sleep 2; \
         mv /usr/bin/kvm_display.new /usr/bin/kvm_display && \
         chmod +x /usr/bin/kvm_display && \
         cp /usr/bin/kvm_display /userdata/picokvm/bin/kvm_display && \
         reboot"
EOF
