$ErrorActionPreference = 'Continue'
$ProjectDir = $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$ProjectDir\scripts\common.ps1"

function Wait-ForEnter {
    Write-Host ''
    [void](Read-Host 'Press Enter to return to the menu')
}

function Show-ServerStatus {
    Write-Host ''
    Write-Host 'Palworld container:' -ForegroundColor Cyan
    & docker compose ps
    Write-Host ''
    Write-Host ("Unlim running: {0}" -f (Test-UnlimHost))
    $MonitorPidPath = Join-Path $ProjectDir 'runtime\player-monitor.pid'
    $MonitorRunning = $false
    if (Test-Path -LiteralPath $MonitorPidPath) {
        $MonitorPid = (Get-Content -LiteralPath $MonitorPidPath -Raw).Trim()
        if ($MonitorPid -match '^\d+$') {
            $MonitorRunning = $null -ne (Get-Process -Id ([int]$MonitorPid) -ErrorAction SilentlyContinue)
        }
    }
    Write-Host ("Player monitor running: {0}" -f $MonitorRunning)
}

function Show-Players {
    try {
        $Response = Invoke-PalworldApi -Method Get -Path 'players'
        $Players = @($Response.players)
        Write-Host ''
        Write-Host ("Online players: {0}" -f $Players.Count) -ForegroundColor Cyan
        foreach ($Player in $Players) { Write-Host ("- {0}" -f $Player.name) }
    }
    catch {
        Write-Warning "Could not read the player list: $($_.Exception.Message)"
    }
}

function Show-HealthSummary {
    $MetricsPath = Join-Path $ProjectDir 'logs\health-metrics.csv'
    if (-not (Test-Path -LiteralPath $MetricsPath)) {
        Write-Warning 'No health history has been recorded yet.'
        return
    }
    $Since = (Get-Date).AddHours(-24)
    $Rows = @(Import-Csv -LiteralPath $MetricsPath | Where-Object {
        try { [datetime]$_.timestamp -ge $Since } catch { $false }
    })
    if ($Rows.Count -eq 0) { Write-Warning 'No samples are available from the last 24 hours.'; return }
    $Latest = $Rows[-1]
    $OnlineRows = @($Rows | Where-Object { $_.server_online -eq 'True' })
    Write-Host ''
    Write-Host 'Latest sample' -ForegroundColor Cyan
    Write-Host ("Time: {0}" -f $Latest.timestamp)
    Write-Host ("Online: {0}" -f $Latest.server_online)
    Write-Host ("CPU: {0}% / Memory: {1}% ({2})" -f $Latest.cpu_percent, $Latest.memory_percent, $Latest.memory_usage)
    Write-Host ("FPS: {0} / Frame time: {1} ms / Players: {2}" -f $Latest.server_fps, $Latest.frame_time_ms, $Latest.players)
    Write-Host ("Disk free: {0} GB" -f $Latest.disk_free_gb)
    if ($OnlineRows.Count -gt 0) {
        $AverageFps = [math]::Round((($OnlineRows | Measure-Object server_fps -Average).Average), 1)
        $AverageCpu = [math]::Round((($OnlineRows | Measure-Object cpu_percent -Average).Average), 1)
        $PeakMemory = [math]::Round((($OnlineRows | Measure-Object memory_percent -Maximum).Maximum), 1)
        Write-Host ''
        Write-Host ("24h samples: {0} / Average FPS: {1} / Average CPU: {2}% / Peak memory: {3}%" -f $Rows.Count, $AverageFps, $AverageCpu, $PeakMemory)
    }
}

while ($true) {
    Clear-Host
    Write-Host '========================================' -ForegroundColor DarkCyan
    Write-Host ' Palworld Server Manager' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor DarkCyan
    Write-Host '1. Start server'
    Write-Host '2. Safe shutdown and backup'
    Write-Host '3. Create backup now'
    Write-Host '4. Show server status'
    Write-Host '5. Show online players'
    Write-Host '6. Follow server logs'
    Write-Host '7. Restore a backup'
    Write-Host '8. Safely update to the latest version'
    Write-Host '9. Show 24-hour health summary'
    Write-Host '10. Run all project checks'
    Write-Host '0. Exit'
    Write-Host ''
    $Choice = Read-Host 'Select'

    try {
        switch ($Choice) {
            '1' { & "$ProjectDir\scripts\start.ps1"; Wait-ForEnter }
            '2' { & "$ProjectDir\scripts\shutdown.ps1"; Wait-ForEnter }
            '3' { & "$ProjectDir\scripts\backup.ps1"; Wait-ForEnter }
            '4' { Show-ServerStatus; Wait-ForEnter }
            '5' { Show-Players; Wait-ForEnter }
            '6' { Write-Host 'Press Ctrl+C to stop viewing logs.'; & docker compose logs --follow --tail 100 }
            '7' { & "$ProjectDir\scripts\restore.ps1"; Wait-ForEnter }
            '8' { & "$ProjectDir\scripts\update-server.ps1"; Wait-ForEnter }
            '9' { Show-HealthSummary; Wait-ForEnter }
            '10' { & "$ProjectDir\scripts\test-project.ps1" -Online; Wait-ForEnter }
            '0' { return }
            default { Write-Warning 'Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
    catch {
        Write-Error $_.Exception.Message
        Wait-ForEnter
    }
}
