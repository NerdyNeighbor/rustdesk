# Nerdy Neighbor - RustDesk Installer (EXE) + Config + Password
# VERSION: NN-RD-EXE-2026-01-29-01

$ErrorActionPreference = "Stop"

Write-Output "==============================="
Write-Output "Nerdy Neighbor RustDesk Deploy"
Write-Output "SCRIPT VERSION: NN-RD-EXE-2026-01-29-01"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "User: $env:USERNAME"
Write-Output "PS: $($PSVersionTable.PSVersion) | 64-bit: $([Environment]::Is64BitProcess)"
Write-Output "==============================="

# ---- CONFIG ----
$rustdesk_cfg = "=0nI9c2N5Z1QxtGOWdHR0RkRK9ENjRnYJ9kcQtmS4A1VIdXdQpnbEdFdy9GW3dnI6ISeltmIsIiI6ISawFmIsIiI6ISehxWZyJCLiwWYj9GbuIXZ2JXZz5mbiojI0N3boJye"

# Pin a known version (recommended for stability)
$rustdesk_url = "https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.exe"

# Random 12-char password (letters only like their script)
$rustdesk_pw = (-join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_}))

# ---- Ensure admin (auto-elevate if launched interactively) ----
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    # If you're running this in a non-interactive remote shell, elevation won't work.
    # In that case, run the script from an already-elevated context (RMM/System/admin).
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& '$PSCommandPath'`""
    exit
}

# ---- Download ----
$work = "C:\Temp"
if (!(Test-Path $work)) { New-Item -ItemType Directory -Force -Path $work | Out-Null }
$exe = Join-Path $work "rustdesk.exe"

Write-Output "[*] Downloading RustDesk EXE..."
Invoke-WebRequest -Uri $rustdesk_url -OutFile $exe -UseBasicParsing

# ---- Install silently ----
Write-Output "[*] Installing RustDesk..."
Start-Process -FilePath $exe -ArgumentList "--silent-install" -Wait

# ---- Install/Start service ----
$ServiceName = "RustDesk"
Start-Sleep -Seconds 5

$arrService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $arrService) {
    Write-Output "[*] Installing RustDesk service..."
    $rdPath = Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"
    if (!(Test-Path $rdPath)) { throw "RustDesk not found at $rdPath after install." }
    Start-Process -FilePath $rdPath -ArgumentList "--install-service" -Wait
    Start-Sleep -Seconds 5
    $arrService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
}

if ($arrService.Status -ne "Running") {
    Write-Output "[*] Starting RustDesk service..."
    Start-Service $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

# ---- Apply config + set password ----
$rdExe = Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"
if (!(Test-Path $rdExe)) { $rdExe = Join-Path $env:ProgramFiles "RustDesk\RustDesk.exe" }
if (!(Test-Path $rdExe)) { throw "RustDesk executable not found in Program Files." }

Write-Output "[*] Applying config..."
& $rdExe --config $rustdesk_cfg | Out-Null

Write-Output "[*] Setting password..."
& $rdExe --password $rustdesk_pw | Out-Null

Write-Output "[*] Getting RustDesk ID..."
$rustdesk_id = (& $rdExe --get-id) -join "`n"

Write-Output "--------------------------------"
Write-Output "RustDesk ID: $rustdesk_id"
Write-Output "Password:   $rustdesk_pw"
Write-Output "--------------------------------"
Write-Output "[✓] Done."
