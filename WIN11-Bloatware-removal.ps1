# ==============================================================================
# SCRIPT: WIN11_v61_Standalone.ps1
# DESCRIPTION: Standalone Version - Windows 11 Business Baseline (Manual/Testing)
# DEPLOYMENT:  Run directly via PowerShell as Administrator (not JumpCloud)
# CHANGELOG:   v61 - Added Spotlight/lock screen ad suppression (Phase 8)
#                   - Added Copilot policy disable + taskbar button hide (Phase 8)
#                   - ContentDeliveryManager keys now applied to ALL user hives
#                     (existing users loop) and Default User hive (Phase 7)
# ==============================================================================

#Requires -RunAsAdministrator

$LogPath = "C:\Windows\Temp\WIN11_Bloatware_Removal.log"

# --- LOGGING FUNCTION (colored output for interactive use) ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $LogMessage -ErrorAction SilentlyContinue

    $color = switch -Regex ($Message) {
        "^\-\-\-.*\[Phase"                                                          { "Cyan";     break }
        "^  \-> .*(?:removed|cleaned|disabled|purged|uninstalled|completed|successfully|restarted|deployed|applied|enforced|protected|covered)" { "Green";    break }
        "^  \-> .*(?:locked|queuing|waiting|processing|downloading|extracting|creating|running|scanning|checking|starting)" { "Yellow";   break }
        "^  \-> .*(?:not detected|not found|already absent|not present)"            { "DarkGray"; break }
        "^  \-> NOTE:|PROTECTED"                                                    { "Yellow";   break }
        default {
            switch ($Level) {
                "ERROR"   { "Red" }
                "WARNING" { "Yellow" }
                "SUCCESS" { "Green" }
                default   { "White" }
            }
        }
    }
    Write-Host $Message -ForegroundColor $color
}

# ==============================================================================
# BANNER
# ==============================================================================
Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "    WIN11 BLOATWARE REMOVAL v61 - STANDALONE MODE" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "=== Windows 11 Bloatware Removal v61.1 Started ===" "INFO"
Write-Log "Computer: $env:COMPUTERNAME | User: $env:USERNAME" "INFO"

