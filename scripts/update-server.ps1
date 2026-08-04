$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$PSScriptRoot\common.ps1"

function Get-LatestOfficialImage {
    $Token = (Invoke-RestMethod -Uri 'https://ghcr.io/token?scope=repository:pocketpairjp/palserver:pull' -Headers @{ 'User-Agent' = 'Palworld-Safe-Updater' }).token
    $Tags = (Invoke-RestMethod -Uri 'https://ghcr.io/v2/pocketpairjp/palserver/tags/list' -Headers @{ Authorization = "Bearer $Token"; 'User-Agent' = 'Palworld-Safe-Updater' }).tags
    $Versions = @($Tags | Where-Object { $_ -match '^v?\d+\.\d+\.\d+\.\d+$' } | ForEach-Object {
        [pscustomobject]@{ Tag = $_; Version = [version]($_ -replace '^v') }
    } | Sort-Object Version -Descending)
    if ($Versions.Count -eq 0) { throw 'The official registry returned no versioned Palworld images.' }
    return "ghcr.io/pocketpairjp/palserver:$($Versions[0].Tag)"
}

function Restore-UpdateBackup {
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $RestoreRoot = Join-Path $ProjectDir "work\update-rollback-$Timestamp"
    $RecoveryRoot = Join-Path $ProjectDir 'recovery'
    $FailedSaved = Join-Path $RecoveryRoot "Saved-after-failed-update-$Timestamp"
    New-Item -ItemType Directory -Force -Path $RestoreRoot, $RecoveryRoot | Out-Null
    Expand-Archive -LiteralPath $BackupPath -DestinationPath $RestoreRoot -Force
    $RestoredSaved = Join-Path $RestoreRoot 'Saved'
    if (-not (Test-Path -LiteralPath (Join-Path $RestoredSaved 'SaveGames'))) {
        throw 'Rollback backup does not contain Saved\SaveGames.'
    }
    if (Test-Path -LiteralPath (Join-Path $ProjectDir 'data\Saved')) {
        Move-Item -LiteralPath (Join-Path $ProjectDir 'data\Saved') -Destination $FailedSaved
    }
    Move-Item -LiteralPath $RestoredSaved -Destination (Join-Path $ProjectDir 'data\Saved')
    Remove-Item -LiteralPath $RestoreRoot -Recurse -Force -ErrorAction SilentlyContinue
    return $FailedSaved
}

if (-not (Test-Path -LiteralPath '.env')) { throw '.env does not exist.' }
& docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is not ready.' }

$OldEnv = Get-Content -LiteralPath '.env' -Raw
$OldImage = Get-ProjectSetting -Name 'PALWORLD_IMAGE'
$NewImage = Get-LatestOfficialImage
$OldTag = ($OldImage -split ':')[-1]
$NewTag = ($NewImage -split ':')[-1]

Write-Host "Current image: $OldImage"
Write-Host "Latest image:  $NewImage"
if ([version]($NewTag -replace '^v') -le [version]($OldTag -replace '^v')) {
    Write-Host 'The server already uses the latest official version.' -ForegroundColor Green
    return
}

try {
    $PlayerResponse = Invoke-PalworldApi -Method Get -Path 'players'
    $Players = @($PlayerResponse.players)
    Write-Host ("Online players: {0}" -f $Players.Count)
}
catch {
    throw "The player list could not be checked, so the update was cancelled: $($_.Exception.Message)"
}

$Confirmation = Read-Host "Type UPDATE $NewTag to continue"
if ($Confirmation -cne "UPDATE $NewTag") {
    Write-Host 'Update cancelled.'
    return
}

$BackupPath = $null
$ImageChanged = $false
try {
    & "$PSScriptRoot\shutdown.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Safe shutdown failed.' }

    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'backups') -Filter '*.zip' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $BackupPath) { throw 'The update backup could not be located.' }

    $NewEnv = [regex]::Replace($OldEnv, '(?m)^PALWORLD_IMAGE=.*$', "PALWORLD_IMAGE=$NewImage")
    Set-Content -LiteralPath '.env' -Value $NewEnv -Encoding UTF8
    $ImageChanged = $true

    Invoke-DiscordNotificationSafe -Type Information -Message "Palworld server update started: $OldTag -> $NewTag."
    & "$PSScriptRoot\start.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'The updated server did not start successfully.' }

    $Info = Invoke-PalworldApi -Method Get -Path 'info'
    Remove-Item -LiteralPath (Join-Path $ProjectDir 'runtime\version-notified') -Force -ErrorAction SilentlyContinue
    Invoke-DiscordNotificationSafe -Type Information -Message "Palworld server update completed: $OldTag -> $NewTag. Backup: $([IO.Path]::GetFileName($BackupPath))"
    Write-Host "Update completed: $OldTag -> $NewTag" -ForegroundColor Green
}
catch {
    $UpdateError = $_.Exception.Message
    Write-Warning "Update failed: $UpdateError"
    if (-not $ImageChanged -or -not $BackupPath) {
        Invoke-DiscordNotificationSafe -Type ServiceError -Message "Palworld update stopped before the image was changed: $UpdateError"
        throw
    }

    Write-Warning 'Restoring the previous image and pre-update save...'
    try {
        & docker compose down --timeout 30 2>&1 | Out-Null
        Set-Content -LiteralPath '.env' -Value $OldEnv -Encoding UTF8
        $FailedSaved = Restore-UpdateBackup -BackupPath $BackupPath
        & "$PSScriptRoot\start.ps1"
        if ($LASTEXITCODE -ne 0) { throw 'The previous server version did not restart.' }
        Invoke-DiscordNotificationSafe -Type ServiceRecovered -Message "Palworld update failed and was rolled back to $OldTag. Failed-update data was retained for diagnosis."
        Write-Warning "Rollback completed. Failed-update data: $FailedSaved"
    }
    catch {
        $RollbackError = $_.Exception.Message
        Invoke-DiscordNotificationSafe -Type ServiceError -Message "Palworld update and automatic rollback failed. Manual recovery is required: $RollbackError"
        throw "Update failed: $UpdateError; rollback failed: $RollbackError"
    }
}
