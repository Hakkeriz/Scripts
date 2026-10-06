# ==============================================================================
# SCRIPT: Win11-Debloat-Standalone.ps1
# DESCRIPTION: Windows 11 debloat / AI removal / consumer-content baseline.
#              Removes OEM bloatware (Lenovo, HP), consumer Microsoft apps,
#              consumer M365/OneNote, Recall + Copilot (and locks them down via
#              policy), Spotlight/lock-screen ads, widgets/news feed.
#              Business Teams (MSTeams) is preserved.
# USAGE:       powershell.exe -ExecutionPolicy Bypass -File .\Win11-Debloat-Standalone.ps1
#              Switches:
#                -Interactive       colored output, restarts Explorer, asks to reboot
#                -RemoveOneDrive    also uninstall built-in OneDrive (off by default)
#                -SkipM365Consumer  skip the consumer M365 / OneNote removal (ODT)
#              Unattended (RMM / SYSTEM): run with no switches.
# LOG:         C:\Temp\Logs\Win11_Bloatware_Removal.log
# EXIT:        0 = completed (reboot recommended)
# ==============================================================================

#Requires -RunAsAdministrator
param(
    [switch]$Interactive,
    [switch]$RemoveOneDrive,
    [switch]$SkipM365Consumer
)

$LogDir  = "C:\Temp\Logs"
$LogPath = "$LogDir\Win11_Bloatware_Removal.log"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# --- LOGGING FUNCTION ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $LogMessage -ErrorAction SilentlyContinue

    $color = "White"
    if     ($Level -eq "ERROR")                                   { $color = "Red" }
    elseif ($Level -eq "WARN" -or $Level -eq "WARNING")           { $color = "Yellow" }
    elseif ($Message -match '^---')                               { $color = "Cyan" }
    elseif ($Message -match 'not detected|not found|already absent|not present|Already absent') { $color = "DarkGray" }
    elseif ($Message -match 'PROTECTED|NOTE:')                    { $color = "Yellow" }
    elseif ($Message -match '(?i)removed|cleaned|disabled|purged|uninstalled|completed|deployed|applied|enforced|stripped') { $color = "Green" }
    Write-Host $LogMessage -ForegroundColor $color
}

Write-Log "=== Windows 11 Bloatware Removal Started ===" "INFO"
Write-Log "Computer: $env:COMPUTERNAME | User: $env:USERNAME" "INFO"

