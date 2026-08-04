param(
    [string]$BackupPath = '',
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

$RunningId = ''
& docker info 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    $ContainerOutput = & docker compose ps --status running --quiet palworld-server
    if ($LASTEXITCODE -ne 0) { throw 'Failed to inspect Docker Compose status.' }
    $RunningId = ($ContainerOutput | Out-String).Trim()
}
if ($RunningId) { throw 'Stop the server before restoring a backup.' }

$BackupsDir = Join-Path $ProjectDir 'backups'
if (-not $BackupPath) {
    $Available = @(Get-ChildItem -LiteralPath $BackupsDir -Filter 'palworld-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($Available.Count -eq 0) { throw 'No backups are available.' }

    Write-Host 'Available backups:'
    for ($Index = 0; $Index -lt $Available.Count; $Index++) {
        Write-Host "[$($Index + 1)] $($Available[$Index].Name) - $($Available[$Index].LastWriteTime)"
    }
    $Selection = Read-Host 'Enter the backup number to restore'
    if ($Selection -notmatch '^\d+$' -or [int]$Selection -lt 1 -or [int]$Selection -gt $Available.Count) {
        throw 'Invalid backup selection.'
    }
    $BackupPath = $Available[[int]$Selection - 1].FullName
}
else {
    $BackupPath = (Resolve-Path -LiteralPath $BackupPath).Path
}
$ResolvedBackupsDir = (Resolve-Path -LiteralPath $BackupsDir).Path
if (-not $BackupPath.StartsWith($ResolvedBackupsDir + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The backup must be inside the project backups directory.'
}
if ([IO.Path]::GetFileName($BackupPath) -notmatch '^palworld-\d{8}-\d{6}\.zip$') {
    throw 'The backup filename is not recognized.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$Archive = [System.IO.Compression.ZipFile]::OpenRead($BackupPath)
try {
    if (-not ($Archive.Entries | Where-Object { $_.FullName -match '^Saved[\\/]' })) {
        throw 'The selected archive does not contain a Saved directory.'
    }
}
finally {
    $Archive.Dispose()
}

if (-not $NonInteractive) {
    $Confirmation = Read-Host "Type RESTORE to restore $([IO.Path]::GetFileName($BackupPath))"
    if ($Confirmation -cne 'RESTORE') {
        Write-Host 'Restore cancelled.'
        return
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$WorkRoot = Join-Path $ProjectDir 'work'
$RecoveryRoot = Join-Path $ProjectDir 'recovery'
$RestoreTemp = Join-Path $WorkRoot "restore-$Timestamp"
$SafetyPath = $null
New-Item -ItemType Directory -Force -Path $RestoreTemp, $RecoveryRoot | Out-Null

try {
    Expand-Archive -LiteralPath $BackupPath -DestinationPath $RestoreTemp
    $RestoredSaved = Join-Path $RestoreTemp 'Saved'
    if (-not (Test-Path -LiteralPath $RestoredSaved)) {
        throw 'The restored Saved directory is missing.'
    }

    $CurrentSaved = Join-Path $ProjectDir 'data\Saved'
    if (Test-Path -LiteralPath $CurrentSaved) {
        $SafetyPath = Join-Path $RecoveryRoot "Saved-before-restore-$Timestamp"
        Move-Item -LiteralPath $CurrentSaved -Destination $SafetyPath
        Write-Host "Previous data preserved: $SafetyPath"
    }
    Move-Item -LiteralPath $RestoredSaved -Destination $CurrentSaved
}
catch {
    if ($SafetyPath -and (Test-Path -LiteralPath $SafetyPath) -and -not (Test-Path -LiteralPath $CurrentSaved)) {
        Move-Item -LiteralPath $SafetyPath -Destination $CurrentSaved
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $RestoreTemp) {
        $ResolvedWork = (Resolve-Path -LiteralPath $WorkRoot).Path
        $ResolvedTemp = (Resolve-Path -LiteralPath $RestoreTemp).Path
        if ($ResolvedTemp.StartsWith($ResolvedWork + [IO.Path]::DirectorySeparatorChar)) {
            Remove-Item -LiteralPath $ResolvedTemp -Recurse -Force
        }
    }
}

Write-Host 'Restore completed. Review the recovery directory, then start the server.'
Invoke-DiscordStatusSafe -Status Offline -Detail "Backup restored: $([IO.Path]::GetFileName($BackupPath))"
$global:LASTEXITCODE = 0
