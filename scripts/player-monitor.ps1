$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

$StatePath = Join-Path $ProjectDir 'runtime\player-monitor-state.json'
$EventsPath = Join-Path $ProjectDir 'logs\player-events.csv'
$AccessPath = Join-Path $ProjectDir 'logs\player-access.json'
$Interval = [int](Get-ProjectSetting -Name 'MONITOR_INTERVAL_SECONDS' -Default '30')
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir 'logs') | Out-Null
if (-not (Test-Path -LiteralPath $EventsPath)) { 'timestamp,event,name,accountName,userId' | Set-Content -LiteralPath $EventsPath -Encoding UTF8 }

function Get-PlayerIdentityKey {
    param($Player)
    if (-not [string]::IsNullOrWhiteSpace([string]$Player.userId)) { return "user:$([string]$Player.userId)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$Player.accountName)) { return "account:$([string]$Player.accountName)" }
    return "name:$([string]$Player.name)"
}

$Access = @{}
if (Test-Path -LiteralPath $AccessPath) {
    try {
        $PersistedPlayers = Get-Content -LiteralPath $AccessPath -Raw | ConvertFrom-Json
        foreach ($Player in $PersistedPlayers) {
            $Key = [string]$Player.key
            if ([string]::IsNullOrWhiteSpace($Key)) { $Key = Get-PlayerIdentityKey $Player }
            # Normalize persisted records so data written by an older PalOps version
            # remains writable when new fields are introduced.
            $Access[$Key] = [pscustomobject]@{
                key = $Key
                name = [string]$Player.name
                accountName = [string]$Player.accountName
                userId = [string]$Player.userId
                firstSeenAt = [string]$Player.firstSeenAt
                lastSeenAt = [string]$Player.lastSeenAt
                joinCount = if ($null -eq $Player.joinCount) { 0 } else { [int]$Player.joinCount }
                online = $false
            }
        }
    }
    catch { Write-Warning "Player access history could not be loaded: $($_.Exception.Message)" }
}
if ($Access.Count -eq 0 -and (Test-Path -LiteralPath $EventsPath)) {
    try {
        foreach ($Event in @(Import-Csv -LiteralPath $EventsPath)) {
            $Key = Get-PlayerIdentityKey $Event
            if (-not $Access.ContainsKey($Key)) {
                $Access[$Key] = [pscustomobject]@{ key = $Key; name = [string]$Event.name; accountName = [string]$Event.accountName; userId = [string]$Event.userId; firstSeenAt = [string]$Event.timestamp; lastSeenAt = [string]$Event.timestamp; joinCount = 0; online = $false }
            }
            $Record = $Access[$Key]
            if ([string]$Event.timestamp -lt [string]$Record.firstSeenAt) { $Record.firstSeenAt = [string]$Event.timestamp }
            if ([string]$Event.timestamp -gt [string]$Record.lastSeenAt) { $Record.lastSeenAt = [string]$Event.timestamp }
            if ([string]$Event.event -eq 'JOIN') { $Record.joinCount = [int]$Record.joinCount + 1 }
        }
    }
    catch { Write-Warning "Player events could not seed access history: $($_.Exception.Message)" }
}

function Save-PlayerAccessDirectory {
    $TemporaryPath = "$AccessPath.tmp"
    $Records = @($Access.Values | Sort-Object @{ Expression = { [string]$_.lastSeenAt }; Descending = $true })
    ConvertTo-Json -InputObject $Records -Depth 5 | Set-Content -LiteralPath $TemporaryPath -Encoding UTF8
    Move-Item -LiteralPath $TemporaryPath -Destination $AccessPath -Force
}

$Previous = @{}
if (Test-Path -LiteralPath $StatePath) {
    try {
        $SavedPlayers = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
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

    $AutomaticRecoveryEnabled = $true
    try {
        $RecoveryTask = Get-ScheduledTask -TaskName 'Palworld-Monitor-Watchdog' -ErrorAction SilentlyContinue
        if ($RecoveryTask) { $AutomaticRecoveryEnabled = [bool]$RecoveryTask.Settings.Enabled }
    }
    catch { Write-Warning "Automatic recovery setting could not be read: $($_.Exception.Message)" }

    if ($AutomaticRecoveryEnabled -and -not (Test-UnlimHost)) {
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
        $ObservedAt = (Get-Date).ToString('o')
        foreach ($Record in $Access.Values) { $Record.online = $false }
        foreach ($Player in $Players) {
            $Key = Get-PlayerIdentityKey $Player
            if (-not $Access.ContainsKey($Key)) {
                $Access[$Key] = [pscustomobject]@{ key = $Key; name = [string]$Player.name; accountName = [string]$Player.accountName; userId = [string]$Player.userId; firstSeenAt = $ObservedAt; lastSeenAt = $ObservedAt; joinCount = 0; online = $true }
            }
            $Record = $Access[$Key]
            $Record.name = [string]$Player.name
            $Record.accountName = [string]$Player.accountName
            $Record.userId = [string]$Player.userId
            $Record.lastSeenAt = $ObservedAt
            $Record.online = $true
            if (-not $Previous.ContainsKey($Player.userId)) { $Record.joinCount = [int]$Record.joinCount + 1 }
        }
        foreach ($Id in $Previous.Keys) {
            if (-not $Current.ContainsKey($Id)) {
                $Key = Get-PlayerIdentityKey $Previous[$Id]
                if ($Access.ContainsKey($Key)) { $Access[$Key].lastSeenAt = $ObservedAt; $Access[$Key].online = $false }
            }
        }
        Save-PlayerAccessDirectory
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