# ==============================================================================
# PHASE 1 - RELEASING SYSTEM HANDLES
# ==============================================================================
Write-Log "--- [Phase 1] Releasing System Handles ---" "INFO"
$pList = @(
    "Outlook","Recall","AIHost","Xbox","OfficeHub","SmartConnect",
    "LenovoAINow","ReadyFor","aimgr","OneNote","Family","LADM",
    "HpSAMD","HpSAPS","hpCommunicationService","hpTouchpointAnalyticsService",
    "hpsvcmgr","CxBoot","HPAMService","HpProtectedNetwork"
)
foreach ($p in $pList) {
    Get-Process | Where-Object { $_.ProcessName -like "*$p*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}
Write-Log "  -> System handles released." "INFO"

# ==============================================================================
# PHASE 2 - TRADITIONAL WIN32 APP REMOVAL
# ==============================================================================
Write-Log "--- [Phase 2] Uninstalling Traditional Apps (Win32) ---" "INFO"

# --- Lenovo AI Now ---
Write-Log "  -> [Lenovo AI Now] Checking for installation..." "INFO"

$lenovoAIDetected = $false
foreach ($path in @(
    "C:\Program Files\Lenovo\Lenovo AI Now",
    "C:\Program Files (x86)\Lenovo\Lenovo AI Now",
    "C:\ProgramData\Lenovo\Lenovo AI Now"
)) { if (Test-Path $path) { $lenovoAIDetected = $true; break } }

foreach ($rPath in @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Lenovo AI Now",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Lenovo AI Now"
)) { if (Test-Path $rPath) { $lenovoAIDetected = $true; break } }

if ($lenovoAIDetected) {
    Write-Log "  -> Lenovo AI Now detected. Starting removal..." "INFO"

    foreach ($proc in @("AIHost","LADM","aimgr","LenovoAINow","Uninstall","unins000")) {
        Get-Process | Where-Object { $_.ProcessName -like "*$proc*" } |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1

    # Nullify shell extension CLSIDs
    $clsid = "{D3924970-4E57-4560-A656-324209E0D495}"
    foreach ($regPath in @(
        "HKLM:\SOFTWARE\Classes\CLSID\$clsid",
        "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID\$clsid",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"
    )) {
        if (Test-Path $regPath) {
            Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  -> Removed shell extension: $regPath" "INFO"
        }
    }

    # Force directory removal with ownership takeover
    foreach ($path in @(
        "C:\Program Files\Lenovo\Lenovo AI Now",
        "C:\Program Files (x86)\Lenovo\Lenovo AI Now",
        "C:\ProgramData\Lenovo\Lenovo AI Now",
        "$env:LOCALAPPDATA\Lenovo\Lenovo AI Now",
        "$env:APPDATA\Lenovo\Lenovo AI Now"
    )) {
        if (Test-Path $path) {
            Write-Log "  -> Force removing: $path" "INFO"
            & takeown /f "$path" /r /d y 2>$null | Out-Null
            & icacls "$path" /grant Administrators:F /t 2>$null | Out-Null
            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue

            if (!(Test-Path $path)) {
                Write-Log "  -> Successfully removed: $path" "INFO"
            } else {
                Write-Log "  -> Path locked, queuing for boot-time deletion..." "INFO"
                $smKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
                $existing = (Get-ItemProperty -Path $smKey -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
                $pendingList = New-Object System.Collections.Generic.List[string]
                if ($existing) { foreach ($line in $existing) { $pendingList.Add($line) } }
                $pendingList.Add("\??\$path")
                $pendingList.Add("")
                Set-ItemProperty -Path $smKey -Name "PendingFileRenameOperations" -Value ($pendingList.ToArray()) -Type MultiString -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Registry cleanup
    foreach ($regPath in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Lenovo AI Now",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Lenovo AI Now",
        "HKLM:\SOFTWARE\Lenovo\Lenovo AI Now",
        "HKLM:\SOFTWARE\WOW6432Node\Lenovo\Lenovo AI Now",
        "HKCU:\Software\Lenovo\Lenovo AI Now"
    )) {
        if (Test-Path $regPath) {
            Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  -> Removed registry key: $regPath" "INFO"
        }
    }

    # Startup entries
    foreach ($runPath in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    )) {
        if (Test-Path $runPath) {
            $runKey = Get-ItemProperty $runPath -ErrorAction SilentlyContinue
            if ($runKey) {
                $runKey.PSObject.Properties | Where-Object { $_.Name -like "*Lenovo*AI*" } | ForEach-Object {
                    Remove-ItemProperty -Path $runPath -Name $_.Name -Force -ErrorAction SilentlyContinue
                    Write-Log "  -> Removed startup entry: $($_.Name)" "INFO"
                }
            }
        }
    }

    # Uninstall registry ghosts
    foreach ($uninPath in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )) {
        Get-ChildItem $uninPath -ErrorAction SilentlyContinue | Where-Object {
            (Get-ItemProperty $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName -like "*Lenovo AI*"
        } | ForEach-Object {
            Write-Log "  -> Removing uninstall entry: $($_.PSChildName)" "INFO"
            Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Log "  -> Lenovo AI Now removal completed." "INFO"
} else {
    Write-Log "  -> Lenovo AI Now not detected on this system." "INFO"
}

# --- Windows Built-in OneDrive (opt-in: -RemoveOneDrive) ---
if ($RemoveOneDrive) {
    # Remove per-user OneDrive from ALL user profiles, not just current user
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $userSetup = "$($_.FullName)\AppData\Local\Microsoft\OneDrive\OneDriveSetup.exe"
        if (Test-Path $userSetup) {
            Write-Log "  -> Removing per-user OneDrive from profile: $($_.Name)" "INFO"
            Start-Process $userSetup -ArgumentList "/uninstall" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        }
    }

    # Also remove via system path
    $odPath = "$env:SystemRoot\System32\OneDriveSetup.exe"
    if (-not (Test-Path $odPath)) { $odPath = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" }
    if (Test-Path $odPath) {
        Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $odProc = Start-Process $odPath -ArgumentList "/uninstall" -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Log "  -> Built-in OneDrive uninstalled (exit: $($odProc.ExitCode))" "INFO"
        foreach ($key in @(
            "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
            "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
        )) { Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue }
    } else {
        Write-Log "  -> Built-in OneDrive: Already absent." "INFO"
    }

    # Remove MSIX OneDriveSync if Windows Update pushed it - must happen BEFORE /allusers install
    # otherwise setup errors "A newer version is installed, uninstall first"
    $msixOD = Get-AppxPackage -AllUsers -Name "Microsoft.OneDriveSync" -ErrorAction SilentlyContinue
    if ($msixOD) {
        Remove-AppxPackage -AllUsers -Package $msixOD.PackageFullName -ErrorAction SilentlyContinue
        Write-Log "  -> Removed MSIX OneDriveSync (Windows Update re-delivery)" "INFO"
    }
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -match "OneDriveSync" } |
        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }

    # Block Windows Update orchestrator from re-delivering OneDrive MSIX after reboot
    foreach ($key in @(
        "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OneDriveUpdate",
        "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler\OneDriveUpdate"
    )) { Remove-Item $key -Force -ErrorAction SilentlyContinue }
    # Block Windows Store / consumer feature re-delivery of OneDriveSync MSIX permanently
    # DisableWindowsConsumerFeatures prevents Windows from auto-installing Store apps on new/existing users
    $cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (!(Test-Path $cloudPath)) { New-Item $cloudPath -Force | Out-Null }
    Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    Write-Log "  -> OneDrive MSIX re-delivery blocked (orchestrator + consumer features policy)" "INFO"

} else {
    Write-Log "  -> Built-in OneDrive: left in place (use -RemoveOneDrive to remove)." "INFO"
}

# --- Smart Connect ---
$reg = $null
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ReadyFor") {
    $reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ReadyFor" -ErrorAction SilentlyContinue
} elseif (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ReadyFor") {
    $reg = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ReadyFor" -ErrorAction SilentlyContinue
}

if ($reg -and $reg.UninstallString) {
    Write-Log "  -> Found: Smart Connect. Issuing silent removal..." "INFO"
    $uCmd = $reg.UninstallString.Trim('"')
    Start-Process "cmd.exe" -ArgumentList "/c `"$uCmd`" /S /SILENT" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-Log "  -> Smart Connect: Removal command issued." "INFO"
} else {
    Write-Log "  -> Smart Connect: Already absent." "INFO"
}

# --- HP Wolf Security Deep Scrub ---
Write-Log "  -> [HP Wolf Security] Checking for installation..." "INFO"
$hpWolfApps = @(
    "HP Wolf Security",
    "HP Wolf Security - Console",
    "HP Wolf Security Application Support for Sure Sense",
    "HP Security Update Service"
)
$hpWolfFound = $false
$hpWolfServices = @("HpSAMD","hpCommunicationService","hpTouchpointAnalyticsService","HPAMService")
foreach ($svc in $hpWolfServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "  -> Stopped/disabled service: $svc" "INFO"
    }
}
Start-Sleep -Seconds 3
foreach ($uninPath in @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)) {
    Get-ChildItem $uninPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $matched = $hpWolfApps | Where-Object { $props.DisplayName -like "*$_*" }
        if ($props -and $matched) {
            $appName = $props.DisplayName
            Write-Log "  -> Uninstalling: $appName" "INFO"
            $hpWolfFound = $true
            try {
                if ($props.UninstallString -match "msiexec") {
                    $guid = [regex]::Match($props.UninstallString, '\{[^}]+\}').Value
                    if ($guid) {
                        $proc = Start-Process "msiexec.exe" -ArgumentList "/x `"$guid`" /quiet /norestart" -Wait -PassThru -ErrorAction Stop
                        Write-Log "  -> Uninstalled: $appName (exit: $($proc.ExitCode))" "INFO"
                    }
                } elseif ($props.QuietUninstallString) {
                    Start-Process "cmd.exe" -ArgumentList "/c `"$($props.QuietUninstallString)`"" -Wait -ErrorAction Stop | Out-Null
                    Write-Log "  -> Uninstalled: $appName via QuietUninstall" "INFO"
                }
            } catch {
                Write-Log "  -> Uninstall failed for ${appName}: $($_.Exception.Message)" "WARN"
            }
            Start-Sleep -Seconds 2
        }
    }
}
foreach ($path in @(
    "$env:ProgramFiles\HP\Wolf Security",
    "$env:ProgramFiles\HP\HP Wolf Security",
    "${env:ProgramFiles(x86)}\HP\Wolf Security",
    "$env:ProgramData\HP\HP Wolf Security",
    "$env:ProgramData\HP\Wolf Security"
)) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "  -> Removed residual: $path" "INFO"
    }
}
foreach ($key in @(
    "HKLM:\SOFTWARE\HP\Wolf Security",
    "HKLM:\SOFTWARE\WOW6432Node\HP\Wolf Security",
    "HKLM:\SOFTWARE\HP\HP Wolf Security"
)) {
    if (Test-Path $key) {
        Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "  -> Removed registry: $key" "INFO"
    }
}
if (-not $hpWolfFound) { Write-Log "  -> HP Wolf Security: Not present" "INFO" }

# --- HP Win32 App Removal ---
Write-Log "  -> [HP Win32 Apps] Removing HP consumer Win32 apps..." "INFO"
$hpWin32Apps = @("HP Notifications","HP Documentation","HP Connection Optimizer","HP Security Update Service")
foreach ($uninPath in @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)) {
    Get-ChildItem $uninPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $matched = $hpWin32Apps | Where-Object { $props.DisplayName -like "*$_*" }
        if ($props -and $matched) {
            Write-Log "  -> Uninstalling: $($props.DisplayName)" "INFO"
            try {
                if ($props.UninstallString -match "msiexec") {
                    $guid = [regex]::Match($props.UninstallString, '\{[^}]+\}').Value
                    if ($guid) { Start-Process "msiexec.exe" -ArgumentList "/x `"$guid`" /quiet /norestart" -Wait | Out-Null }
                } elseif ($props.QuietUninstallString) {
                    Start-Process "cmd.exe" -ArgumentList "/c `"$($props.QuietUninstallString)`"" -Wait | Out-Null
                } elseif ($props.UninstallString) {
                    $u = $props.UninstallString.Trim('"').Trim()
                    Start-Process "cmd.exe" -ArgumentList "/c `"$u`" /S /SILENT /quiet" -Wait | Out-Null
                }
                Write-Log "  -> Uninstalled: $($props.DisplayName)" "INFO"
            } catch {
                Write-Log "  -> Failed: $($props.DisplayName) - $($_.Exception.Message)" "WARN"
            }
        }
    }
}
# HP Documentation uses broken .cmd uninstaller - force remove folder + ghost registry
foreach ($docPath in @("$env:ProgramFiles\HP\Documentation","${env:ProgramFiles(x86)}\HP\Documentation")) {
    if (Test-Path $docPath) { Remove-Item $docPath -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "  -> Force-removed HP Documentation folder: $docPath" "INFO" }
}
$hpGhostApps = @("HP Connection Optimizer","HP Documentation")
foreach ($uninPath in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
    Get-ChildItem $uninPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $matched = $hpGhostApps | Where-Object { $props.DisplayName -like "*$_*" }
        if ($props -and $matched) {
            $installDir = $props.InstallLocation
            if (-not $installDir -or -not (Test-Path $installDir)) {
                Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "  -> Removed ghost registry entry: $($props.DisplayName)" "INFO"
            }
        }
    }
}

