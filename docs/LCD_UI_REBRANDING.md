# LCD UI 리브랜딩 — 컴퓨존 펌웨어 팀 요청 가이드

## 배경

LuckFox PicoKVM 본체에는 작은 컬러 LCD가 있고, 거기에 노란 여우 로고 + 시계 + HDMI/USB 카드 형태의 UI가 표시됩니다. 이 UI를 컴퓨존 브랜딩으로 변경하기 위해 필요한 정보를 정리합니다.

## 우리가 알아낸 사실

장치 내부 동작 분석 결과:

1. **LCD UI는 별도 데몬**: `/userdata/picokvm/bin/kvm_display` 라는 ARMv7 LVGL 바이너리가 LCD를 그립니다 (`kvm_app` 과 분리된 프로세스).
2. **마스터 위치**: `/usr/bin/kvm_display` (rootfs ext4 RW). SHA256 `66989d50e9205ce4a15a83941e984c888f5f2675ad35f9dc385271b863323bde`, 크기 1,579,632 bytes.
3. **자동 동기화**: 부팅 시 `S20updatedata` init 스크립트가 `/usr/bin/kvm_*` → `/userdata/picokvm/bin/` 로 복사 (cmp 후 다르면 덮어씀). 따라서 `/userdata/...` 만 교체해서는 재부팅 시 복원됨.
4. **소스 비공개**: `kvm_display` 는 **상용 jetkvm-native가 아닌 컴퓨존(또는 LuckFox) 자체 LVGL 앱**입니다. 디자인이 jetkvm-native 와 완전히 다릅니다 (sidebar 형태가 아닌 시계/카드 형태).
5. **시도 결과**: jetkvm-native 오픈소스를 빌드해서 `kvm_display` 자리에 넣으면 LCD UI 디자인 자체가 jetkvm 디자인으로 바뀌어 컴퓨존 디자인이 사라집니다 — 따라서 사용 불가.

## 컴퓨존 펌웨어 팀에 요청할 것

### A. 필수 — 다음 중 하나
1. **`kvm_display` 소스코드 전체** (가장 깔끔)
   - LVGL 8.x 기반 SquareLine Studio 프로젝트일 가능성이 높음
   - 부팅/홈/네트워크/About 등 화면 .c 파일 + 이미지 (`ui_img_*.c`)
   - Makefile + lv_conf.h
2. **로고 이미지 자산만이라도** + 빌드 도구 정보
   - LCD에 표시되는 모든 로고 이미지 원본 (PNG/SVG)
   - 어떤 LVGL 버전, 어떤 빌드 환경 (Rockchip RV1106 buildkit 버전)

### B. 빌드 환경 정보
- 사용 중인 cross-toolchain (예: `arm-rockchip830-linux-uclibcgnueabihf-gcc`)
- LVGL 버전 (8.3.6 추정)
- 의존하는 외부 라이브러리 (`-lrockit -lrockchip_mpp -lrga` 등)

### C. 변경하고 싶은 것
- **부팅 화면 로고**: 노란 여우 → 컴퓨존 로고
- **홈 화면 헤더 로고** (있다면): 동일
- 텍스트 라벨이 한국어인지 영어인지 (현재는 영어 "HDMI", "USB" 등) — 한국어로 가능한지

## 우리가 이미 준비한 자산
요청 시 함께 전달:

| 파일 | 용도 |
|---|---|
| `compuzone-logo-153x42.png` | 153x42 가로형 로고 (LCD 부팅 화면 권장 사이즈) |
| `ui/src/assets/logo-compuzone.svg` | 318x48 가로형 로고 (벡터, 고해상도) |
| `compuzone.jpg` | 정사각형 컴퓨존 로고 |
| `scripts/build_native.sh` | 우리가 만든 jetkvm-native 빌드 자동화 스크립트 (참고용 — RV1106 buildkit 사용 방식) |

## 임시 대안 (소스 입수 어려울 경우)

**바이너리 hex patch**: 현재 `kvm_display` 바이너리 안에서 로고 PNG/이미지 데이터의 위치를 찾아 직접 hex 교체. 절차:
1. `/usr/bin/kvm_display` 를 PC로 복사
2. `binwalk` 또는 `strings` + hex editor 로 LVGL `lv_img_dsc_t` 구조체 또는 PNG/JPEG 헤더 식별
3. 같은 크기/포맷의 새 이미지 데이터로 hex overwrite (변수 위치/크기 변경 불가)
4. SHA256 갱신 후 `/usr/bin/kvm_display` + `/userdata/picokvm/bin/kvm_display` 동시 교체

위험: 잘못 교체 시 LCD 검은 화면. 백업 필수: `cp /usr/bin/kvm_display /usr/bin/kvm_display.orig`

## 현재 상태 (2026-04-27 기준)

- ✅ 웹 UI: 컴퓨존 브랜딩 + 한국어 (573 키) 완료
- ✅ 배포 자동화: `scripts/deploy.ps1` (kvm_app 빌드/배포)
- ✅ jetkvm-native 빌드 도구: `scripts/build_native.sh` (소스 입수 시 즉시 활용 가능)
- ⏸ LCD UI: **컴퓨존 자체 `kvm_display` 소스 입수 대기**
