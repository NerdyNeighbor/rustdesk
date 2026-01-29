#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# ===== CONFIGURATION =====
$rustdesk_cfg = "=0nI9c2N5Z1QxtGOWdHR0RkRK9ENjRnYJ9kcQtmS4A1VIdXdQpnbEdFdy9GW3dnI6ISeltmIsIiI6ISawFmIsIiI6ISehxWZyJCLiwWYj9GbuIXZ2JXZz5mbiojI0N3boJye"
$rustdesk_pw = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })

# ===== FUNCTIONS =====
function Get-LatestRustDeskVersion {
    # Follow the redirect from /releases/latest to get actual version
    $response = Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/latest" -MaximumRedirection 0 -ErrorAction SilentlyContinue -UseBasicParsing
    $redirectUrl = $response.Headers.Location

    if (-not $redirectUrl) {
        # Fallback: try getting it from the response
        $response = Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/latest" -UseBasicParsing
        $redirectUrl = $response.BaseResponse.ResponseUri.AbsoluteUri
    }

    # Extract version from URL like: https://github.com/rustdesk/rustdesk/releases/tag/1.3.6
    if ($redirectUrl -match '/releases/tag/(?<version>[\d\.]+)') {
        return $matches['version']
    }

    throw "Could not determine latest RustDesk version"
}

function Get-RustDeskDownloadUrl {
    param([string]$Version)
    return "https://github.com/rustdesk/rustdesk/releases/download/$Version/rustdesk-$Version-x86_64.exe"
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
    Push-Location "$env:ProgramFiles\RustDesk"
    $rustdesk_id = (.\rustdesk.exe --get-id 2>$null).Trim()
    .\rustdesk.exe --config $rustdesk_cfg
    .\rustdesk.exe --password $rustdesk_pw
    Pop-Location
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
    $ProgressPreference = 'SilentlyContinue'  # Speeds up download significantly
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
Start-Process -FilePath $installerPath -ArgumentList "--silent-install" -Wait
Start-Sleep -Seconds 5
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
Start-Sleep -Seconds 3  # Give service time to initialize
Push-Location "$env:ProgramFiles\RustDesk"
$rustdesk_id = (.\rustdesk.exe --get-id 2>$null).Trim()
.\rustdesk.exe --config $rustdesk_cfg
.\rustdesk.exe --password $rustdesk_pw
Pop-Location
Write-Host "      Configuration applied." -ForegroundColor Green

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Output results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    Installation Complete!             " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "RustDesk ID: $rustdesk_id" -ForegroundColor White
Write-Host "Password:    $rustdesk_pw" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