# ==============================================================================
# PHASE 3 - DISM AI & RECALL STRIP
# ==============================================================================
Write-Log "--- [Phase 3] Stripping AI Workloads & Recall ---" "INFO"

try {
    & dism.exe /online /disable-feature /featurename:Recall /remove /norestart /quiet 2>$null | Out-Null
    Write-Log "  -> Recall feature disabled and payload removed." "INFO"
} catch {
    Write-Log "  -> Recall feature not present or already disabled." "INFO"
}

foreach ($g in @("WindowsWorkload","Microsoft.OutlookForWindows","LinkedIn","Copilot","Recall","aimgr")) {
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $g }
    if ($prov) {
        foreach ($p in $prov) {
            Write-Log "  -> DISM stripping: $($p.DisplayName)" "INFO"
            & dism.exe /online /remove-provisionedappxpackage /packagename:$($p.PackageName) /norestart /quiet 2>$null | Out-Null
        }
    }
}

Write-Log "  -> Scanning for WindowsWorkload AI packages..." "INFO"
$aiWorkloads = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "WindowsWorkload.*" }
if ($aiWorkloads) {
    $removed = 0; $locked = 0
    foreach ($pkg in $aiWorkloads) {
        try {
            Remove-AppxPackage $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $removed++
        } catch {
            if ($_.Exception.Message -match "0x80073D02|currently in use") { $locked++ }
        }
    }
    Write-Log "  -> Removed $removed AI packages. $locked locked (will clear after reboot)." "INFO"
} else {
    Write-Log "  -> No WindowsWorkload AI packages found." "INFO"
}

