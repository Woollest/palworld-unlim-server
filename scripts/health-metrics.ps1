$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$PSScriptRoot\common.ps1"

$LogsDir = Join-Path $ProjectDir 'logs'
$MetricsPath = Join-Path $LogsDir 'health-metrics.csv'
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

$Row = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    server_online = $false
    cpu_percent = $null
    memory_percent = $null
    memory_usage = ''
    server_fps = $null
    frame_time_ms = $null
    players = $null
    max_players = $null
    uptime_seconds = $null
    base_camps = $null
    world_days = $null
    disk_free_gb = [math]::Round((Get-PSDrive -Name ([IO.Path]::GetPathRoot($ProjectDir).Substring(0, 1))).Free / 1GB, 2)
}

$ContainerId = (& docker compose ps --status running --quiet palworld-server 2>$null | Out-String).Trim()
if ($ContainerId) {
    $Row.server_online = $true
    $StatsText = (& docker stats --no-stream --format '{{json .}}' palworld-server 2>$null | Out-String).Trim()
    if ($StatsText) {
        $Stats = $StatsText | ConvertFrom-Json
        $Row.cpu_percent = [double](($Stats.CPUPerc -replace '%', '').Trim())
        $Row.memory_percent = [double](($Stats.MemPerc -replace '%', '').Trim())
        $Row.memory_usage = $Stats.MemUsage
    }
    try {
        $Metrics = Invoke-PalworldApi -Method Get -Path 'metrics'
        $Row.server_fps = $Metrics.serverfps
        $Row.frame_time_ms = $Metrics.serverframetime
        $Row.players = $Metrics.currentplayernum
        $Row.max_players = $Metrics.maxplayernum
        $Row.uptime_seconds = $Metrics.uptime
        $Row.base_camps = $Metrics.basecampnum
        $Row.world_days = $Metrics.days
    }
    catch {
        Write-Warning "Palworld metrics could not be read: $($_.Exception.Message)"
    }
}

$Object = [pscustomobject]$Row
if (Test-Path -LiteralPath $MetricsPath) {
    $Object | Export-Csv -LiteralPath $MetricsPath -Append -NoTypeInformation -Encoding UTF8
}
else {
    $Object | Export-Csv -LiteralPath $MetricsPath -NoTypeInformation -Encoding UTF8
}
