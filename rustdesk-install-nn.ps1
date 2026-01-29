#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# ===== CONFIGURATION =====
$rustdesk_host = "192.168.0.210"
$rustdesk_key = "wwXortWDnzPuwHWP8JkPrOIbtc4OJFDtDwV8kqCVy7g="
$rustdesk_pw = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })

# ===== FUNCTIONS =====
function Get-LatestRustDeskVersion {
    $response = Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/latest" -MaximumRedirection 0 -ErrorAction SilentlyContinue -UseBasicParsing
    $redirectUrl = $response.Headers.Location

    if (-not $redirectUrl) {
        $response = Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/latest" -UseBasicParsing
        $redirectUrl = $response.BaseResponse.ResponseUri.AbsoluteUri
    }

    if ($redirectUrl -match '/releases/tag/(?<version>[\d\.]+)') {
        return $matches['version']
    }

    throw "Could not determine latest RustDesk version"
}

function Get-RustDeskDownloadUrl {
    param([string]$Version)
    return "https://github.com/rustdesk/rustdesk/releases/download/$Version/rustdesk-$Version-x86_64.exe"
}

function Apply-RustDeskConfig {
    param(
        [string]$ServerHost,
        [string]$ServerKey
    )

    # Build the rendezvous server address (default port 21116)
    $rendezvousServer = $ServerHost
    if ($rendezvousServer -notmatch ':\d+$') {
        $rendezvousServer = "${rendezvousServer}:21116"
    }

    # Config file paths
    $userConfigDir = "$env:APPDATA\RustDesk\config"
    $serviceConfigDir = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"

    # Build config content with correct format (key goes in [options] section)
    $configContent = "rendezvous_server = '$rendezvousServer'`nnat_type = 1`nserial = 0`nunlock_pin = ''`ntrusted_devices = ''`n`n[options]`nstop-service = 'N'`nkey = '$ServerKey'`ncustom-rendezvous-server = '$ServerHost'"

    foreach ($configDir in @($userConfigDir, $serviceConfigDir)) {
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        $configFile = Join-Path $configDir "RustDesk2.toml"
        $configContent | Set-Content -Path $configFile -Force
    }
}

# ===== MAIN SCRIPT =====
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       RustDesk Installation Script    " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get latest version
Write-Host "[1/6] Checking latest RustDesk version..." -ForegroundColor Yellow
$latestVersion = Get-LatestRustDeskVersion
Write-Host "      Latest version: $latestVersion" -ForegroundColor Green

# Check if already installed and up to date
$installedVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\RustDesk" -ErrorAction SilentlyContinue).Version
if ($installedVersion -eq $latestVersion) {
    Write-Host "      RustDesk $latestVersion is already installed." -ForegroundColor Green
    Write-Host ""
    Write-Host "Applying configuration..." -ForegroundColor Yellow

    Stop-Service -Name "RustDesk" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Apply-RustDeskConfig -ServerHost $rustdesk_host -ServerKey $rustdesk_key

    Set-Service -Name "RustDesk" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "RustDesk" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $rustdeskExe = "$env:ProgramFiles\RustDesk\rustdesk.exe"

    # Set password
    $pwProc = Start-Process -FilePath $rustdeskExe -ArgumentList "--password", $rustdesk_pw -PassThru -NoNewWindow
    if (-not $pwProc.WaitForExit(15000)) { $pwProc.Kill() }
    Start-Sleep -Seconds 2

    # Get ID
    $tempFile = [System.IO.Path]::GetTempFileName()
    $idProc = Start-Process -FilePath $rustdeskExe -ArgumentList "--get-id" -PassThru -NoNewWindow -RedirectStandardOutput $tempFile
    if ($idProc.WaitForExit(10000)) {
        $rustdesk_id = (Get-Content $tempFile -ErrorAction SilentlyContinue)
        if ($rustdesk_id) { $rustdesk_id = $rustdesk_id.Trim() }
    } else {
        $idProc.Kill()
        $rustdesk_id = ""
    }
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "RustDesk ID: $rustdesk_id" -ForegroundColor White
    Write-Host "Password:    $rustdesk_pw" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

# Create temp directory
$tempDir = "$env:TEMP\RustDeskInstall"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Download
Write-Host "[2/6] Downloading RustDesk $latestVersion..." -ForegroundColor Yellow
$downloadUrl = Get-RustDeskDownloadUrl -Version $latestVersion
$installerPath = Join-Path $tempDir "rustdesk-$latestVersion.exe"

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "      Download complete." -ForegroundColor Green
} catch {
    throw "Failed to download RustDesk: $_"
}

