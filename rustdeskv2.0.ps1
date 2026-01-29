# NN RustDesk Installer Script
# VERSION: NN-RD-2026-01-29-01 (bump this every time you change the script)

$ErrorActionPreference = "Stop"

Write-Host "============================================================"
Write-Host "Nerdy Neighbor RustDesk Installer"
Write-Host "SCRIPT VERSION: NN-RD-2026-01-29-01"
Write-Host "HOST: $env:COMPUTERNAME"
Write-Host "USER: $env:USERNAME"
Write-Host ("PowerShell: {0}  | 64-bit PS Process: {1}  | 64-bit OS: {2}" -f `
    $PSVersionTable.PSVersion, [Environment]::Is64BitProcess, [Environment]::Is64BitOperatingSystem)
Write-Host "============================================================"

# ================= CONFIG =================
$ConfigString   = "=0nI9c2N5Z1QxtGOWdHR0RkRK9ENjRnYJ9kcQtmS4A1VIdXdQpnbEdFdy9GW3dnI6ISeltmIsIiI6ISawFmIsIiI6ISehxWZyJCLiwWYj9GbuIXZ2JXZz5mbiojI0N3boJye"
$RustDeskMsiUrl = "https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.msi"
$MsiPath        = Join-Path $env:TEMP "rustdesk-1.4.5-x86_64.msi"
$TaskName       = "NN-RustDesk-ApplyConfig-Once"

# schtasks path selection (handles WOW64 redirection)
$SchTasksSysnative = "$env:WINDIR\Sysnative\schtasks.exe"
$SchTasksSystem32  = "$env:WINDIR\System32\schtasks.exe"

if (Test-Path $SchTasksSysnative) {
    $SchTasks = $SchTasksSysnative
} else {
    $SchTasks = $SchTasksSystem32
}

Write-Host "[DEBUG] schtasks candidate (Sysnative): $SchTasksSysnative  | exists: $(Test-Path $SchTasksSysnative)"
Write-Host "[DEBUG] schtasks candidate (System32):  $SchTasksSystem32   | exists: $(Test-Path $SchTasksSystem32)"
Write-Host "[DEBUG] schtasks selected:             $SchTasks            | exists: $(Test-Path $SchTasks)"

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
    try { (Get-CimInstance Win32_ComputerSystem).UserName } catch { $null }
}

# ================= INSTALL =================
Write-Host "[*] Downloading RustDesk MSI..."
Invoke-WebRequest -Uri $RustDeskMsiUrl -OutFile $MsiPath -UseBasicParsing

Write-Host "[*] Installing RustDesk silently..."
Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait

$RustDeskExe = Find-RustDeskExeSystemInstall
Write-Host "[DEBUG] RustDeskExe detected: $RustDeskExe"

if (-not $RustDeskExe) {
    throw "RustDesk executable not found in Program Files after install."
}

# Stop any RustDesk running in this admin/session context (safe)
Stop-Process -Name "rustdesk","RustDesk" -Force -ErrorAction SilentlyContinue

# ================= CREATE PER-USER APPLY SCRIPT =================
$ApplyDir = Join-Path $env:ProgramData "NerdyNeighbor\RustDesk"
$ApplyPs1 = Join-Path $ApplyDir "Apply-RustDesk-Config.ps1"
New-Item -ItemType Directory -Path $ApplyDir -Force | Out-Null

@"
`$ErrorActionPreference = 'Stop'
Write-Host "NN Apply Script running as user: `$env:USERNAME on `$env:COMPUTERNAME"
`$TaskName = '$TaskName'
`$SchTasks = `"$SchTasks`"
`$Exe      = `"$RustDeskExe`"
`$Cfg      = `"$ConfigString`"

# Stop RustDesk in the user session (safe)
Get-Process -Name rustdesk,RustDesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Apply config (writes to THIS user's profile)
Start-Process -FilePath `$Exe -ArgumentList "--config `"`$Cfg`"" -Wait

# One-shot cleanup: remove scheduled task so it only runs once
& `$SchTasks /Delete /TN `$TaskName /F 2>`$null | Out-Null
"@ | Set-Content -Path $ApplyPs1 -Encoding UTF8 -Force

Write-Host "[DEBUG] Apply script written: $ApplyPs1"

# ================= SCHEDULE TASK =================
$InteractiveUser = Get-InteractiveUser
Write-Host "[DEBUG] Interactive user: $InteractiveUser"

# Delete task if present (ignore errors)
try {
    & $SchTasks /Delete /TN $TaskName /F 2>$null | Out-Null
    Write-Host "[DEBUG] Deleted existing task (if it existed)."
} catch {
    Write-Host "[DEBUG] Task delete threw, but continuing: $($_.Exception.Message)"
}

# Create ONLOGON task (runs as the user who logs on)
$TaskCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ApplyPs1`""
Write-Host "[DEBUG] Creating task with TR: $TaskCmd"

& $SchTasks /Create /TN $TaskName /SC ONLOGON /RL HIGHEST /TR $TaskCmd /F | Out-Null
Write-Host "[*] Scheduled per-user config apply task created: $TaskName"

# Trigger immediately if user is logged in
if ($InteractiveUser) {
    Write-Host "[*] Triggering task now..."
    & $SchTasks /Run /TN $TaskName | Out-Null
    Write-Host "[✓] Triggered."
} else {
    Write-Host "[!] No interactive user logged in. Will apply on next login."
}

Write-Host "[✓] RustDesk installed. Config will apply per-user via scheduled task."
