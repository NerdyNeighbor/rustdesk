# Nerdy Neighbor - RustDesk Silent Installer + Auto Config (per-logged-in user)
# Purpose:
# - Install RustDesk MSI silently (admin context)
# - Apply server config in the *interactive user* context (RustDesk config is per-user)
# - Works reliably in remote PowerShell/admin sessions (uses full path to schtasks.exe)

$ErrorActionPreference = "Stop"

# ================= CONFIG =================
$ConfigString   = "=0nI9c2N5Z1QxtGOWdHR0RkRK9ENjRnYJ9kcQtmS4A1VIdXdQpnbEdFdy9GW3dnI6ISeltmIsIiI6ISawFmIsIiI6ISehxWZyJCLiwWYj9GbuIXZ2JXZz5mbiojI0N3boJye"
$RustDeskMsiUrl = "https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.msi"
$MsiPath        = Join-Path $env:TEMP "rustdesk-1.4.5-x86_64.msi"

$TaskName = "NN-RustDesk-ApplyConfig-Once"
$SchTasks = Join-Path $env:WINDIR "System32\schtasks.exe"

# ================= FUNCTIONS =================
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
    # Returns DOMAIN\User for the console session, if someone is logged in; otherwise $null
    try {
        (Get-CimInstance Win32_ComputerSystem).UserName
    } catch {
        $null
    }
}

# ================= PRECHECKS =================
if (-not (Test-Path $SchTasks)) {
    throw "schtasks.exe not found at expected path: $SchTasks"
}

# ================= INSTALL =================
Write-Host "[*] Downloading RustDesk MSI..."
Invoke-WebRequest -Uri $RustDeskMsiUrl -OutFile $MsiPath -UseBasicParsing

Write-Host "[*] Installing RustDesk silently..."
Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait

$RustDeskExe = Find-RustDeskExeSystemInstall
if (-not $RustDeskExe) {
    throw "RustDesk executable not found in Program Files after install."
}

# Stop any RustDesk running in this admin/session context (safe)
Stop-Process -Name "rustdesk","RustDesk" -Force -ErrorAction SilentlyContinue

# ================= CREATE PER-USER APPLY SCRIPT =================
$ApplyDir = Join-Path $env:ProgramData "NerdyNeighbor\RustDesk"
$ApplyPs1 = Join-Path $ApplyDir "Apply-RustDesk-Config.ps1"
New-Item -ItemType Directory -Path $ApplyDir -Force | Out-Null

# Write a script that runs as the interactive user, applies config, then deletes the scheduled task (one-shot)
@"
`$ErrorActionPreference = 'Stop'

`$TaskName = '$TaskName'
`$SchTasks = `"$SchTasks`"
`$Exe      = `"$RustDeskExe`"
`$Cfg      = `"$ConfigString`"

# Stop RustDesk in the user session (safe)
Get-Process -Name rustdesk,RustDesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Apply config (writes to THIS user's profile)
Start-Process -FilePath `$Exe -ArgumentList "--config `"`$Cfg`"" -Wait

# Optional: launch RustDesk after config
# Start-Process -FilePath `$Exe | Out-Null

# One-shot cleanup: remove scheduled task so it only runs once
& `$SchTasks /Delete /TN `$TaskName /F 2>`$null | Out-Null
"@ | Set-Content -Path $ApplyPs1 -Encoding UTF8 -Force

# ================= SCHEDULE TASK =================
$InteractiveUser = Get-InteractiveUser

# Remove existing task if present (do NOT treat as fatal)
& $SchTasks /Delete /TN $TaskName /F 2>$null | Out-Null

# Create a task that runs at next logon. Use "Users" group so it runs in the logged-on user's context.
# (No password required; runs when the user logs on interactively.)
$TaskCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ApplyPs1`""
& $SchTasks /Create `
    /TN $TaskName `
    /SC ONLOGON `
    /RL HIGHEST `
    /TR $TaskCmd `
    /F | Out-Null

Write-Host "[*] Scheduled per-user config apply task created: $TaskName"
Write-Host "    Apply script: $ApplyPs1"

# If a user is currently logged in, trigger immediately
if ($InteractiveUser) {
    Write-Host "[*] Interactive user detected ($InteractiveUser). Triggering task now..."
    & $SchTasks /Run /TN $TaskName | Out-Null
    Write-Host "[✓] Triggered. Config should apply in that user's profile within a few seconds."
} else {
    Write-Host "[!] No interactive user currently logged in. Config will apply at the next user logon."
}

Write-Host "[✓] RustDesk installed. Config will apply per-user via scheduled task."