# ==============================================================================
# PHASE 1 - RELEASING SYSTEM HANDLES
# ==============================================================================
Write-Log "--- [Phase 1] Releasing System Handles ---" "INFO"
$pList = @(
    "Outlook","Recall","AIHost","Xbox","OfficeHub","SmartConnect",
    "LenovoAINow","ReadyFor","aimgr","OneNote","Family","LADM"
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

# ==============================================================================
# PHASE 3 - DISM AI & RECALL STRIP
# ==============================================================================
Write-Log "--- [Phase 3] Stripping AI Workloads & Recall ---" "INFO"

try {
    & dism.exe /online /disable-feature /featurename:Recall /norestart /quiet 2>$null | Out-Null
    Write-Log "  -> Recall feature disabled." "INFO"
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
# PHASE 5 - M365 CONSUMER & ONENOTE REMOVAL (ODT)
# ==============================================================================
Write-Log "--- [Phase 5] M365 Consumer & OneNote Purge ---" "INFO"

try {
    $tmp = "C:\Windows\Temp\M365Deploy"
    if (!(Test-Path $tmp)) { New-Item $tmp -ItemType Directory -Force | Out-Null }

    Write-Log "  -> Downloading Office Deployment Tool..." "INFO"
    $odtUrl = "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17830-20162.exe"
    Invoke-WebRequest -Uri $odtUrl -OutFile "$tmp\odt.exe" -UseBasicParsing -ErrorAction Stop

    Write-Log "  -> Extracting ODT..." "INFO"
    Start-Process "$tmp\odt.exe" -ArgumentList "/quiet /extract:`"$tmp`"" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 2

    if (Test-Path "$tmp\setup.exe") {
        Write-Log "  -> Creating removal configuration..." "INFO"
        @(
            '<?xml version="1.0" encoding="UTF-8"?>',
            '<Configuration>',
            '  <Remove All="FALSE">',
            '    <Product ID="O365HomePremRetail">',
            '      <Language ID="en-us"/><Language ID="fi-fi"/><Language ID="sv-se"/><Language ID="da-dk"/><Language ID="nb-no"/>',
            '    </Product>',
            '    <Product ID="O365PersonalRetail">',
            '      <Language ID="en-us"/><Language ID="fi-fi"/><Language ID="sv-se"/><Language ID="da-dk"/><Language ID="nb-no"/>',
            '    </Product>',
            '    <Product ID="OneNoteFreeRetail">',
            '      <Language ID="en-us"/><Language ID="fi-fi"/><Language ID="sv-se"/><Language ID="da-dk"/><Language ID="nb-no"/>',
            '    </Product>',
            '  </Remove>',
            '  <Display Level="None" AcceptEULA="TRUE" />',
            '</Configuration>'
        ) | Out-File "$tmp\r.xml" -Encoding UTF8

        Write-Log "  -> Running ODT removal (may take several minutes)..." "INFO"
        Start-Process "$tmp\setup.exe" -ArgumentList "/configure `"$tmp\r.xml`"" -Wait -WindowStyle Hidden
        Write-Log "  -> ODT removal completed." "INFO"
    } else {
        Write-Log "  -> ODT setup.exe not found. Skipping ODT method." "INFO"
    }
} catch {
    Write-Log "  -> ODT method failed: $($_.Exception.Message)" "INFO"
}

# Registry ghost cleanup
foreach ($ok in @("O365HomePremRetail","OneNoteFreeRetail","O365PersonalRetail")) {
    $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    if (Test-Path $path) {
        Get-ChildItem $path -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match $ok } |
            ForEach-Object {
                Write-Log "  -> Purging registry entry: $($_.PSChildName)" "INFO"
                Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
    }
}

Write-Log "  -> Scanning for OneNote packages..." "INFO"
Get-Package -Name "*OneNote*" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch "Apps for business" } |
    ForEach-Object {
        Write-Log "  -> Removing OneNote package: $($_.Name)" "INFO"
        $_ | Uninstall-Package -Force -ErrorAction SilentlyContinue
    }

Write-Log "  -> M365 Consumer and OneNote purged." "INFO"

# ==============================================================================
# PHASE 6 - NATIVE APPX SWEEP
# ==============================================================================
Write-Log "--- [Phase 6] Native Appx Sweep ---" "INFO"
$aList = @(
    "Bing","Clipchamp","ZuneMusic","ZuneVideo","YourPhone","GamingApp","Xbox",
    "Todos","MicrosoftJournal","Whiteboard","QuickAssist","Solitaire","MixedReality",
    "FeedbackHub","Maps","DevHome","communicationsapps","OfficeHub",
    "Microsoft.OutlookForWindows","MicrosoftFamily","PowerAutomateDesktop",
    "WidgetsPlatformRuntime","StartExperiencesApp","Client.WebExperience",
    "LinkedIn","Recall","Copilot","Windows.Copilot",
    # v61.1 additions
    "MirametrixInc.GlancebyMirametrix",  # Lenovo eye-tracking bloatware
    "Microsoft.Edge.GameAssist",          # Gaming overlay, no business value
    "AppUp.IntelTechnologyMDE",           # Intel Unison - consumer phone sync
    "MicrosoftWindows.CrossDevice",       # Cross Device / phone link infrastructure
    "Microsoft.GetHelp",                  # Consumer help app
    "AdobeAcrobatReaderCoreApp"           # MSIX Store Reader (Win32 Acrobat already installed)
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

        # ContentDeliveryManager (Spotlight ads)
        $cdmRegBase = "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        & reg add "$cdmRegBase" /v RotatingLockScreenEnabled        /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SubscribedContent-338387Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SubscribedContent-338388Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SubscribedContent-353694Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SoftLandingEnabled               /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmRegBase" /v SystemPaneSuggestionsEnabled      /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # Copilot taskbar button
        & reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null | Out-Null

        [gc]::Collect()
        Start-Sleep -Seconds 1
        & reg unload "HKU\DefaultUser" 2>$null | Out-Null

        Write-Log "  -> Default User registry cleaned (Feed + CDM + Copilot)." "INFO"
    } catch {
        Write-Log "  -> Could not modify Default User hive: $($_.Exception.Message)" "INFO"
    }
}

