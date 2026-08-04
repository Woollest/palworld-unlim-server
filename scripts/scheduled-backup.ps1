$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir 'runtime\server-enabled'))) { return }
if (Test-Path -LiteralPath (Join-Path $ProjectDir 'runtime\maintenance.lock')) { return }
$IntervalHours = [double](Get-ProjectSetting -Name 'AUTO_BACKUP_INTERVAL_HOURS' -Default '6')
$Latest = Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'backups') -Filter 'palworld-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($Latest -and $Latest.LastWriteTime -gt (Get-Date).AddHours(-$IntervalHours)) { return }
try {
    $Response = Invoke-PalworldApi -Method Get -Path 'players'
    $Players = @($Response.players)
    if ($Players.Count -gt 0) {
        Write-Host "Backup deferred because $($Players.Count) player(s) are online."
        return
    }
    & "$PSScriptRoot\backup.ps1" -Mode Scheduled
}
catch {
    throw
}
