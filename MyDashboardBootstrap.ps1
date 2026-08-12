# =========================================================
# MyDashboardBootstrap.ps1
# Standalone First-Time Installer & Deployment Script
# =========================================================

$ErrorActionPreference = "Stop"
$InstallRoot = "C:\MyDashboard"
$PowerShell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$LogFile = Join-Path $InstallRoot "MyDashboardSetup.log"
$UpdateUrl = "https://script.google.com/macros/s/AKfycbw9EvpQLlX06IeynrWhSY3sy1YNHDp2Zq4wuJVoFSo6J9PC7j8TQqilA5u5EY1LWh0Z6w/exec"

# Create Install Directory
if (!(Test-Path -LiteralPath $InstallRoot)) {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    } catch {}
}

Write-Log "============================================================"
Write-Log "MyDashboard Bootstrap Setup Started"
Write-Log "============================================================"

# Auto-Elevation Check
$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
$IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (!$IsAdmin) {
    Write-Log "Not running as Administrator. Requesting elevation."
    try {
        $Arguments = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        Start-Process -FilePath $PowerShell -ArgumentList $Arguments -Verb RunAs
        exit 0
    } catch {
        Write-Log "ERROR: Unable to request Administrator elevation: $_"
        exit 1
    }
}

Write-Log "Running with Administrator privileges."

# TLS Configuration
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Download Package via Google Apps Script
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MyDashboard Automated Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Downloading package components..." -ForegroundColor Cyan

$TempDir = Join-Path $InstallRoot "_update"
$ZipPath = Join-Path $TempDir "MyDashboard.zip"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    $RequestUrl = "$UpdateUrl?action=download&t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $wc = New-Object System.Net.WebClient
    $wc.Headers["User-Agent"] = "Mozilla/5.0"
    $wc.Headers["Accept"] = "application/json"
    $ResponseText = $wc.DownloadString($RequestUrl)
    $wc.Dispose()

    if ([string]::IsNullOrWhiteSpace($ResponseText)) { throw "Google Apps Script returned an empty response." }
    
    $ResponseText = $ResponseText.Trim([char]0xFEFF).Trim()
    $Result = $ResponseText | ConvertFrom-Json
    if (!$Result.ok) { throw "Google Apps Script error: $($Result.error)" }

    $ZipBytes = [Convert]::FromBase64String($Result.data)
    [System.IO.File]::WriteAllBytes($ZipPath, $ZipBytes)

    Write-Host "Extracting files to $InstallRoot..." -ForegroundColor Cyan
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $InstallRoot -Force
    Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $TempDir -Force -Recurse -ErrorAction SilentlyContinue
    Write-Log "Package extracted successfully."
}
catch {
    Write-Log "DEPLOYMENT ERROR: $_"
    Write-Host "Deployment failed: $_" -ForegroundColor Red
    exit 1
}

# Register mydashboard:// Protocol Handler
Write-Host "Registering mydashboard:// protocol..." -ForegroundColor Cyan
$ProtocolRoot = "HKCU:\Software\Classes\mydashboard"
$ProtocolCommand = "$ProtocolRoot\shell\open\command"
$ProtocolScript = Join-Path $InstallRoot "MyDashboardProtocol.ps1"
$LauncherScript = Join-Path $InstallRoot "MyDashboardLauncher.ps1"

try {
    New-Item -Path $ProtocolRoot -Force | Out-Null
    New-ItemProperty -Path $ProtocolRoot -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
    Set-ItemProperty -Path $ProtocolRoot -Name "(default)" -Value "URL:MyDashboard Protocol"

    New-Item -Path "$ProtocolRoot\shell\open\command" -Force | Out-Null
    $CommandValue = "`"$PowerShell`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ProtocolScript`" `"%1`""
    Set-ItemProperty -Path $ProtocolCommand -Name "(default)" -Value $CommandValue
    Write-Log "mydashboard:// protocol registered successfully."
}
catch {
    Write-Log "PROTOCOL ERROR: $_"
}

# Create Desktop Shortcut
try {
    $Desktop = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $Desktop "MyDashboard.lnk"
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $PowerShell
    $Shortcut.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$LauncherScript`""
    $Shortcut.WorkingDirectory = $InstallRoot
    $Shortcut.Description = "MyDashboard"
    $Shortcut.Save()
    Write-Log "Desktop shortcut created."
} catch {}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " MyDashboard Installation Completed!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
exit 0