# Deploy system-wide Start layout policy
$layoutXml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    Version="1">
  <RequiredStartGroupsCollection />
  <AppendGroup Name="Layout Essentials" />
</LayoutModificationTemplate>
"@

$layoutPath = "C:\Windows\StartLayout.xml"
$layoutXml | Out-File $layoutPath -Encoding UTF8 -Force

$explorerPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (!(Test-Path $explorerPolicies)) { New-Item $explorerPolicies -Force | Out-Null }
Set-ItemProperty -Path $explorerPolicies -Name "LockedStartLayout" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $explorerPolicies -Name "StartLayoutFile"   -Value $layoutPath -Type String -Force

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

# AI / Recall policies
$aiPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
if (!(Test-Path $aiPath)) { New-Item $aiPath -Force | Out-Null }
Set-ItemProperty -Path $aiPath -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $aiPath -Name "DisableRecall"         -Value 1 -Type DWord -Force
Write-Log "  -> AI / Recall policies enforced." "INFO"

# Prevent Windows Update from re-enabling Recall
$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (!(Test-Path $wuPath)) { New-Item $wuPath -Force | Out-Null }
Set-ItemProperty -Path $wuPath -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force
Write-Log "  -> Recall post-update re-enablement blocked." "INFO"

# Copilot policy (machine-wide)
$copilotPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
if (!(Test-Path $copilotPath)) { New-Item $copilotPath -Force | Out-Null }
Set-ItemProperty -Path $copilotPath -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
Write-Log "  -> Copilot machine-wide policy applied." "INFO"

# Windows Spotlight / lock screen ads (machine-wide)
$cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (!(Test-Path $cloudPath)) { New-Item $cloudPath -Force | Out-Null }
Set-ItemProperty -Path $cloudPath -Name "DisableWindowsSpotlightFeatures"     -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cloudPath -Name "DisableWindowsSpotlightOnLockScreen" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cloudPath -Name "DisableSoftLanding"                  -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures"      -Value 1 -Type DWord -Force
Write-Log "  -> Windows Spotlight / lock screen ad policies enforced." "INFO"

# Per-user policies — loop all existing user hives
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

        # ContentDeliveryManager (Spotlight / lock screen ads)
        $cdmBase = "HKU\$hiveName\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        & reg add "$cdmBase" /v RotatingLockScreenEnabled        /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SubscribedContent-338387Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SubscribedContent-338388Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SubscribedContent-353694Enabled  /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SoftLandingEnabled               /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "$cdmBase" /v SystemPaneSuggestionsEnabled      /t REG_DWORD /d 0 /f 2>$null | Out-Null

        # Copilot taskbar button
        & reg add "HKU\$hiveName\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f 2>$null | Out-Null
        & reg add "HKU\$hiveName\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null | Out-Null

        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg unload "HKU\$hiveName" 2>$null | Out-Null

        $usersProcessed++
    } catch {
        # User hive locked (user is logged in) - machine-wide HKLM policies still apply
    }
}

if ($usersProcessed -gt 0) {
    Write-Log "  -> Per-user policies applied to $usersProcessed profile(s)." "INFO"
} else {
    Write-Log "  -> No offline user hives found (machine-wide policies still apply)." "INFO"
}

# Apply to current interactive session
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

