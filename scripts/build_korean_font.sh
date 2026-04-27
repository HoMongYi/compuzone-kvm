#!/usr/bin/env bash
# Build LVGL 16px font combining Montserrat-Medium (Latin) + NanumGothic (Korean weekday glyphs)
# Output replaces kvmui/lv_font_montserratMedium_16.c (variable name preserved).
#
# Korean weekday characters (only what we need on LCD):
#   일 U+C77C  월 U+C6D4  화 U+D654  수 U+C218  목 U+BAA9  금 U+AE08  토 U+D1A0
#
# Usage:  bash scripts/build_korean_font.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${PROJECT_ROOT}/.build-native"
DISPLAY_REPO="${WORK_DIR}/kvm_display"
FONT_DIR="${WORK_DIR}/fonts"
mkdir -p "${FONT_DIR}"

LV_FONT_CONV="${WORK_DIR}/node_modules/.bin/lv_font_conv"

color_green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
color_cyan()  { printf '\033[0;36m%s\033[0m\n' "$*"; }
fail() { printf '\033[0;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ -d "${DISPLAY_REPO}" ]] || fail "kvm_display repo missing. Run scripts/build_native.sh first."

# Install lv_font_conv if missing
if [[ ! -x "${LV_FONT_CONV}" ]]; then
    color_cyan "==> Installing lv_font_conv"
    pushd "${WORK_DIR}" >/dev/null
    npm install --no-fund --no-audit lv_font_conv
    popd >/dev/null
fi

# Main text font (Latin + Korean glyphs) -- expected to be pre-placed by user
MAIN_FONT="${FONT_DIR}/NanumSquareRoundB.ttf"
[[ -s "${MAIN_FONT}" ]] || fail "Place NanumSquareRoundB.ttf at ${MAIN_FONT}"

# LVGL Font Awesome (provides LV_SYMBOL_* glyphs in PUA range U+F000-U+F8FF)
FA_FONT="${FONT_DIR}/FontAwesome5-Solid+Brands+Regular.woff"
if [[ ! -s "${FA_FONT}" ]]; then
    color_cyan "==> Downloading LVGL Font Awesome"
    rm -f "${FA_FONT}"
    URLS=(
        "https://cdn.jsdelivr.net/gh/lvgl/lvgl@release/v8.3/scripts/built_in_font/FontAwesome5-Solid+Brands+Regular.woff"
        "https://raw.githubusercontent.com/lvgl/lvgl/release/v8.3/scripts/built_in_font/FontAwesome5-Solid%2BBrands%2BRegular.woff"
        "https://fastly.jsdelivr.net/gh/lvgl/lvgl@release/v8.3/scripts/built_in_font/FontAwesome5-Solid+Brands+Regular.woff"
    )
    for url in "${URLS[@]}"; do
        color_cyan "    trying ${url}"
        if curl -fL --max-time 60 -o "${FA_FONT}" "${url}" && [[ -s "${FA_FONT}" ]]; then
            color_green "    downloaded $(stat -c%s "${FA_FONT}") bytes"
            break
        fi
        rm -f "${FA_FONT}"
    done
fi
[[ -s "${FA_FONT}" ]] || fail "Font Awesome download failed"

# Korean glyphs used on LCD:
#   Weekdays: 일 월 화 수 목 금 토
#   Labels:   주 소 연 결 끊 김 사 용 량 온 도 앱 버 전 호 스 트 이 름
#   VPN:      됨 로 그 인  (연결됨, 로그인됨, 연결 끊김 — sent from kvm_app)
KR_RANGE="0xC77C,0xC6D4,0xD654,0xC218,0xBAA9,0xAE08,0xD1A0,0xC8FC,0xC18C,0xC5F0,0xACB0,0xB04A,0xAE40,0xC0AC,0xC6A9,0xB7C9,0xC628,0xB3C4,0xC571,0xBC84,0xC804,0xD638,0xC2A4,0xD2B8,0xC774,0xB984,0xB428,0xB85C,0xADF8,0xC778"

# LVGL symbols actually used in kvm_display:
#   LV_SYMBOL_UP=0xF077  DOWN=0xF078  UPLOAD=0xF093  DOWNLOAD=0xF019
LV_SYMBOLS="0xF019,0xF077,0xF078,0xF093"

# Regenerate all Montserrat Medium sizes used by the UI so every label that
# shows Korean text can render properly.
for SIZE in 14 16 18 32; do
    VAR="lv_font_montserratMedium_${SIZE}"
    OUT="${DISPLAY_REPO}/kvmui/${VAR}.c"
    [[ -f "${OUT}" ]] || { color_cyan "Skip ${VAR} (file missing)"; continue; }
    [[ -f "${OUT}.orig" ]] || cp "${OUT}" "${OUT}.orig"

    color_cyan "==> Generating ${VAR} (NanumSquareRoundB + Font Awesome)"
    "${LV_FONT_CONV}" \
        --bpp 4 --size "${SIZE}" --format lvgl --no-compress --no-prefilter \
        --font "${MAIN_FONT}" --range 0x20-0x7F,0xA0-0xFF,${KR_RANGE} \
        --font "${FA_FONT}" --range "${LV_SYMBOLS}" \
        --lv-font-name "${VAR}" \
        -o "${OUT}"

    # Some lv_font_conv versions ignore --lv-font-name; ensure variable name matches
    if ! grep -q "lv_font_t ${VAR}" "${OUT}" 2>/dev/null; then
        GEN_NAME="$(grep -oE 'lv_font_t [A-Za-z_0-9]+ =' "${OUT}" | head -1 | awk '{print $2}')"
        if [[ -n "${GEN_NAME}" && "${GEN_NAME}" != "${VAR}" ]]; then
            sed -i "s/\b${GEN_NAME}\b/${VAR}/g" "${OUT}"
        fi
    fi
    SIZE_KB=$(( $(stat -c%s "${OUT}") / 1024 ))
    color_green "    ${VAR}.c (${SIZE_KB} KB)"
done
