<#
.SYNOPSIS
  Build and deploy Compuzone KVM to a LuckFox PicoKVM device.

.DESCRIPTION
  Cross-compiles kvm_app for ARMv7 Linux (with frontend embedded) and
  SCPs it to the device at /userdata/picokvm/bin/kvm_app, then restarts
  the app.

.PARAMETER DeviceIp
  IP address of the LuckFox PicoKVM device (e.g. 192.168.0.105).

.PARAMETER User
  SSH user on the device. Default: root

.PARAMETER RemotePath
  Remote path of the kvm_app binary. Default: /userdata/picokvm/bin/kvm_app

.PARAMETER SkipFrontend
  Skip rebuilding the frontend (use existing static/ directory).

.PARAMETER SkipBuild
  Skip building entirely, deploy existing bin/kvm_app.

.PARAMETER SkipRestart
  Do not restart the app after upload (user will manually reboot).

.EXAMPLE
  .\scripts\deploy.ps1 -DeviceIp 192.168.0.105

.EXAMPLE
  .\scripts\deploy.ps1 -DeviceIp 192.168.0.105 -SkipFrontend
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$DeviceIp,

    [string]$User = "root",

    [string]$RemotePath = "/userdata/picokvm/bin/kvm_app",

    [string]$DisplayRemotePath = "/userdata/picokvm/bin/kvm_display",

    [switch]$SkipFrontend,

    [switch]$SkipBuild,

    [switch]$SkipRestart,

    # NOTE: Compuzone fork uses its own proprietary kvm_display binary
    # (different LVGL UI than upstream jetkvm-native). Uploading our
    # rebuilt jetkvm_native here will REPLACE the entire LCD UI design.
    # Default is to NOT upload it. Set this flag to opt in.
    [switch]$DeployDisplay
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# --- Ensure Go is on PATH (common Windows install locations) ---
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    $goCandidates = @(
        "C:\Program Files\Go\bin",
        "C:\Program Files (x86)\Go\bin",
        "$env:LOCALAPPDATA\Programs\Go\bin"
    )
    foreach ($p in $goCandidates) {
        if (Test-Path (Join-Path $p "go.exe")) {
            $env:Path = "$p;$env:Path"
            Write-Host "Added Go to PATH: $p" -ForegroundColor DarkGray
            break
        }
    }
}

if (-not $SkipBuild) {
    if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
        throw "Go is not installed or not on PATH. Install from https://go.dev/dl/"
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "npm is not installed or not on PATH."
    }

    # --- 1. Frontend build ---
    if (-not $SkipFrontend) {
        Write-Step "Building frontend (ui/ -> static/)"
        Push-Location ui
        try {
            npm run build:device
            if ($LASTEXITCODE -ne 0) { throw "npm build failed" }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "Skipping frontend build (-SkipFrontend)" -ForegroundColor Yellow
    }

    # --- 2. Go cross-compile (ARMv7 Linux) ---
    Write-Step "Cross-compiling kvm_app for ARMv7 Linux"
    $env:GOOS = "linux"
    $env:GOARCH = "arm"
    $env:GOARM = "7"
    $env:CGO_ENABLED = "0"

    # Read version from Makefile (fallback to 0.1.2)
    $version = "0.1.2"
    $makefile = Get-Content Makefile -ErrorAction SilentlyContinue
    if ($makefile) {
        $verLine = $makefile | Select-String -Pattern "^VERSION\s*\?=\s*(\S+)" | Select-Object -First 1
        if ($verLine) { $version = $verLine.Matches[0].Groups[1].Value }
    }

    $ldflags = "-s -w -X kvm.builtAppVersion=$version"
    go build -tags netgo -trimpath -ldflags $ldflags -o bin/kvm_app cmd/main.go
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }

    $binInfo = Get-Item bin/kvm_app
    $sizeMB = [math]::Round($binInfo.Length / 1MB, 2)
    Write-Host "Built bin/kvm_app ($sizeMB MB)" -ForegroundColor Green
} else {
    Write-Host "Skipping build (-SkipBuild)" -ForegroundColor Yellow
    if (-not (Test-Path "bin/kvm_app")) {
        throw "bin/kvm_app not found. Build it first or remove -SkipBuild."
    }
}

# --- 3. SCP to device ---
Write-Step "Uploading to ${User}@${DeviceIp}:${RemotePath}"
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    throw "scp not found. Install OpenSSH client: Settings -> Apps -> Optional Features -> OpenSSH Client"
}

# Upload kvm_app to a temp file first, then mv to avoid partial overwrite
$remoteTmp = "$RemotePath.new"
scp bin/kvm_app "${User}@${DeviceIp}:${remoteTmp}"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

# Optionally upload custom kvm_display (LCD UI binary) built from jetkvm-native
$displayTmp = ""
$displayLocal = Join-Path $ProjectRoot "resource/jetkvm_native"
if ($DeployDisplay -and (Test-Path $displayLocal)) {
    Write-Step "Uploading LCD UI binary to ${DisplayRemotePath}"
    $displayTmp = "$DisplayRemotePath.new"
    scp $displayLocal "${User}@${DeviceIp}:${displayTmp}"
    if ($LASTEXITCODE -ne 0) { throw "scp (kvm_display) failed" }
}

Write-Step "Swapping binaries and restarting"
$swapDisplay = if ($displayTmp) {
    " && mv $displayTmp $DisplayRemotePath && chmod +x $DisplayRemotePath"
} else { "" }

$remoteCmd = if ($SkipRestart) {
    "mv $remoteTmp $RemotePath && chmod +x $RemotePath$swapDisplay && echo 'Uploaded. Restart skipped.'"
} else {
    "mv $remoteTmp $RemotePath && chmod +x $RemotePath$swapDisplay && (killall kvm_app kvm_display jetkvm_native 2>/dev/null || true) && echo 'Restarted.'"
}

ssh "${User}@${DeviceIp}" $remoteCmd
if ($LASTEXITCODE -ne 0) { throw "ssh restart failed" }

Write-Host ""
Write-Host "Deployment complete." -ForegroundColor Green
Write-Host "Open the KVM UI: http://$DeviceIp/" -ForegroundColor Green
