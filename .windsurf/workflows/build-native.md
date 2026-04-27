---
description: 단말기 LCD 로고를 컴퓨존 로고로 교체하기 위해 jetkvm-native를 재빌드
---

# jetkvm-native 재빌드 워크플로우 (LCD 로고 교체)

이 워크플로우는 LuckFox PicoKVM 단말기 LCD 화면에 표시되는 로고(`ui_Boot_Logo`)를 컴퓨존 로고로 교체합니다.

## 사전 요구사항

- **WSL Ubuntu 22.04+** 설치 완료 (`wsl --install` 후 재부팅)
- **컴퓨존 로고 PNG 파일** (153x42 권장, 알파 채널 포함)
- 디스크 공간 ~2 GB (buildkit + 빌드 산출물)
- 첫 빌드 시 약 5~10 분 (buildkit 다운로드 포함)

## 단계

1. 사용자에게 컴퓨존 로고 PNG 경로를 확인한다 (예: `D:\logos\compuzone.png`).

2. WSL에서 빌드 스크립트를 실행한다. Windows 경로는 `/mnt/c/...`, `/mnt/d/...` 형태로 변환:

   // turbo
   ```powershell
   wsl bash scripts/build_native.sh /mnt/d/logos/compuzone.png
   ```

3. 빌드가 끝나면 다음이 갱신된다:
   - `resource/jetkvm_native` (새 바이너리)
   - `resource/jetkvm_native.sha256` (해시 갱신)

4. 새 바이너리가 임베드된 `kvm_app` 을 빌드하고 장치에 배포한다:

   ```powershell
   .\scripts\deploy.ps1 -DeviceIp <KVM_IP>
   ```

## 옵션

- 다른 사이즈의 로고 사용 시 자동 리사이즈 (가운데 정렬, 투명 배경 패딩)
- buildkit, jetkvm-native 클론은 한 번만 다운로드되고 이후 캐시됨 (`.build-native/` 디렉터리)

## 트러블슈팅

- **`wsl: command not found`** — Windows에 WSL 미설치. 관리자 PowerShell에서 `wsl --install` 후 재부팅
- **`lv_img_conv` 변환 오류** — PNG가 손상되었거나 알파 채널 없음. ImageMagick으로 변환 시도: `convert input.png PNG32:output.png`
- **`make` 실패** — buildkit 다운로드 미완료. `.build-native/` 폴더 삭제 후 재실행
- **장치에서 새 로고 안 보임** — `kvm_app` 재빌드 필요 (jetkvm_native가 embed 됨). `deploy.ps1` 다시 실행
- **이미지 비율이 안 맞음** — 153x42 (3.6:1) 가 아닌 비율이면 가운데 정렬 + 투명 패딩으로 자동 처리되지만, 원본을 미리 가까운 비율로 만들면 더 깔끔함

## 결과 확인

장치에서 LCD를 보면:
- 부팅 시 컴퓨존 로고 표시
- Home 화면 헤더에도 동일 로고 표시 (`ui_Home_Header_Logo`)
- Network/About 등 다른 화면의 헤더 로고도 같은 이미지 사용
