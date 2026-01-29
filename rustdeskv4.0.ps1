# Nerdy Neighbor - RustDesk Installer (EXE) + Config + Password (Hardened)
# VERSION: NN-RD-EXE-2026-01-29-02

$ErrorActionPreference = "Stop"

Write-Output "==============================="
Write-Output "Nerdy Neighbor RustDesk Deploy"
Write-Output "SCRIPT VERSION: NN-RD-EXE-2026-01-29-02"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "User: $env:USERNAME"
Write-Output "PS: $($PSVersionTable.PSVersion) | 64-bit: $([Environment]::Is64BitProcess)"
Write-Output "==============================="

# ---- CONFIG ----
$rustdesk_cfg = "=0nI9c2N5Z1QxtGOWdHR0RkRK9ENjRnYJ9kcQtmS4A1VIdXdQpnbEdFdy9GW3dnI6ISeltmIsIiI6ISawFmIsIiI6ISehxWZyJCLiwWYj9GbuIXZ2JXZz5mbiojI0N3boJye"
$rustdesk_url = "https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.exe"

# Random 12-char password (letters only)
$rustdesk_pw = (-join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_}))

# ---- Require admin (if non-interactive remote shell, you must already be elevated) ----
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { throw "Not running as Administrator. Run this from an elevated/admin context." }

# ---- Download EXE ----
$work = "C:\Temp"
if (!(Test-Path $work)) { New-Item -ItemType Directory -Force -Path $work | Out-Null }
$bootstrap = Join-Path $work "rustdesk.exe"

Write-Output "[*] Downloading RustDesk EXE..."
Invoke-WebRequest -Uri $rustdesk_url -OutFile $bootstrap -UseBasicParsing

# ---- Silent install (does not hang) ----
Write-Output "[*] Installing RustDesk..."
Start-Process -FilePath $bootstrap -ArgumentList "--silent-install" -Wait

# ---- Locate installed binaries ----
$rdCli = Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"
$rdGui = Join-Path $env:ProgramFiles "RustDesk\RustDesk.exe"
if (!(Test-Path $rdCli)) { throw "RustDesk CLI not found: $rdCli" }
if (!(Test-Path $rdGui)) { Write-Output "[!] RustDesk GUI not found at $rdGui (okay)" }

# ---- Service handling (no hangs) ----
$ServiceName = "RustDesk"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (-not $svc) {
    Write-Output "[*] Installing RustDesk service..."
    Start-Process -FilePath $rdCli -ArgumentList "--install-service"  # no -Wait (can hang)
    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Seconds 2
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    } until ($svc -or (Get-Date) -gt $deadline)
    if (-not $svc) { throw "RustDesk service did not appear within 45 seconds." }
} else {
    Write-Output "[*] RustDesk service already exists. Skipping service install."
}

# Ensure service running
Write-Output "[*] Ensuring RustDesk service is running..."
try { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue } catch {}

$deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
} until (($svc -and $svc.Status -eq "Running") -or (Get-Date) -gt $deadline)

Write-Output "[DEBUG] Service status: $($svc.Status)"

# ---- Kill extra RustDesk GUI instances (you have multiple) ----
# Keep the service alive; kill only non-service copies if possible.
# If we can't reliably distinguish, we do a gentle cleanup: stop all, then start service again.
Write-Output "[*] Cleaning up extra RustDesk processes..."
Get-Process -Name rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Start service again
try { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2

# ---- Apply config + password using CLI ----
Write-Output "[*] Applying config..."
& $rdCli --config $rustdesk_cfg | Out-Null

Write-Output "[*] Setting password..."
& $rdCli --password $rustdesk_pw | Out-Null

Write-Output "[*] Getting RustDesk ID..."
$rustdesk_id = (& $rdCli --get-id) -join "`n"

Write-Output "--------------------------------"
Write-Output "RustDesk ID: $rustdesk_id"
Write-Output "Password:   $rustdesk_pw"
Write-Output "--------------------------------"
Write-Output "[✓] Done."
