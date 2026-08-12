# =========================================================
# MyDashboardProtocol.ps1
# =========================================================

$ErrorActionPreference = "Stop"

$InstallRoot = "C:\MyDashboard"

$PowerShell = `
    "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

$Log = Join-Path `
    $InstallRoot `
    "Protocol.log"

# =========================================================
# EXISTING MYDASHBOARD UPDATE ENDPOINT
# =========================================================

$UpdateUrl = `
    "https://script.google.com/macros/s/AKfycbw9EvpQLlX06IeynrWhSY3sy1YNHDp2Zq4wuJVoFSo6J9PC7j8TQqilA5u5EY1LWh0Z6w/exec"


# =========================================================
# LOGGING
# =========================================================

function Write-Log {

    param(
        [string]$Message
    )

    try {

        if (!(Test-Path -LiteralPath $InstallRoot)) {

            New-Item `
                -ItemType Directory `
                -Path $InstallRoot `
                -Force |
                Out-Null
        }

        Add-Content `
            -LiteralPath $Log `
            -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"

    }
    catch {
        # Do not stop the launcher because logging failed.
    }
}


# =========================================================
# GET COMMAND
# =========================================================

$uri = ""

if ($args.Count -gt 0) {

    $uri = [string]$args[0]
}

$uri = `
    $uri.Trim().Trim('"').Trim("'").ToLower()


if ($uri.StartsWith("mydashboard://")) {

    $command = $uri.Substring(14)

}
else {

    $command = $uri
}


$command = `
    $command.Trim("/").Trim()


Write-Log "URI=[$uri]"
Write-Log "COMMAND=[$command]"


# =========================================================
# VALID COMMANDS
# =========================================================

$ValidCommands = @(
    "setup",
    "idprinting",
    "deliverynote",
    "studentid",
    "pickupcard",
    "employeeid",
    "requestform"
)


if ($ValidCommands -notcontains $command) {

    Write-Log "ERROR: Unknown command [$command]"

    exit 1
}


# =========================================================
# FUNCTION: CHECK MYDASHBOARD
# =========================================================

function Test-MyDashboardInstalled {

    $RequiredFiles = @(
        "MyDashboardLauncher.ps1",
        "MyDashboardUpdate.ps1",
        "MyDashboardProtocol.ps1"
    )

    foreach ($File in $RequiredFiles) {

        $Path = Join-Path `
            $InstallRoot `
            $File

        if (!(Test-Path -LiteralPath $Path)) {

            return $false
        }
    }

    return $true
}


# =========================================================
# FUNCTION: DOWNLOAD COMPLETE PACKAGE
# =========================================================

function Install-MyDashboard {

    Write-Log "MyDashboard installation/update required."

    Write-Host ""
    Write-Host "MyDashboard is not installed." `
        -ForegroundColor Yellow

    Write-Host "Downloading MyDashboard..." `
        -ForegroundColor Cyan

    # -----------------------------------------------------
    # Prepare directories
    # -----------------------------------------------------

    New-Item `
        -ItemType Directory `
        -Path $InstallRoot `
        -Force |
        Out-Null


    $UpdateDir = Join-Path `
        $InstallRoot `
        "_bootstrap"

    New-Item `
        -ItemType Directory `
        -Path $UpdateDir `
        -Force |
        Out-Null


    $ZipPath = Join-Path `
        $UpdateDir `
        "MyDashboard.zip"


    # -----------------------------------------------------
    # Request package from Apps Script
    # -----------------------------------------------------

    $RequestUrl =
        $UpdateUrl +
        "?action=download&t=" +
        [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()


    Write-Log "Requesting package from Apps Script."


    $wc = New-Object System.Net.WebClient

    try {

        $wc.Headers["User-Agent"] = "Mozilla/5.0"

        $wc.Headers["Accept"] = "application/json"

        $ResponseText =
            $wc.DownloadString($RequestUrl)

    }
    finally {

        $wc.Dispose()
    }


    if ([string]::IsNullOrWhiteSpace($ResponseText)) {

        throw `
            "Google Apps Script returned an empty response."
    }


    $ResponseText =
        $ResponseText.Trim([char]0xFEFF).Trim()


    # -----------------------------------------------------
    # Parse JSON
    # -----------------------------------------------------

    $Result =
        $ResponseText |
        ConvertFrom-Json


    if (!$Result.ok) {

        throw `
            "Google Apps Script error: $($Result.error)"
    }


    if ([string]::IsNullOrWhiteSpace($Result.data)) {

        throw `
            "Google Apps Script returned no package data."
    }


    Write-Log `
        "Package received. Base64 length: $($Result.data.Length)"


    # -----------------------------------------------------
    # Decode ZIP
    # -----------------------------------------------------

    $ZipBytes =
        [Convert]::FromBase64String(
            $Result.data
        )


    if ($ZipBytes.Length -lt 22) {

        throw `
            "Downloaded package is too small."
    }


    # -----------------------------------------------------
    # Verify ZIP
    # -----------------------------------------------------

    if (
        $ZipBytes[0] -ne 0x50 -or
        $ZipBytes[1] -ne 0x4B
    ) {

        throw `
            "Downloaded package is not a valid ZIP file."
    }


    # -----------------------------------------------------
    # Save ZIP
    # -----------------------------------------------------

    [System.IO.File]::WriteAllBytes(
        $ZipPath,
        $ZipBytes
    )


    Write-Log `
        "ZIP saved: $($ZipBytes.Length) bytes"


    # -----------------------------------------------------
    # Extract package
    # -----------------------------------------------------

    Write-Host `
        "Installing MyDashboard..." `
        -ForegroundColor Cyan


    Expand-Archive `
        -LiteralPath $ZipPath `
        -DestinationPath $InstallRoot `
        -Force


    # -----------------------------------------------------
    # Cleanup
    # -----------------------------------------------------

    Remove-Item `
        -LiteralPath $ZipPath `
        -Force `
        -ErrorAction SilentlyContinue


    Write-Log "MyDashboard package extracted."


    # -----------------------------------------------------
    # Run Download-System-Scripts.cmd
    # -----------------------------------------------------

    $CmdFile = Join-Path `
        $InstallRoot `
        "Download-System-Scripts.cmd"


    if (Test-Path -LiteralPath $CmdFile) {

        Write-Log `
            "Running Download-System-Scripts.cmd."

        Write-Host `
            "Running MyDashboard setup..." `
            -ForegroundColor Cyan


        $Process =
            Start-Process `
                -FilePath $CmdFile `
                -WorkingDirectory $InstallRoot `
                -Wait `
                -PassThru


        if ($Process.ExitCode -ne 0) {

            throw `
                "Download-System-Scripts.cmd failed with exit code $($Process.ExitCode)."
        }


        Write-Log `
            "Download-System-Scripts.cmd completed successfully."
    }
    else {

        Write-Log `
            "Download-System-Scripts.cmd not found after package extraction."
    }


    # -----------------------------------------------------
    # Check installation
    # -----------------------------------------------------

    if (!(Test-MyDashboardInstalled)) {

        throw `
            "MyDashboard package was downloaded, but required files are still missing."
    }


    Write-Log `
        "MyDashboard installation completed."

    Write-Host `
        "MyDashboard installation completed." `
        -ForegroundColor Green
}


# =========================================================
# SETUP COMMAND
# =========================================================

if ($command -eq "setup") {

    try {

        Install-MyDashboard

        Write-Log `
            "Setup command completed."

        exit 0

    }
    catch {

        Write-Log `
            "SETUP ERROR: $($_.Exception.Message)"

        Write-Host ""
        Write-Host `
            "MyDashboard setup failed." `
            -ForegroundColor Red

        Write-Host `
            $_.Exception.Message `
            -ForegroundColor Red

        exit 1
    }
}


# =========================================================
# CHECK / INSTALL MYDASHBOARD
# =========================================================

try {

    if (!(Test-MyDashboardInstalled)) {

        Write-Log `
            "MyDashboard not found. Starting automatic installation."

        Install-MyDashboard
    }
    else {

        Write-Log `
            "MyDashboard installation detected."
    }

}
catch {

    Write-Log `
        "INSTALL ERROR: $($_.Exception.Message)"

    Write-Host ""
    Write-Host `
        "Unable to install MyDashboard." `
        -ForegroundColor Red

    Write-Host `
        $_.Exception.Message `
        -ForegroundColor Red

    exit 1
}


# =========================================================
# LAUNCHER
# =========================================================

$Launcher =
    Join-Path `
        $InstallRoot `
        "MyDashboardLauncher.ps1"


if (!(Test-Path -LiteralPath $Launcher)) {

    Write-Log `
        "ERROR: MyDashboardLauncher.ps1 not found."

    exit 1
}


Write-Log `
    "Starting launcher: $command"


# =========================================================
# START APPLICATION
# =========================================================

Start-Process `
    -FilePath $PowerShell `
    -WorkingDirectory $InstallRoot `
    -ArgumentList @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $Launcher,
        $command
    )


Write-Log `
    "Launcher started: $command"


exit 0