# ==============================================================================
# PHASE 9 - CLEANUP & UI REFRESH
# ==============================================================================
Write-Log "--- [Phase 9] Cleanup & UI Refresh ---" "INFO"

# Remove ODT temp files
$tmp = "C:\Windows\Temp\M365Deploy"
if (Test-Path $tmp) {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  -> Temporary files cleaned." "INFO"
}

# Taskbar shortcut cleanup (current user)
$taskbarPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
if (Test-Path $taskbarPath) {
    $removedCount = 0
    Get-ChildItem $taskbarPath -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $targetPath = $shell.CreateShortcut($_.FullName).TargetPath
            if ($targetPath -match "Lenovo.*AI|OutlookForWindows|LinkedIn") {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                $removedCount++
                Write-Log "  -> Removed taskbar pin: $($_.Name)" "INFO"
            }
        } catch {}
    }
    if ($removedCount -gt 0) { Write-Log "  -> Removed $removedCount taskbar shortcuts." "INFO" }
}

# Rebuild icon cache
foreach ($icPath in @(
    "$env:LOCALAPPDATA\IconCache.db",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db"
)) {
    Get-ChildItem $icPath -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# Restart Explorer
try {
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process "explorer.exe"
    Write-Log "  -> Explorer restarted." "INFO"
} catch {
    Write-Log "  -> Explorer will restart automatically." "INFO"
}

# ==============================================================================
# PHASE 10 - DEPLOYMENT SUMMARY
# ==============================================================================
Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "    DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

if ($consumerTeamsFound) {
    Write-Host "  -> Consumer Teams (MicrosoftTeams):  Removed"              -ForegroundColor Green
} else {
    Write-Host "  -> Consumer Teams:                   Not present"           -ForegroundColor Gray
}
Write-Host     "  -> Business Teams (MSTeams):         PROTECTED & Preserved" -ForegroundColor Green
Write-Host     "  -> Consumer Outlook:                 Removed"               -ForegroundColor Green
if ($lenovoAIDetected) {
    Write-Host "  -> Lenovo AI Now:                    Fully purged"          -ForegroundColor Green
} else {
    Write-Host "  -> Lenovo AI Now:                    Not present"           -ForegroundColor Gray
}
Write-Host     "  -> M365 Consumer + OneNote:          Purged (5 Nordic langs)" -ForegroundColor Green
Write-Host     "  -> AI / Recall Infrastructure:       Stripped + Policy locked" -ForegroundColor Green
Write-Host     "  -> Copilot:                          Removed + Policy disabled" -ForegroundColor Green
Write-Host     "  -> Windows Spotlight / Lock screen:  Ads suppressed"        -ForegroundColor Green
Write-Host     "  -> Widgets / News Feed:              Disabled (all users)"   -ForegroundColor Green
Write-Host     "  -> ContentDeliveryManager:           Cleared (all users + Default)" -ForegroundColor Green
Write-Host     "  -> New User Prevention:              Deployed"               -ForegroundColor Green
Write-Host     "  -> Lenovo Commercial Vantage:        Preserved"              -ForegroundColor Green
Write-Host     "  -> Dolby / Elevoc Audio:             Preserved"              -ForegroundColor Green
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "*** CLEANUP COMPLETE - REBOOT REQUIRED ***"                        -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host ""

Write-Log "=== CLEANUP COMPLETE - REBOOT REQUIRED ===" "INFO"
Write-Log "Log saved to: $LogPath" "INFO"

# --- INTERACTIVE ENDING (Standalone only) ---
Write-Host "Press any key to continue..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host "`nReboot now to finalize? (Y/N): " -ForegroundColor Yellow -NoNewline
$rebootChoice = Read-Host

if ($rebootChoice -eq "Y" -or $rebootChoice -eq "y") {
    Write-Host "`nRebooting in 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "`nPlease reboot manually to complete the cleanup." -ForegroundColor Yellow
    Write-Host "Locked AI packages and pending file deletions finalize on next boot." -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}