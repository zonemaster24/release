$ErrorActionPreference = "Stop"

$InstallRoot = "C:\MyDashboard"
$ZipUrl = "https://github.com/zonemaster24/release/raw/refs/heads/main/Updater.zip"
$TempDir = Join-Path $InstallRoot "_bootstrap"
$ZipPath = Join-Path $TempDir "Updater.zip"
$CmdFile = Join-Path $InstallRoot "Download-System-Scripts.cmd"

# 1. Create directories automatically
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

Write-Host "Downloading Updater.zip from GitHub..." -ForegroundColor Cyan

# 2. Automatically download the ZIP from GitHub
Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath

Write-Host "Extracting package..." -ForegroundColor Cyan

# 3. Automatically extract the ZIP recursively into C:\MyDashboard
Expand-Archive -LiteralPath $ZipPath -DestinationPath $InstallRoot -Force

# 4. Clean up temporary zip file
Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue

# 5. Automatically run the batch file inside if present
if (Test-Path -LiteralPath $CmdFile) {
    Write-Host "Triggering setup batch file..." -ForegroundColor Cyan
    Start-Process -FilePath $CmdFile -WorkingDirectory $InstallRoot -Wait -NoNewWindow
    Write-Host "Setup completed successfully!" -ForegroundColor Green
} else {
    Write-Warning "Setup batch file not found after extraction."
}