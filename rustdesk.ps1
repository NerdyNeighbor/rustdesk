# Nerdy Neighbor - RustDesk Silent Installer + Auto Config
# Runs clean with: ExecutionPolicy Bypass (per-process)
# Installs RustDesk 1.4.5 and applies server config

$ErrorActionPreference = "Stop"

# ================= CONFIG =================
$ConfigString = "=0nI9c2N5Z1QxtGOWdHR0RkRK9ENjRnYJ9kcQtmS4A1VIdXdQpnbEdFdy9GW3dnI6ISeltmIsIiI6ISawFmIsIiI6ISehxWZyJCLiwWYj9GbuIXZ2JXZz5mbiojI0N3boJye"
$RustDeskMsiUrl = "https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.msi"
$MsiPath = Join-Path $env:TEMP "rustdesk-1.4.5-x86_64.msi"

# ================= FUNCTIONS =================
function Find-RustDeskExe {
    $paths = @(
        Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"
        Join-Path ${env:ProgramFiles(x86)} "RustDesk\rustdesk.exe"
        Join-Path $env:LocalAppData "Programs\RustDesk\rustdesk.exe"
    )

    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

# ================= INSTALL =================
Write-Host "[*] Downloading RustDesk MSI..."
Invoke-WebRequest -Uri $RustDeskMsiUrl -OutFile $MsiPath -UseBasicParsing

Write-Host "[*] Installing RustDesk silently..."
Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait

# ================= CONFIG APPLY =================
$RustDeskExe = Find-RustDeskExe
if (-not $RustDeskExe) {
    throw "RustDesk executable not found after installation."
}

Write-Host "[*] Applying RustDesk server configuration..."
Start-Process -FilePath $RustDeskExe -ArgumentList "--config `"$ConfigString`"" -Wait

Write-Host "[✓] RustDesk installed and configured successfully."
