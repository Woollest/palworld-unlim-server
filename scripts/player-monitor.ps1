$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

$StatePath = Join-Path $ProjectDir 'runtime\player-monitor-state.json'
$EventsPath = Join-Path $ProjectDir 'logs\player-events.csv'
$Interval = [int](Get-ProjectSetting -Name 'MONITOR_INTERVAL_SECONDS' -Default '30')
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir 'logs') | Out-Null
if (-not (Test-Path -LiteralPath $EventsPath)) { 'timestamp,event,name,accountName,userId' | Set-Content -LiteralPath $EventsPath -Encoding UTF8 }

$Previous = @{}
if (Test-Path -LiteralPath $StatePath) {
    try {
        $SavedPlayers = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
        foreach ($Player in $SavedPlayers) { $Previous[$Player.userId] = $Player }
    } catch {}
}
$PalworldFailureCount = 0
$PalworldAlerted = $false
$UnlimAlerted = $false
$DiskAlerted = $false

while ($true) {
    try {
        $DriveName = ([IO.Path]::GetPathRoot($ProjectDir)).TrimEnd('\').TrimEnd(':')
        $Drive = Get-PSDrive -Name $DriveName
        $FreeGb = $Drive.Free / 1GB
        $WarningGb = [double](Get-ProjectSetting -Name 'DISK_WARNING_FREE_GB' -Default '20')
        if ($FreeGb -lt $WarningGb -and -not $DiskAlerted) {
            Invoke-DiscordNotificationSafe -Type ServiceError -Message ('Disk space is low: {0:N1} GB free. Backups or saves may fail.' -f $FreeGb)
            $DiskAlerted = $true
        }
        elseif ($FreeGb -ge ($WarningGb + 5) -and $DiskAlerted) {
            Invoke-DiscordNotificationSafe -Type ServiceRecovered -Message ('Disk space recovered: {0:N1} GB free.' -f $FreeGb)
            $DiskAlerted = $false
        }
    }
    catch { Write-Warning "Disk space check failed: $($_.Exception.Message)" }

    if (-not (Test-UnlimHost)) {
        if (-not $UnlimAlerted) {
            Invoke-DiscordNotificationSafe -Type ServiceError -Message 'Unlim stopped unexpectedly. Automatic recovery has started.'
            Invoke-DiscordConnectionSafe -State Offline
            $UnlimAlerted = $true
        }
        try {
            Start-UnlimHost | Out-Null
            $NewKey = Get-UnlimConnectionKey
            if (-not $NewKey) { throw 'The recovered Unlim process did not provide a connection key.' }
            Invoke-DiscordConnectionSafe -State Online -ConnectionKey $NewKey
            Invoke-DiscordNotificationSafe -Type ServiceRecovered -Message 'Unlim was restarted automatically. The connection information has been updated.'
            $UnlimAlerted = $false
        }
        catch {
            Write-Warning "Unlim automatic recovery failed: $($_.Exception.Message)"
        }
    }

    try {
        $Response = Invoke-PalworldApi -Method Get -Path 'players'
        $Players = @($Response.players)
        $Current = @{}
        foreach ($Player in $Players) { $Current[$Player.userId] = $Player }

        foreach ($Id in $Current.Keys) {
            if (-not $Previous.ContainsKey($Id)) {
                [pscustomobject]@{ timestamp = (Get-Date).ToString('o'); event = 'JOIN'; name = $Current[$Id].name; accountName = $Current[$Id].accountName; userId = $Id } | Export-Csv -LiteralPath $EventsPath -Append -NoTypeInformation -Encoding UTF8
            }
        }
        foreach ($Id in $Previous.Keys) {
            if (-not $Current.ContainsKey($Id)) {
                [pscustomobject]@{ timestamp = (Get-Date).ToString('o'); event = 'LEAVE'; name = $Previous[$Id].name; accountName = $Previous[$Id].accountName; userId = $Id } | Export-Csv -LiteralPath $EventsPath -Append -NoTypeInformation -Encoding UTF8
            }
        }
        if ($Current.Count -ne $Previous.Count -or -not (Test-Path -LiteralPath $StatePath)) {
            Invoke-DiscordStatusSafe -Status Online -Detail 'Palworld and Unlim are running.' -PlayerCount $Current.Count
        }
        @($Players) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatePath -Encoding UTF8
        $Previous = $Current
        $PalworldFailureCount = 0
        if ($PalworldAlerted) {
            Invoke-DiscordNotificationSafe -Type ServiceRecovered -Message 'The Palworld server management connection has recovered.'
            $PalworldAlerted = $false
        }
    }
    catch {
        $PalworldFailureCount++
        Write-Warning "Player monitor poll failed: $($_.Exception.Message)"
        if ($PalworldFailureCount -ge 3 -and -not $PalworldAlerted) {
            Invoke-DiscordStatusSafe -Status Error -Detail 'Palworld health checks failed three times.'
            Invoke-DiscordNotificationSafe -Type ServiceError -Message 'The Palworld server failed three consecutive health checks. Administrator review is required.'
            $PalworldAlerted = $true
        }
    }
    Start-Sleep -Seconds ([Math]::Max(10, $Interval))
}