# Stop existing RustDesk processes/service
Write-Host "[3/6] Stopping existing RustDesk processes..." -ForegroundColor Yellow
Stop-Service -Name "RustDesk" -Force -ErrorAction SilentlyContinue
Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Write-Host "      Done." -ForegroundColor Green

# Install
Write-Host "[4/6] Installing RustDesk..." -ForegroundColor Yellow
Start-Process -FilePath $installerPath -ArgumentList "--silent-install"

# Wait for installation to complete
$installTimeout = 60
$elapsed = 0
while ($elapsed -lt $installTimeout) {
    Start-Sleep -Seconds 2
    $elapsed += 2
    if (Test-Path "$env:ProgramFiles\RustDesk\rustdesk.exe") {
        Start-Sleep -Seconds 3
        break
    }
}

if (-not (Test-Path "$env:ProgramFiles\RustDesk\rustdesk.exe")) {
    throw "Installation timed out - RustDesk executable not found"
}
Write-Host "      Installation complete." -ForegroundColor Green

# Ensure service is running
Write-Host "[5/6] Starting RustDesk service..." -ForegroundColor Yellow
$maxAttempts = 12
$attempt = 0
do {
    $attempt++
    $service = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Running') {
            Start-Service -Name "RustDesk" -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
        $service.Refresh()
        if ($service.Status -eq 'Running') {
            Write-Host "      Service is running." -ForegroundColor Green
            break
        }
    } else {
        Start-Sleep -Seconds 3
    }
} while ($attempt -lt $maxAttempts)

if ($attempt -ge $maxAttempts) {
    Write-Host "      Warning: Service may not be running properly." -ForegroundColor Red
}

# Apply configuration
Write-Host "[6/6] Applying configuration..." -ForegroundColor Yellow
Stop-Service -Name "RustDesk" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Apply-RustDeskConfig -ServerHost $rustdesk_host -ServerKey $rustdesk_key

Set-Service -Name "RustDesk" -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name "RustDesk" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$rustdeskExe = "$env:ProgramFiles\RustDesk\rustdesk.exe"

# Set password
$pwProc = Start-Process -FilePath $rustdeskExe -ArgumentList "--password", $rustdesk_pw -PassThru -NoNewWindow
if (-not $pwProc.WaitForExit(15000)) { $pwProc.Kill() }
Start-Sleep -Seconds 2

# Get the ID
$rustdesk_id = ""
$idAttempts = 0
while ([string]::IsNullOrWhiteSpace($rustdesk_id) -and $idAttempts -lt 5) {
    $idAttempts++
    $tempFile = [System.IO.Path]::GetTempFileName()
    $idProc = Start-Process -FilePath $rustdeskExe -ArgumentList "--get-id" -PassThru -NoNewWindow -RedirectStandardOutput $tempFile
    if ($idProc.WaitForExit(10000)) {
        $content = Get-Content $tempFile -ErrorAction SilentlyContinue
        if ($content) { $rustdesk_id = $content.Trim() }
    } else {
        $idProc.Kill()
    }
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($rustdesk_id)) {
        Start-Sleep -Seconds 2
    }
}

Write-Host "      Configuration applied." -ForegroundColor Green

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Output results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    Installation Complete!             " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
if ([string]::IsNullOrWhiteSpace($rustdesk_id)) {
    Write-Host "RustDesk ID: (open RustDesk to view)" -ForegroundColor Yellow
} else {
    Write-Host "RustDesk ID: $rustdesk_id" -ForegroundColor White
}
Write-Host "Password:    $rustdesk_pw" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