$aimgrPkgs = Get-AppxPackage -AllUsers -Name "aimgr" -ErrorAction SilentlyContinue
if ($aimgrPkgs) {
    foreach ($pkg in $aimgrPkgs) {
        Write-Log "  -> Removing Local AI Manager: $($pkg.PackageFullName)" "INFO"
        Remove-AppxPackage $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
}

Write-Log "  -> AI workload cleanup complete." "INFO"

# ==============================================================================
# PHASE 4 - SURGICAL TEAMS SHIELD (PROTECT BUSINESS, REMOVE CONSUMER)
# ==============================================================================
Write-Log "--- [Phase 4] Purging Consumer Teams ---" "INFO"
Write-Log "  -> NOTE: M365 Business Teams (MSTeams) is PROTECTED." "INFO"

$consumerTeams = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "MicrosoftTeams" }
$consumerTeamsFound = $false

if ($consumerTeams) {
    $consumerTeamsFound = $true
    foreach ($p in $consumerTeams) {
        Write-Log "  -> Removing Consumer Teams: $($p.PackageFullName)" "INFO"
        Remove-AppxPackage $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    Write-Log "  -> Consumer Teams removed." "INFO"
} else {
    Write-Log "  -> Consumer Teams not found." "INFO"
}

# ==============================================================================
# PHASE 5 - CONSUMER M365 & ONENOTE REMOVAL (ODT)
# Only runs if a consumer Click-to-Run product is actually installed.
# Business "Microsoft 365 Apps for enterprise" is never targeted.
# ==============================================================================
Write-Log "--- [Phase 5] Consumer M365 & OneNote Purge ---" "INFO"

$consumerIds = @("O365HomePremRetail","O365PersonalRetail","OneNoteFreeRetail")
$c2rIds = ""
try {
    $c2rIds = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name ProductReleaseIds -ErrorAction Stop).ProductReleaseIds
} catch {}
$consumerPresent = @($consumerIds | Where-Object { $c2rIds -match $_ })

