# Nerdy Neighbor - RustDesk Deploy (EXE install + deterministic config apply)
# VERSION: NN-RD-FINAL-2026-01-29-01
# - Installs RustDesk 1.4.5 silently (EXE)
# - Installs/starts RustDesk service
# - Writes RustDesk2.toml directly (reliable; avoids flaky --config import)
# - Sets unattended password
# - Prints RustDesk ID + password + shows config file path

$ErrorActionPreference = "Stop"

Write-Output "==============================="
Write-Output "Nerdy Neighbor RustDesk Deploy"
Write-Output "SCRIPT VERSION: NN-RD-FINAL-2026-01-29-01"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "User: $env:USERNAME"
Write-Output "PS: $($PSVersionTable.PSVersion) | 64-bit: $([Environment]::Is64BitProcess)"
Write-Output "==============================="

# ---------- YOUR SERVER SETTINGS ----------
$IdServer    = "nnserver.local:21116"   # hbbs
$RelayServer = "nnserver.local:21117"   # hbbr
$Key         = "wwXortWDnzPuwHWP8JkPrOIbtc4OJFDtDwV8kqCVy7g="

# Pin known-good version (stable deployments)
$RustDeskExeUrl = "https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.exe"

# Generate random 12-char password (letters only)
$RustDeskPassword = (-join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_}))

# ---------- REQUIRE ADMIN ----------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { throw "Not running as Administrator. Run from an elevated/admin context." }

# ---------- DOWNLOAD + INSTALL ----------
$WorkDir = "C:\Temp"
if (!(Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }
$BootstrapExe = Join-Path $WorkDir "rustdesk-bootstrap.exe"

Write-Output "[*] Downloading RustDesk EXE..."
Invoke-WebRequest -Uri $RustDeskExeUrl -OutFile $BootstrapExe -UseBasicParsing

Write-Output "[*] Installing RustDesk silently..."
Start-Process -FilePath $BootstrapExe -ArgumentList "--silent-install" -Wait

# Installed binaries (RustDesk uses both names depending on build)
$RdCli = Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"
$RdGui = Join-Path $env:ProgramFiles "RustDesk\RustDesk.exe"
if (!(Test-Path $RdCli)) { throw "RustDesk CLI not found: $RdCli" }
if (!(Test-Path $RdGui)) { Write-Output "[!] RustDesk GUI not found at $RdGui (OK)" }

# ---------- SERVICE SETUP (NO HANGS) ----------
$ServiceName = "RustDesk"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

# Kill any running RustDesk processes to avoid lock/config weirdness
Write-Output "[*] Cleaning up RustDesk processes..."
Get-Process -Name rustdesk,RustDesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

if (-not $svc) {
    Write-Output "[*] Installing RustDesk service..."
    Start-Process -FilePath $RdCli -ArgumentList "--install-service"  # no -Wait (can hang)
    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Seconds 2
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    } until ($svc -or (Get-Date) -gt $deadline)
    if (-not $svc) { throw "RustDesk service did not appear within 45 seconds." }
} else {
    Write-Output "[*] RustDesk service already exists. Skipping service install."
}

Write-Output "[*] Ensuring RustDesk service is running..."
try { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue } catch {}
$deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
} until (($svc -and $svc.Status -eq "Running") -or (Get-Date) -gt $deadline)

Write-Output "[DEBUG] Service status: $($svc.Status)"

# ---------- DETERMINISTIC CONFIG APPLY (per-user GUI) ----------
# RustDesk GUI reads this file:
$CfgDir  = Join-Path $env:APPDATA "RustDesk\config"
$CfgFile = Join-Path $CfgDir "RustDesk2.toml"

Write-Output "[*] Writing RustDesk2.toml (authoritative GUI config)..."
Write-Output "    ID Server:    $IdServer"
Write-Output "    Relay Server: $RelayServer"

New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null

@"
rendezvous_server = '$IdServer'
relay_server = '$RelayServer'
key = '$Key'

[options]
stop-service = 'N'
"@ | Set-Content -Path $CfgFile -Encoding UTF8 -Force

# Restart service to ensure it re-reads settings cleanly
Write-Output "[*] Restarting RustDesk service..."
try { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
try { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2

# ---------- SET PASSWORD + GET ID ----------
Write-Output "[*] Setting unattended password..."
& $RdCli --password $RustDeskPassword | Out-Null

Write-Output "[*] Getting RustDesk ID..."
$RustDeskId = (& $RdCli --get-id) -join "`n"

Write-Output "--------------------------------"
Write-Output "Config file: $CfgFile"
Write-Output "RustDesk ID: $RustDeskId"
Write-Output "Password:   $RustDeskPassword"
Write-Output "--------------------------------"
Write-Output "[✓] Done."
