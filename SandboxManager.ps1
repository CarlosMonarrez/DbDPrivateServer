[CmdletBinding()]
param(
    [switch]$AllowUnknownSteamState
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigDir = Join-Path $ScriptRoot '.sandbox'
$ConfigPath = Join-Path $ConfigDir 'config.json'
$DefaultSteamDbDPath = 'C:\Program Files (x86)\Steam\steamapps\common\Dead by Daylight'
$DefaultSandboxPath = Join-Path $ScriptRoot 'DbDSandbox'

function Write-Title {
    Clear-Host
    Write-Host 'DBD Sandbox Manager' -ForegroundColor Cyan
    Write-Host 'Keeps the official install read-only and manages a separate offline sandbox.'
    Write-Host ''
}

function Ensure-ConfigDir {
    if (-not (Test-Path -LiteralPath $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir | Out-Null
    }
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return [pscustomobject]@{
            OfficialPath = $DefaultSteamDbDPath
            SandboxPath = $DefaultSandboxPath
            CreatedUtc = $null
            LastSyncUtc = $null
        }
    }

    return Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

function Save-Config {
    param([Parameter(Mandatory)]$Config)

    Ensure-ConfigDir
    $Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    return [System.IO.Path]::GetFullPath($expanded)
}

function Test-DbDInstall {
    param([Parameter(Mandatory)][string]$Path)

    $paks = Join-Path $Path 'DeadByDaylight\Content\Paks'
    $win64 = Join-Path $Path 'DeadByDaylight\Binaries\Win64'
    return (Test-Path -LiteralPath $paks) -and (Test-Path -LiteralPath $win64)
}

function Get-DbDPackageLayout {
    param([Parameter(Mandatory)][string]$Path)

    $paks = Join-Path $Path 'DeadByDaylight\Content\Paks'
    if (-not (Test-Path -LiteralPath $paks)) {
        return 'MissingPaksFolder'
    }

    $currentPak = Join-Path $paks 'pakchunk0-Windows.pak'
    $currentContainer = Join-Path $paks 'pakchunk0-Windows.utoc'
    $legacyPak = Join-Path $paks 'pakchunk0-WindowsNoEditor.pak'

    if ((Test-Path -LiteralPath $currentPak) -and (Test-Path -LiteralPath $currentContainer)) {
        return 'WindowsIoStore'
    }

    if (Test-Path -LiteralPath $legacyPak) {
        return 'LegacyWindowsNoEditor'
    }

    return 'Unknown'
}

function Assert-OfficialPath {
    param([Parameter(Mandatory)][string]$OfficialPath)

    if (-not (Test-DbDInstall -Path $OfficialPath)) {
        throw "The official path does not look like a Dead by Daylight install: $OfficialPath"
    }
}

function Assert-SandboxPath {
    param(
        [Parameter(Mandatory)][string]$OfficialPath,
        [Parameter(Mandatory)][string]$SandboxPath
    )

    $officialFull = Resolve-FullPath $OfficialPath
    $sandboxFull = Resolve-FullPath $SandboxPath
    $sandboxRoot = [System.IO.Path]::GetPathRoot($sandboxFull)

    if ($officialFull.TrimEnd('\') -ieq $sandboxFull.TrimEnd('\')) {
        throw 'Sandbox path cannot be the same as the official install path.'
    }

    if ($sandboxFull.TrimEnd('\') -ieq $sandboxRoot.TrimEnd('\')) {
        throw 'Sandbox path cannot be a drive root.'
    }

    if ($sandboxFull.StartsWith($officialFull.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Sandbox path cannot be inside the official install path.'
    }

    if ($officialFull.StartsWith($sandboxFull.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Sandbox path cannot be a parent folder of the official install path.'
    }
}

function Get-SteamPath {
    $candidates = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\Software\WOW6432Node\Valve\Steam',
        'HKLM:\Software\Valve\Steam'
    )

    foreach ($candidate in $candidates) {
        try {
            $props = Get-ItemProperty -Path $candidate -ErrorAction Stop
            foreach ($name in @('SteamPath', 'InstallPath')) {
                if ($props.$name) {
                    return Resolve-FullPath $props.$name
                }
            }
        } catch {
            continue
        }
    }

    return $null
}

function Get-SteamOfflineStatus {
    $steamPath = Get-SteamPath
    if (-not $steamPath) {
        return [pscustomobject]@{
            Status = 'Unknown'
            Reason = 'Steam install path was not found in the registry.'
            SteamPath = $null
        }
    }

    $loginUsers = Join-Path $steamPath 'config\loginusers.vdf'
    if (-not (Test-Path -LiteralPath $loginUsers)) {
        return [pscustomobject]@{
            Status = 'Unknown'
            Reason = "Steam loginusers.vdf was not found at $loginUsers."
            SteamPath = $steamPath
        }
    }

    $content = Get-Content -LiteralPath $loginUsers -Raw
    $wantsOffline = $content -match '"WantsOfflineMode"\s+"1"'

    if ($wantsOffline) {
        return [pscustomobject]@{
            Status = 'Offline'
            Reason = 'Steam config indicates Offline Mode.'
            SteamPath = $steamPath
        }
    }

    return [pscustomobject]@{
        Status = 'OnlineOrUnknown'
        Reason = 'Steam config does not indicate Offline Mode.'
        SteamPath = $steamPath
    }
}

function Assert-SteamOffline {
    $status = Get-SteamOfflineStatus
    if ($status.Status -eq 'Offline') {
        Write-Host "Steam Offline Mode check: $($status.Reason)" -ForegroundColor Green
        return
    }

    if ($AllowUnknownSteamState -and $status.Status -eq 'Unknown') {
        Write-Host "Steam Offline Mode check could not be confirmed: $($status.Reason)" -ForegroundColor Yellow
        Write-Host 'Continuing because -AllowUnknownSteamState was provided.' -ForegroundColor Yellow
        return
    }

    throw "Steam Offline Mode is not confirmed. $($status.Reason) Start Steam in Offline Mode before launching the sandbox."
}

function Invoke-RobocopyMirror {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $excludeDirs = @(
        '.cache'
    )

    $args = @(
        $Source,
        $Destination,
        '/MIR',
        '/R:2',
        '/W:2',
        '/NFL',
        '/NDL',
        '/NP',
        '/XD'
    ) + $excludeDirs

    Write-Host "Copying official install into sandbox:"
    Write-Host "  Source:      $Source"
    Write-Host "  Destination: $Destination"
    Write-Host ''
    Write-Host 'The source path is read-only for this manager. This can take a while.'

    & robocopy @args | Out-Host
    $exitCode = $LASTEXITCODE

    if ($exitCode -ge 8) {
        throw "Robocopy failed with exit code $exitCode."
    }
}

function Initialize-Sandbox {
    $config = Read-Config

    Write-Title
    Write-Host 'Configure paths. Press Enter to accept the shown value.'
    Write-Host ''

    $officialInput = Read-Host "Official DBD install [$($config.OfficialPath)]"
    if ([string]::IsNullOrWhiteSpace($officialInput)) {
        $officialInput = $config.OfficialPath
    }

    $sandboxInput = Read-Host "Sandbox copy path [$($config.SandboxPath)]"
    if ([string]::IsNullOrWhiteSpace($sandboxInput)) {
        $sandboxInput = $config.SandboxPath
    }

    $officialPath = Resolve-FullPath $officialInput
    $sandboxPath = Resolve-FullPath $sandboxInput

    Assert-OfficialPath -OfficialPath $officialPath
    Assert-SandboxPath -OfficialPath $officialPath -SandboxPath $sandboxPath

    $config.OfficialPath = $officialPath
    $config.SandboxPath = $sandboxPath
    if (-not $config.CreatedUtc) {
        $config.CreatedUtc = [DateTime]::UtcNow.ToString('o')
    }

    Save-Config -Config $config

    Write-Host ''
    Write-Host 'Configuration saved.' -ForegroundColor Green
}

function Sync-Sandbox {
    $config = Read-Config
    $officialPath = Resolve-FullPath $config.OfficialPath
    $sandboxPath = Resolve-FullPath $config.SandboxPath

    Assert-OfficialPath -OfficialPath $officialPath
    Assert-SandboxPath -OfficialPath $officialPath -SandboxPath $sandboxPath

    if (-not (Test-Path -LiteralPath $sandboxPath)) {
        New-Item -ItemType Directory -Path $sandboxPath | Out-Null
    }

    Invoke-RobocopyMirror -Source $officialPath -Destination $sandboxPath

    $config.LastSyncUtc = [DateTime]::UtcNow.ToString('o')
    Save-Config -Config $config

    Write-Host ''
    Write-Host 'Sandbox sync complete. The official install was not modified.' -ForegroundColor Green
}

function Import-LocalPak {
    $config = Read-Config
    $sandboxPath = Resolve-FullPath $config.SandboxPath
    Assert-SandboxPath -OfficialPath (Resolve-FullPath $config.OfficialPath) -SandboxPath $sandboxPath

    if (-not (Test-DbDInstall -Path $sandboxPath)) {
        throw 'The sandbox does not look initialized. Sync the sandbox first.'
    }

    $source = Read-Host 'Path to a local .pak or .sig file'
    $sourcePath = Resolve-FullPath $source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "File not found: $sourcePath"
    }

    $extension = [System.IO.Path]::GetExtension($sourcePath)
    if ($extension -notin @('.pak', '.sig', '.ucas', '.utoc')) {
        throw 'Only .pak, .sig, .ucas, and .utoc files can be imported by this manager. It will not install executables or DLLs.'
    }

    $paksPath = Join-Path $sandboxPath 'DeadByDaylight\Content\Paks'
    if (-not (Test-Path -LiteralPath $paksPath)) {
        throw "Sandbox Paks folder not found: $paksPath"
    }

    Copy-Item -LiteralPath $sourcePath -Destination $paksPath -Force
    Write-Host ''
    Write-Host "Imported into sandbox only: $paksPath" -ForegroundColor Green
}

function Open-SandboxFolder {
    $config = Read-Config
    $sandboxPath = Resolve-FullPath $config.SandboxPath

    if (-not (Test-Path -LiteralPath $sandboxPath)) {
        throw "Sandbox folder does not exist yet: $sandboxPath"
    }

    Invoke-Item -LiteralPath $sandboxPath
}

function Launch-Sandbox {
    $config = Read-Config
    $sandboxPath = Resolve-FullPath $config.SandboxPath
    Assert-SandboxPath -OfficialPath (Resolve-FullPath $config.OfficialPath) -SandboxPath $sandboxPath
    Assert-SteamOffline

    if (-not (Test-DbDInstall -Path $sandboxPath)) {
        throw 'The sandbox does not look initialized. Sync the sandbox first.'
    }

    $launcher = Join-Path $sandboxPath 'DeadByDaylight.exe'
    $shipping = Join-Path $sandboxPath 'DeadByDaylight\Binaries\Win64\DeadByDaylight-Win64-Shipping.exe'

    if (Test-Path -LiteralPath $launcher) {
        Start-Process -FilePath $launcher -WorkingDirectory $sandboxPath
        return
    }

    if (Test-Path -LiteralPath $shipping) {
        Start-Process -FilePath $shipping -WorkingDirectory (Split-Path -Parent $shipping)
        return
    }

    throw 'No known DBD executable was found inside the sandbox.'
}

function Show-Status {
    $config = Read-Config
    $steam = Get-SteamOfflineStatus

    Write-Title
    Write-Host "Official path: $($config.OfficialPath)"
    Write-Host "Sandbox path:  $($config.SandboxPath)"
    Write-Host "Last sync UTC: $($config.LastSyncUtc)"
    Write-Host "Steam state:   $($steam.Status) - $($steam.Reason)"
    Write-Host "Official layout: $(Get-DbDPackageLayout -Path (Resolve-FullPath $config.OfficialPath))"
    Write-Host "Sandbox layout:  $(Get-DbDPackageLayout -Path (Resolve-FullPath $config.SandboxPath))"
    Write-Host ''

    if (Test-DbDInstall -Path (Resolve-FullPath $config.OfficialPath)) {
        Write-Host 'Official install check: found' -ForegroundColor Green
    } else {
        Write-Host 'Official install check: not found or invalid' -ForegroundColor Yellow
    }

    if (Test-DbDInstall -Path (Resolve-FullPath $config.SandboxPath)) {
        Write-Host 'Sandbox install check: found' -ForegroundColor Green
    } else {
        Write-Host 'Sandbox install check: not initialized' -ForegroundColor Yellow
    }
}

function Invoke-MenuAction {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Choice)

    switch ($Choice) {
        '1' { Initialize-Sandbox }
        '2' { Sync-Sandbox }
        '3' { Import-LocalPak }
        '4' { Launch-Sandbox }
        '5' { Open-SandboxFolder }
        '6' { Show-Status }
        'Q' { return $false }
        default {
            Write-Host 'Invalid option.' -ForegroundColor Yellow
        }
    }

    return $true
}

do {
    Write-Title
    Write-Host '[1] Configure paths'
    Write-Host '[2] Sync official install to sandbox'
    Write-Host '[3] Import local package file into sandbox'
    Write-Host '[4] Launch sandbox (requires Steam Offline Mode)'
    Write-Host '[5] Open sandbox folder'
    Write-Host '[6] Status'
    Write-Host '[Q] Quit'
    Write-Host ''

    $rawChoice = Read-Host 'Select an option'
    if ($null -eq $rawChoice) {
        break
    }
    $choice = $rawChoice.Trim().ToUpperInvariant()
    $continue = $true

    try {
        $continue = Invoke-MenuAction -Choice $choice
    } catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

    if ($continue) {
        Write-Host ''
        Read-Host 'Press Enter to continue' | Out-Null
    }
} while ($continue)
