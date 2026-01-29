# Nerdy Neighbor - RustDesk Silent Installer + Apply Config as Logged-in User
$ErrorActionPreference = "Stop"

# ================= CONFIG =================
$ConfigString   = "=0nI9c2N5Z1QxtGOWdHR0RkRK9ENjRnYJ9kcQtmS4A1VIdXdQpnbEdFdy9GW3dnI6ISeltmIsIiI6ISawFmIsIiI6ISehxWZyJCLiwWYj9GbuIXZ2JXZz5mbiojI0N3boJye"
$RustDeskMsiUrl = "https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.msi"
$MsiPath        = Join-Path $env:TEMP "rustdesk-1.4.5-x86_64.msi"
$TaskName       = "NN-RustDesk-ApplyConfig-Once"

function Find-RustDeskExeSystemInstall {
    $paths = @(
        (Join-Path $env:ProgramFiles "RustDesk\RustDesk.exe"),
        (Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "RustDesk\RustDesk.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "RustDesk\rustdesk.exe")
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-InteractiveUser {
    # Returns DOMAIN\User for the console session, if someone is logged in
    $cs = Get-CimInstance Win32_ComputerSystem
    return $cs.UserName  # null if nobody logged in
}

Write-Host "[*] Downloading RustDesk MSI..."
Invoke-WebRequest -Uri $RustDeskMsiUrl -OutFile $MsiPath -UseBasicParsing

Write-Host "[*] Installing RustDesk silently..."
Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait

$RustDeskExe = Find-RustDeskExeSystemInstall
if (-not $RustDeskExe) {
    throw "RustDesk executable not found in Program Files after install."
}

# Kill any running RustDesk (either name)
Stop-Process -Name "rustdesk","RustDesk" -Force -ErrorAction SilentlyContinue

# Create a small per-user apply script somewhere all users can read
$ApplyDir  = Join-Path $env:ProgramData "NerdyNeighbor\RustDesk"
$ApplyPs1  = Join-Path $ApplyDir "Apply-RustDesk-Config.ps1"
New-Item -ItemType Directory -Path $ApplyDir -Force | Out-Null

@"
`$ErrorActionPreference = 'Stop'
`$exe = `"$RustDeskExe`"
`$cfg = `"$ConfigString`"

# Ensure RustDesk isn't already running in the user session
Get-Process -Name rustdesk,RustDesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Apply config (writes to THIS user's profile)
Start-Process -FilePath `$exe -ArgumentList "--config `"`$cfg`"" -Wait

# Optional: launch RustDesk after config
# Start-Process -FilePath `$exe

# Self-delete the scheduled task so it only runs once
schtasks /Delete /TN `"$TaskName`" /F | Out-Null
"@ | Set-Content -Path $ApplyPs1 -Encoding UTF8 -Force

# Determine if an interactive user is logged in
$InteractiveUser = Get-InteractiveUser

# Create/replace the scheduled task: run once at next logon of ANY user, then self-delete
# (We use "Users" group so it will run in the context of whoever logs in)
schtasks /Delete /TN $TaskName /F 2>$null | Out-Null

$TaskCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ApplyPs1`""
schtasks /Create /TN $TaskName /SC ONLOGON /RL HIGHEST /TR $TaskCmd /F | Out-Null

Write-Host "[*] Scheduled per-user config apply task created: $TaskName"

if ($InteractiveUser) {
    Write-Host "[*] Interactive user detected ($InteractiveUser). Triggering task now..."
    schtasks /Run /TN $TaskName | Out-Null
    Write-Host "[✓] Triggered. Config should apply in that user's profile within a few seconds."
} else {
    Write-Host "[!] No interactive user currently logged in. Config will apply at the next user logon."
}

Write-Host "[✓] RustDesk installed. Config will apply per-user via scheduled task."
