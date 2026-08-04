$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

$DashboardPort = [int](Get-ProjectSetting -Name 'DASHBOARD_PORT' -Default '8765')
$DashboardReady = $false
try { $DashboardReady = (Invoke-WebRequest -Uri "http://127.0.0.1:$DashboardPort/api/status" -TimeoutSec 2 -UseBasicParsing).StatusCode -eq 200 } catch {}
if (-not $DashboardReady) {
    $DashboardLog = Join-Path $ProjectDir 'logs\dashboard.log'
    $DashboardError = Join-Path $ProjectDir 'logs\dashboard-error.log'
    $PowerShellExecutable = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    Start-Process -FilePath $PowerShellExecutable -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\dashboard.ps1`"", '-NoBrowser') -WorkingDirectory $ProjectDir -WindowStyle Hidden -RedirectStandardOutput $DashboardLog -RedirectStandardError $DashboardError | Out-Null
}

$DiscordConfigPath = Join-Path $ProjectDir 'config\discord.env'
if (Test-Path -LiteralPath $DiscordConfigPath) {
    $DiscordConfig = @{}
    foreach ($Line in Get-Content -LiteralPath $DiscordConfigPath) { if ($Line -match '^([^#=]+)=(.*)$') { $DiscordConfig[$Matches[1].Trim()] = $Matches[2].Trim() } }
    $DiscordCommandPidPath = Join-Path $ProjectDir 'runtime\discord-command-bot.pid'
    $DiscordCommandRunning = $false
    if (Test-Path -LiteralPath $DiscordCommandPidPath) {
        $DiscordCommandPid = (Get-Content -LiteralPath $DiscordCommandPidPath -Raw).Trim()
        if ($DiscordCommandPid -match '^\d+$') { $DiscordCommandRunning = $null -ne (Get-Process -Id ([int]$DiscordCommandPid) -ErrorAction SilentlyContinue) }
    }
    if ($DiscordConfig['DISCORD_ENABLED'] -eq 'true' -and $DiscordConfig['DISCORD_BOT_TOKEN'] -and $DiscordConfig['DISCORD_CHANNEL_ID'] -and -not $DiscordCommandRunning) {
        $DiscordCommandLog = Join-Path $ProjectDir 'logs\discord-command.log'
        $DiscordCommandError = Join-Path $ProjectDir 'logs\discord-command-process-error.log'
        $PowerShellExecutable = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
        Start-Process -FilePath $PowerShellExecutable -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\discord-command-bot.ps1`"") -WorkingDirectory $ProjectDir -WindowStyle Hidden -RedirectStandardOutput $DiscordCommandLog -RedirectStandardError $DiscordCommandError | Out-Null
    }
}

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
