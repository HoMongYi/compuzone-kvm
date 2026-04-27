---
description: LuckFox PicoKVM 장치에 Compuzone KVM 앱을 빌드 및 배포
---

# Compuzone KVM 배포 워크플로우

이 워크플로우는 프런트엔드를 빌드하고 Go 바이너리를 ARMv7 Linux로 크로스 컴파일한 뒤 SCP로 LuckFox PicoKVM 장치에 업로드하고 앱을 재시작합니다.

## 사전 요구사항

- Windows PowerShell
- Go 1.23+ (https://go.dev/dl/)
- Node.js 18+ / npm
- OpenSSH Client (`scp`, `ssh`) — Windows 10/11 기본 포함
- LuckFox PicoKVM 장치 IP 주소 및 SSH 접근 (기본 user: `root`)

## 단계

1. 사용자에게 장치 IP를 확인받는다. 모르면 다음과 같이 물어본다:

   > "LuckFox PicoKVM 장치의 IP 주소를 알려주세요 (예: 192.168.0.105)"

2. 배포 스크립트를 실행한다. `$DEVICE_IP` 를 사용자가 준 값으로 치환.

   // turbo
   ```powershell
   .\scripts\deploy.ps1 -DeviceIp $DEVICE_IP
   ```

3. 완료 후 `http://$DEVICE_IP/` 에서 UI를 확인하라고 안내한다.

## 옵션 플래그

- `-SkipFrontend` : `static/` 이미 최신이면 프런트엔드 빌드 스킵
- `-SkipBuild` : 기존 `bin/kvm_app` 재사용
- `-SkipRestart` : 파일만 업로드하고 앱 재시작은 수동으로
- `-User <name>` : SSH 사용자 (기본 `root`)
- `-RemotePath <path>` : 장치상 바이너리 경로 (기본 `/userdata/picokvm/bin/kvm_app`)

## 빠른 예시

```powershell
# 전체 빌드 + 배포
.\scripts\deploy.ps1 -DeviceIp 192.168.0.105

# UI만 바뀌었을 때 (프런트엔드 + Go 재빌드)
.\scripts\deploy.ps1 -DeviceIp 192.168.0.105

# Go 코드만 바뀌었을 때 (프런트 스킵)
.\scripts\deploy.ps1 -DeviceIp 192.168.0.105 -SkipFrontend

# 이미 빌드된 바이너리 재배포
.\scripts\deploy.ps1 -DeviceIp 192.168.0.105 -SkipBuild
```

## 트러블슈팅

- **`go: command not found`** — Go 설치 후 PowerShell 재시작 필요. 스크립트는 `C:\Program Files\Go\bin`, `C:\Program Files (x86)\Go\bin`, `%LOCALAPPDATA%\Programs\Go\bin` 을 자동 탐색.
- **`scp: command not found`** — Windows 설정 → 앱 → 선택적 기능 → OpenSSH 클라이언트 설치
- **SSH 비밀번호 매번 입력** — `ssh-keygen` 으로 키 생성 후 `ssh-copy-id` 대신 수동으로 `~/.ssh/authorized_keys` 에 공개키 복사 (장치에서)
- **앱이 재시작 안됨** — systemd 서비스명을 알아야 하는 경우, 장치에서 `systemctl list-units | grep -i kvm` 으로 확인. 기본 스크립트는 `killall kvm_app` 로 종료만 시키고, 장치의 watchdog/init 가 자동 재시작하는 것을 가정.
