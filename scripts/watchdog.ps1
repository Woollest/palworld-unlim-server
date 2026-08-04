$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir 'runtime\server-enabled'))) { return }
if (Test-Path -LiteralPath (Join-Path $ProjectDir 'runtime\maintenance.lock')) { return }
& docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Invoke-DiscordNotificationSafe -Type ServiceError -Message 'Docker Desktop is unavailable. Automatic server recovery was attempted.'
    & "$PSScriptRoot\autostart.ps1"
    return
}
$Running = (& docker compose ps --status running --quiet palworld-server | Out-String).Trim()
if (-not $Running) {
    Invoke-DiscordNotificationSafe -Type ServiceError -Message 'Palworld was not running. Automatic recovery was started.'
    & "$PSScriptRoot\start.ps1"
    return
}
$PidPath = Join-Path $ProjectDir 'runtime\player-monitor.pid'
$MonitorRunning = $false
if (Test-Path -LiteralPath $PidPath) {
    $PidValue = (Get-Content -LiteralPath $PidPath -Raw).Trim()
    if ($PidValue -match '^\d+$') { $MonitorRunning = $null -ne (Get-Process -Id ([int]$PidValue) -ErrorAction SilentlyContinue) }
}
if (-not $MonitorRunning) {
    Start-PlayerMonitor
    Invoke-DiscordNotificationSafe -Type ServiceRecovered -Message 'The Palworld monitoring process was restarted automatically.'
}