if ($SkipM365Consumer) {
    Write-Log "  -> Consumer M365 purge skipped (-SkipM365Consumer)." "INFO"
} elseif ($consumerPresent.Count -eq 0) {
    Write-Log "  -> No consumer Click-to-Run products present - nothing to remove." "INFO"
} else {
    $odtTmp = "$env:SystemRoot\Temp\ConsumerM365Purge"
    try {
        if (!(Test-Path $odtTmp)) { New-Item $odtTmp -ItemType Directory -Force | Out-Null }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Resolve current ODT link from Microsoft Download Center, fall back to a known build
        $odtUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_19725-20126.exe"
        try {
            $resp = Invoke-WebRequest -Uri "https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $lnk = ($resp.Links | Where-Object { $_.href -match "officedeploymenttool.*\.exe" } | Select-Object -First 1).href
            if ($lnk) { $odtUrl = $lnk }
        } catch {
            Write-Log "  -> ODT link resolution failed, using fallback URL." "WARN"
        }

        Write-Log "  -> Downloading Office Deployment Tool..." "INFO"
        Invoke-WebRequest -Uri $odtUrl -OutFile "$odtTmp\odt.exe" -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
        Start-Process "$odtTmp\odt.exe" -ArgumentList "/quiet /extract:`"$odtTmp`"" -Wait -WindowStyle Hidden
        Start-Sleep -Seconds 2

        if (Test-Path "$odtTmp\setup.exe") {
            $langXml = '<Language ID="en-us"/><Language ID="fi-fi"/><Language ID="sv-se"/><Language ID="da-dk"/><Language ID="nb-no"/>'
            $xml = @('<?xml version="1.0" encoding="UTF-8"?>', '<Configuration>', '  <Remove All="FALSE">')
            foreach ($id in $consumerPresent) { $xml += "    <Product ID=`"$id`">$langXml</Product>" }
            $xml += @('  </Remove>', '  <Display Level="None" AcceptEULA="TRUE" />', '</Configuration>')
            $xml | Out-File "$odtTmp\remove.xml" -Encoding ASCII

            Write-Log "  -> Running ODT removal for: $($consumerPresent -join ', ') (may take several minutes)..." "INFO"
            Start-Process "$odtTmp\setup.exe" -ArgumentList "/configure `"$odtTmp\remove.xml`"" -Wait -WindowStyle Hidden
            Write-Log "  -> ODT removal completed." "INFO"
        } else {
            Write-Log "  -> ODT setup.exe not found after extract - skipping." "WARN"
        }
    } catch {
        Write-Log "  -> ODT method failed: $($_.Exception.Message)" "WARN"
    }
    Remove-Item $odtTmp -Recurse -Force -ErrorAction SilentlyContinue

    # Registry ghost cleanup (consumer product IDs only)
    foreach ($ok in $consumerIds) {
        Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match $ok } |
            ForEach-Object {
                Write-Log "  -> Purging registry entry: $($_.PSChildName)" "INFO"
                Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
    }
}

# ==============================================================================
# PHASE 6 - NATIVE APPX SWEEP
# ==============================================================================
Write-Log "--- [Phase 6] Native Appx Sweep ---" "INFO"
$aList = @(
    "Bing","Clipchamp","ZuneMusic","ZuneVideo","YourPhone","GamingApp","Xbox",
    "Todos","MicrosoftJournal","Whiteboard","PowerAutomateDesktop","QuickAssist","Solitaire","MixedReality",
    "FeedbackHub","Maps","DevHome","communicationsapps","OfficeHub",
    "Microsoft.OutlookForWindows","MicrosoftFamily",
    "WidgetsPlatformRuntime","StartExperiencesApp","Client.WebExperience",
    "LinkedIn","Recall","Copilot","Windows.Copilot",
    # v61.1 additions
    "MirametrixInc.GlancebyMirametrix",  # Lenovo eye-tracking bloatware
    "Microsoft.Edge.GameAssist",          # Gaming overlay, no business value
    "AppUp.IntelTechnologyMDE",           # Intel Unison - consumer phone sync
    "MicrosoftWindows.CrossDevice",       # Cross Device / phone link infrastructure
    # "Microsoft.GetHelp",                  # KEEP - handles ms-contact-support: URI used by Windows network troubleshooter (Diagnose network problems). Removing it breaks that feature. (Fixed 2026-05-23)
    "AdobeAcrobatReaderCoreApp",          # MSIX Store Reader (Win32 Acrobat already installed)
    # v62 additions
    "Tile.TileWindowsApplication",
    "Microsoft.SkypeApp",
    "AD2F1837.HPEasyClean","AD2F1837.HPPowerManager","AD2F1837.HPPrivacySettings",
    "AD2F1837.HPProgrammableKey","AD2F1837.HPQuickDrop","AD2F1837.myHP",
    "Microsoft.MSPaint","Microsoft.Microsoft3DViewer","Microsoft.People",
    "Microsoft.Office.OneNote"
)

foreach ($a in $aList) {
    $pkgs = Get-AppxPackage -AllUsers -Name "*$a*" -ErrorAction SilentlyContinue
    if ($pkgs) {
        foreach ($p in $pkgs) {
            if ($p.Name -match "XboxGameCallableUI") {
                Write-Log "  -> Skipping protected: XboxGameCallableUI" "INFO"
                continue
            }
            Remove-AppxPackage $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
        Write-Log "  -> Uninstalled: $a" "INFO"
    } else {
        Write-Log "  -> Already absent: $a" "INFO"
    }
}

# --- LinkedIn/stub deep removal ---
Write-Log "  -> [LinkedIn] Deep removal + CDM block..." "INFO"
@("Microsoft.LinkedIn", "LinkedIn") | ForEach-Object {
    $term = $_
    Get-AppxPackage -AllUsers -Name "*$term*" -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -match $term -or $_.DisplayName -match $term } |
        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
}
$cdmLIKeys = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager")
foreach ($cdmKey in $cdmLIKeys) {
    if (Test-Path $cdmKey) {
        Set-ItemProperty -Path $cdmKey -Name "OemPreInstalledAppsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $cdmKey -Name "PreInstalledAppsEnabled"    -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $cdmKey -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}
Write-Log "  -> LinkedIn removed + CDM re-delivery blocked." "INFO"

# ==============================================================================
# PHASE 7 - NEW USER PREVENTION LAYER
# ==============================================================================
Write-Log "--- [Phase 7] New User Prevention Layer ---" "INFO"

# Clean Default User profile shortcuts
foreach ($smPath in @(
    "C:\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs",
    "C:\Users\Default\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
)) {
    if (Test-Path $smPath) {
        Get-ChildItem $smPath -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $targetPath = $shell.CreateShortcut($_.FullName).TargetPath
                if ($targetPath -match "Lenovo.*AI|OutlookForWindows|LinkedIn") {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    Write-Log "  -> Removed from Default User: $($_.Name)" "INFO"
                }
            } catch {}
        }
    }
}

# Modify Default User registry hive
$defaultNtUser = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $defaultNtUser) {
    try {
        & reg load "HKU\DefaultUser" "$defaultNtUser" 2>$null | Out-Null
        Start-Sleep -Milliseconds 500

        # News Feed
        & reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f 2>$null | Out-Null

        # --- NEW v61: ContentDeliveryManager (Spotlight ads) for Default User ---
        $cdmRegBase = "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        & reg add "$cdmRegBase" /v RotatingLockScreenEnabled        /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SubscribedContent-338387Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SubscribedContent-338388Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SubscribedContent-353694Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SoftLandingEnabled               /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SystemPaneSuggestionsEnabled      /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # Stub app delivery keys - block LinkedIn/Outlook/WhatsApp stubs for new users
        & reg add "$cdmRegBase" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v PreInstalledAppsEnabled    /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v OemPreInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v ContentDeliveryAllowed     /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v FeatureManagementEnabled   /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # Taskbar alignment: 0=Left, 1=Center (Windows 11 default is center)
        # Note: pin layout is handled by TaskbarLayoutModification.xml, not Taskband registry
        & reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # --- Copilot taskbar button for Default User ---
        & reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null | Out-Null
        & reg add "HKU\DefaultUser\Software\Microsoft\Windows\Shell\Copilot" /v IsCopilotAvailable /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # --- AI / Recall (per-user redundancy - matches machine-wide Phase 8 policy) ---
        & reg add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f 2>$null | Out-Null
        & reg add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f 2>$null | Out-Null

        [gc]::Collect()
        Start-Sleep -Seconds 1
        & reg unload "HKU\DefaultUser" 2>$null | Out-Null

        Write-Log "  -> Default User registry cleaned (Feed + CDM stubs + Copilot + Recall + Taskbar)." "INFO"

    } catch {
        Write-Log "  -> Could not modify Default User hive: $($_.Exception.Message)" "INFO"
    }
}

# Remove provisioned stub packages so they never appear in new user profiles
Write-Log "  -> Removing provisioned stub packages..." "INFO"
$stubProvisionedApps = @(
    "Microsoft.LinkedIn","Microsoft.OutlookForWindows",
    "king.com.CandyCrushSaga","king.com.CandyCrushFriends",
    "SpotifyAB.SpotifyMusic","WhatsApp"
)
foreach ($stub in $stubProvisionedApps) {
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -match $stub -or $_.DisplayName -match $stub }
    if ($prov) {
        foreach ($p in $prov) {
            Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
            Write-Log "  -> Deprovisioned: $($p.DisplayName)" "INFO"
        }
    }
}
Write-Log "  -> Provisioned stub cleanup complete." "INFO"

# --- CDM data store wipe + scheduled task disable ---
# Registry keys alone are not enough - CDM has an on-disk data store that
# gets copied to each new user profile and re-pins LinkedIn/Outlook/WhatsApp
# stubs regardless of registry settings. We must:
#   1. Delete the CDM store from the Default profile
#   2. Disable the CDM scheduled task that re-populates it
#   3. Block CDM network access via policy
Write-Log "  -> Wiping CDM data store from Default profile..." "INFO"
$cdmStorePath = "C:\Users\Default\AppData\Local\Microsoft\Windows\ContentDeliveryManager"
if (Test-Path $cdmStorePath) {
    Remove-Item $cdmStorePath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  -> CDM data store removed from Default profile." "INFO"
} else {
    Write-Log "  -> CDM data store: already absent in Default profile." "INFO"
}

# Disable CDM scheduled tasks that re-populate the data store on login
$cdmTasks = @(
    "\Microsoft\Windows\ContentDeliveryManager\ProcessContentStoreTask",
    "\Microsoft\Windows\ContentDeliveryManager\ProcessSuggestedContentTask"
)
foreach ($task in $cdmTasks) {
    try {
        $t = Get-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction Stop
        Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue | Out-Null
        Write-Log "  -> Disabled CDM task: $task" "INFO"
    } catch {
        Write-Log "  -> CDM task not found (OK): $task" "INFO"
    }
}

# Block CDM cloud content delivery via policy (belt+suspenders with registry keys)
$cloudCdmPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (!(Test-Path $cloudCdmPath)) { New-Item $cloudCdmPath -Force | Out-Null }
Set-ItemProperty -Path $cloudCdmPath -Name "DisableCloudOptimizedContent"          -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cloudCdmPath -Name "DisableWindowsSpotlightSuggestions"    -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Log "  -> CDM cloud delivery policy blocked." "INFO"

$oemPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OEMSetup"
if (Test-Path $oemPath) {
    Remove-Item $oemPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  -> OEM customizations removed." "INFO"
}

Write-Log "  -> New user prevention layer deployed." "INFO"

# ==============================================================================
# PHASE 8 - REGISTRY HARDENING & CORPORATE POLICIES
# ==============================================================================
Write-Log "--- [Phase 8] Registry Hardening & Corporate Policies ---" "INFO"

# --- AI / Recall policies ---
$aiPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
if (!(Test-Path $aiPath)) { New-Item $aiPath -Force | Out-Null }
Set-ItemProperty -Path $aiPath -Name "DisableAIDataAnalysis"  -Value 1 -Type DWord -Force
Set-ItemProperty -Path $aiPath -Name "AllowRecallEnablement"  -Value 0 -Type DWord -Force
Write-Log "  -> AI / Recall policies enforced (DisableAIDataAnalysis + AllowRecallEnablement)." "INFO"

# --- NEW v61: Copilot policy (machine-wide) ---
$copilotPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
if (!(Test-Path $copilotPath)) { New-Item $copilotPath -Force | Out-Null }
Set-ItemProperty -Path $copilotPath -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
Write-Log "  -> Copilot machine-wide policy applied." "INFO"

# --- NEW v61: Windows Spotlight / lock screen ads (machine-wide) ---
$cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (!(Test-Path $cloudPath)) { New-Item $cloudPath -Force | Out-Null }
Set-ItemProperty -Path $cloudPath -Name "DisableWindowsSpotlightFeatures"     -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cloudPath -Name "DisableWindowsSpotlightOnLockScreen" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cloudPath -Name "DisableSoftLanding"                  -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures"      -Value 1 -Type DWord -Force
Write-Log "  -> Windows Spotlight / lock screen ad policies enforced." "INFO"

# --- News Feed / Discover disable (all users via hive loading) ---
Write-Log "  -> Applying per-user policies to all profiles..." "INFO"
$users = Get-ChildItem "C:\Users" -Directory |
    Where-Object { $_.Name -notmatch "^(Public|Default|All Users)$" }
$usersProcessed = 0

foreach ($user in $users) {
    $ntUserPath = "$($user.FullName)\NTUSER.DAT"
    if (!(Test-Path $ntUserPath)) { continue }

    $hiveName = "HKU_Temp_$($user.Name)"
    try {
        & reg load "HKU\$hiveName" $ntUserPath 2>$null | Out-Null

        # News Feed
        & reg add "HKU\$hiveName\Software\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f 2>$null | Out-Null

        # --- NEW v61: ContentDeliveryManager (Spotlight / lock screen ads) ---
        $cdmBase = "HKU\$hiveName\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        & reg add "$cdmBase" /v RotatingLockScreenEnabled        /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SubscribedContent-338387Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SubscribedContent-338388Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SubscribedContent-353694Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SoftLandingEnabled               /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SystemPaneSuggestionsEnabled      /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # --- NEW v61: Copilot taskbar button per user ---
        & reg add "HKU\$hiveName\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "HKU\$hiveName\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null | Out-Null
        & reg add "HKU\$hiveName\Software\Microsoft\Windows\Shell\Copilot" /v IsCopilotAvailable /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # --- NEW v63: AI / Recall (per-user redundancy - matches machine-wide Phase 8 policy) ---
        & reg add "HKU\$hiveName\Software\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f 2>$null | Out-Null
        & reg add "HKU\$hiveName\Software\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f 2>$null | Out-Null

        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg unload "HKU\$hiveName" 2>$null | Out-Null

        $usersProcessed++
    } catch {
        # User hive locked (user logged in) - machine-wide policies still cover them
    }
}

if ($usersProcessed -gt 0) {
    Write-Log "  -> Per-user policies applied to $usersProcessed profile(s)." "INFO"
} else {
    Write-Log "  -> No offline user hives found (machine-wide policies still apply)." "INFO"
}

# Apply to current session (applies to the account running the script)
& reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f 2>$null | Out-Null

$cdmCurrent = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
if (Test-Path $cdmCurrent) {
    Set-ItemProperty -Path $cdmCurrent -Name "RotatingLockScreenEnabled"        -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $cdmCurrent -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $cdmCurrent -Name "SubscribedContent-338387Enabled"  -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $cdmCurrent -Name "SubscribedContent-338388Enabled"  -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $cdmCurrent -Name "SubscribedContent-353694Enabled"  -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $cdmCurrent -Name "SoftLandingEnabled"               -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $cdmCurrent -Name "SystemPaneSuggestionsEnabled"     -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}

Write-Log "  -> All per-user and machine-wide policies applied." "INFO"

# --- NEW v63: Copilot + Recall for current session HKCU. Low practical value
#     when running unattended as SYSTEM (this is SYSTEM's own profile, not a
#     real user - actual user coverage comes from the per-user hive loop and
#     Default User hive above), but harmless and kept consistent with the
#     rest of the policy set in case this script is ever run interactively. ---
& reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f 2>$null | Out-Null
& reg add "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null | Out-Null
& reg add "HKCU\Software\Microsoft\Windows\Shell\Copilot" /v IsCopilotAvailable /t REG_DWORD /d 0 /f 2>$null | Out-Null
& reg add "HKCU\Software\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f 2>$null | Out-Null
& reg add "HKCU\Software\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f 2>$null | Out-Null

# ==============================================================================
# PHASE 9 - CLEANUP & UI REFRESH
# ==============================================================================
Write-Log "--- [Phase 9] Cleanup & UI Refresh ---" "INFO"

# Legacy app shortcut cleanup - all user profiles
$legacyShortcutPattern = "Lenovo.*AI|OutlookForWindows|LinkedIn"
$shortcutUserProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch "^(Public|Default|All Users|defaultuser0)$" }
foreach ($userDir in $shortcutUserProfiles) {
    $shortcutPaths = @(
        "$($userDir.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs",
        "$($userDir.FullName)\Desktop",
        "$($userDir.FullName)\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    )
    foreach ($path in $shortcutPaths) {
        if (-not (Test-Path $path)) { continue }
        Get-ChildItem $path -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $lnk = $shell.CreateShortcut($_.FullName)
                if ($lnk.TargetPath -match $legacyShortcutPattern -or $_.BaseName -match $legacyShortcutPattern) {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    Write-Log "  -> Removed legacy shortcut: $($_.Name) ($($userDir.Name))" "INFO"
                }
            } catch {}
        }
    }
}
Get-ChildItem "$env:PUBLIC\Desktop" -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($_.FullName)
        if ($lnk.TargetPath -match $legacyShortcutPattern -or $_.BaseName -match $legacyShortcutPattern) {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "  -> Removed legacy shortcut from Public Desktop: $($_.Name)" "INFO"
        }
    } catch {}
}

# Rebuild icon cache
foreach ($icPath in @(
    "$env:LOCALAPPDATA\IconCache.db",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db"
)) {
    Get-ChildItem $icPath -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# Restart Explorer (interactive sessions only - not meaningful under SYSTEM)
if ($Interactive) {
    try {
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process "explorer.exe"
        Write-Log "  -> Explorer restarted." "INFO"
    } catch {
        Write-Log "  -> Explorer will restart automatically." "INFO"
    }
}

# ==============================================================================
# PHASE 10 - DEPLOYMENT SUMMARY
# ==============================================================================
Write-Log "--- [Phase 10] Deployment Summary ---" "INFO"

if ($consumerTeamsFound) {
    Write-Log "  -> Consumer Teams (MicrosoftTeams):  Removed" "INFO"
} else {
    Write-Log "  -> Consumer Teams:                   Not present" "INFO"
}
Write-Log "  -> Business Teams (MSTeams):         PROTECTED & Preserved" "INFO"
if ($lenovoAIDetected) {
    Write-Log "  -> Lenovo AI Now:                    Fully purged" "INFO"
} else {
    Write-Log "  -> Lenovo AI Now:                    Not present" "INFO"
}
Write-Log "  -> Consumer M365 / OneNote:          Purged if present (ODT)" "INFO"
Write-Log "  -> AI / Recall Infrastructure:       Stripped + Policy locked" "INFO"
Write-Log "  -> Copilot:                          Removed + Policy disabled" "INFO"
Write-Log "  -> Windows Spotlight / Lock screen:  Ads suppressed " "INFO"
Write-Log "  -> Widgets / News Feed:              Disabled (all users)" "INFO"
Write-Log "  -> ContentDeliveryManager:           Cleared (all users + Default)" "INFO"
Write-Log "  -> New User Prevention:              Deployed" "INFO"
Write-Log "  -> Lenovo Commercial Vantage:        Preserved" "INFO"
Write-Log "  -> Dolby / Elevoc Audio:             Preserved" "INFO"
if ($hpWolfFound) {
    Write-Log "  -> HP Wolf Security:                 Deep scrub complete" "INFO"
} else {
    Write-Log "  -> HP Wolf Security:                 Not present" "INFO"
}
Write-Log "  -> HP MSIX/Win32 consumer suite:     Removed" "INFO"
Write-Log "  -> LinkedIn/Outlook/WhatsApp stubs:  Removed + CDM blocked" "INFO"
Write-Log "  -> Provisioned stubs:                Deprovisioned for new users" "INFO"

$odState = "Untouched"
if ($RemoveOneDrive) { $odState = "Removed (-RemoveOneDrive)" }
Write-Log "  -> OneDrive (built-in):              $odState" "INFO"

Write-Log "=== CLEANUP COMPLETE - REBOOT REQUIRED ===" "INFO"
Write-Log "Log saved to: $LogPath" "INFO"

if ($Interactive) {
    $rebootChoice = Read-Host "`nReboot now to finalize? (Y/N)"
    if ($rebootChoice -match '^[Yy]') {
        Write-Host "Rebooting in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Restart-Computer -Force
    } else {
        Write-Host "Reboot manually to finish: locked AI packages and pending file deletions clear on next boot." -ForegroundColor Yellow
    }
}

exit 0
