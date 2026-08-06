$ErrorActionPreference = 'Stop'

function Get-PalOpsOperationHistory {
    param([string]$Path = (Join-Path $ProjectDir 'runtime\dashboard-history.json'), [int]$Limit = 20)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        $Items = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        return @($Items | Select-Object -First $Limit)
    }
    catch { return @() }
}

function Add-PalOpsOperationHistory {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$State, [Parameter(Mandatory)][string]$StartedAt, [Parameter(Mandatory)][string]$CompletedAt, [string]$Message = '', [string]$Target = '', [string]$Path = (Join-Path $ProjectDir 'runtime\dashboard-history.json'))
    $Mutex = [Threading.Mutex]::new($false, 'Local\PalOpsOperationHistory')
    $Acquired = $false
    try {
        $Acquired = $Mutex.WaitOne([TimeSpan]::FromSeconds(5))
        if (-not $Acquired) { throw 'Operation history is busy.' }
        $Entry = [pscustomobject]@{ name = $Name; target = $Target; state = $State; startedAt = $StartedAt; completedAt = $CompletedAt; message = $Message }
        $History = @(Get-PalOpsOperationHistory -Path $Path -Limit 20)
        $TemporaryPath = "$Path.$PID.tmp"
        @($Entry) + @($History) | Select-Object -First 20 | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $TemporaryPath -Encoding UTF8
        Move-Item -LiteralPath $TemporaryPath -Destination $Path -Force
    }
    finally {
        if ($Acquired) { $Mutex.ReleaseMutex() }
        $Mutex.Dispose()
    }
}

function Clear-PalOpsOperationHistory {
    param([string]$Path = (Join-Path $ProjectDir 'runtime\dashboard-history.json'))
    $Mutex = [Threading.Mutex]::new($false, 'Local\PalOpsOperationHistory')
    $Acquired = $false
    try {
        $Acquired = $Mutex.WaitOne([TimeSpan]::FromSeconds(5))
        if (-not $Acquired) { throw 'Operation history is busy.' }
        '[]' | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    finally {
        if ($Acquired) { $Mutex.ReleaseMutex() }
        $Mutex.Dispose()
    }
}

function Invoke-DockerCompose {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Arguments -join ' ')"
    }
}

function Wait-PalworldReady {
    param([int]$TimeoutSeconds = 180)
    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $Deadline) {
        $ContainerOutput = & docker compose ps --status running --quiet palworld-server
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to inspect the Palworld container during startup.'
        }
        $ContainerId = ($ContainerOutput | Out-String).Trim()
        if (-not $ContainerId) {
            throw 'The Palworld container stopped during startup.'
        }
        $RecentLogs = & docker compose logs --no-color --tail 200 palworld-server 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Failed to read Palworld startup logs.' }
        if ($RecentLogs -match 'Running Palworld dedicated server on') {
            return
        }
        Start-Sleep -Seconds 3
    }
    throw "Palworld did not become ready within $TimeoutSeconds seconds."
}

function Invoke-DiscordStatusSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Detail = '',
        [int]$PlayerCount = -1
    )
    try {
        & "$PSScriptRoot\discord-status.ps1" -Status $Status -Detail $Detail -PlayerCount $PlayerCount
    }
    catch {
        Write-Warning "Discord status update failed: $($_.Exception.Message)"
    }
}

function New-PalworldAdminConfig {
    $SecretPath = Join-Path $ProjectDir 'config\admin.env'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SecretPath) | Out-Null
    if (-not (Test-Path -LiteralPath $SecretPath)) {
        $Bytes = New-Object byte[] 32
        $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $Rng.GetBytes($Bytes) } finally { $Rng.Dispose() }
        $Password = [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'B')
        Set-Content -LiteralPath $SecretPath -Value "PALWORLD_ADMIN_PASSWORD=$Password" -Encoding Ascii
    }
    return $SecretPath
}

function Get-PalworldAdminPassword {
    $SecretPath = New-PalworldAdminConfig
    foreach ($Line in Get-Content -LiteralPath $SecretPath) {
        if ($Line -match '^PALWORLD_ADMIN_PASSWORD=(.+)$') { return $Matches[1].Trim() }
    }
    throw 'PALWORLD_ADMIN_PASSWORD is missing.'
}

function Enable-PalworldManagementApi {
    $ConfigPath = Join-Path $ProjectDir 'data\Saved\Config\LinuxServer\PalWorldSettings.ini'
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw 'PalWorldSettings.ini does not exist. Start the server once before enabling management.'
    }
    $Password = Get-PalworldAdminPassword
    $Text = Get-Content -LiteralPath $ConfigPath -Raw
    $Text = [regex]::Replace($Text, 'AdminPassword="[^"]*"', "AdminPassword=`"$Password`"")
    $Text = [regex]::Replace($Text, 'RESTAPIEnabled=(True|False)', 'RESTAPIEnabled=True', 'IgnoreCase')
    $Text = [regex]::Replace($Text, 'RESTAPIPort=\d+', 'RESTAPIPort=8212')
    Set-Content -LiteralPath $ConfigPath -Value $Text -Encoding UTF8
}

function Invoke-PalworldApi {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Get', 'Post')][string]$Method,
        [Parameter(Mandatory = $true)][Alias('Path')][string]$ApiPath,
        [object]$Body = $null
    )
    $Password = Get-PalworldAdminPassword
    $Port = Get-ProjectSetting -Name 'PALWORLD_REST_PORT' -Default '8212'
    $AuthBytes = [Text.Encoding]::ASCII.GetBytes("admin:$Password")
    $Headers = @{ Authorization = "Basic $([Convert]::ToBase64String($AuthBytes))" }
    $Parameters = @{ Method = $Method; Uri = "http://127.0.0.1:$Port/v1/api/$ApiPath"; Headers = $Headers; TimeoutSec = 10 }
    if ($null -ne $Body) {
        $Parameters.ContentType = 'application/json; charset=utf-8'
        $Parameters.Body = ($Body | ConvertTo-Json -Depth 5 -Compress)
    }
    return Invoke-RestMethod @Parameters
}

function Start-PlayerMonitor {
    $PidPath = Join-Path $ProjectDir 'runtime\player-monitor.pid'
    if (Test-Path -LiteralPath $PidPath) {
        $ExistingPid = (Get-Content -LiteralPath $PidPath -Raw).Trim()
        if ($ExistingPid -match '^\d+$' -and (Get-Process -Id ([int]$ExistingPid) -ErrorAction SilentlyContinue)) { return }
        Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
    }
    $LogPath = Join-Path $ProjectDir 'logs\player-monitor.log'
    $ErrorPath = Join-Path $ProjectDir 'logs\player-monitor-error.log'
    $Process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\player-monitor.ps1`"") -WindowStyle Hidden -RedirectStandardOutput $LogPath -RedirectStandardError $ErrorPath -PassThru
    Set-Content -LiteralPath $PidPath -Value $Process.Id -Encoding Ascii
}

function Stop-PlayerMonitor {
    $PidPath = Join-Path $ProjectDir 'runtime\player-monitor.pid'
    if (-not (Test-Path -LiteralPath $PidPath)) { return }
    $StoredPid = (Get-Content -LiteralPath $PidPath -Raw).Trim()
    if ($StoredPid -match '^\d+$') {
        $Process = Get-Process -Id ([int]$StoredPid) -ErrorAction SilentlyContinue
        if ($Process -and $Process.ProcessName -in @('powershell', 'pwsh')) { Stop-Process -Id $Process.Id -Force }
    }
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

function Invoke-DiscordConnectionSafe {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [string]$ConnectionKey = ''
    )
    try {
        & "$PSScriptRoot\discord-connection.ps1" -State $State -ConnectionKey $ConnectionKey
    }
    catch {
        Write-Warning "Discord connection information update failed: $($_.Exception.Message)"
    }
}

function Invoke-DiscordNotificationSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Message
    )
    try {
        & "$PSScriptRoot\discord-notify.ps1" -Type $Type -Message $Message
    }
    catch {
        Write-Warning "Discord notification failed: $($_.Exception.Message)"
    }
}

function Get-UnlimConnectionKey {
    $LogPath = Join-Path $ProjectDir 'logs\unlim-current.log'
    if (-not (Test-Path -LiteralPath $LogPath)) { return '' }
    $LogText = Get-Content -LiteralPath $LogPath -Raw -ErrorAction SilentlyContinue
    $Match = [regex]::Match($LogText, '(?i)zshareunlim-[a-z0-9]+')
    if ($Match.Success) { return $Match.Value }
    return ''
}

function Get-UnlimHostProcess {
    $PidPath = Join-Path $ProjectDir 'runtime\unlim.pid'
    if (Test-Path -LiteralPath $PidPath) {
        $StoredPid = (Get-Content -LiteralPath $PidPath -Raw).Trim()
        if ($StoredPid -match '^\d+$') {
            $Process = Get-Process -Id ([int]$StoredPid) -ErrorAction SilentlyContinue
            if ($Process -and $Process.ProcessName -eq 'unlim') { return $Process }
        }
    }

    $Candidate = Get-Process unlim -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1
    if ($Candidate) {
        Set-Content -LiteralPath $PidPath -Value $Candidate.Id -Encoding Ascii
        return $Candidate
    }
    return $null
}

function Test-UnlimHost {
    return $null -ne (Get-UnlimHostProcess)
}

function Get-ProjectSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = ''
    )
    $EnvPath = Join-Path $ProjectDir '.env'
    if (Test-Path -LiteralPath $EnvPath) {
        foreach ($Line in Get-Content -LiteralPath $EnvPath) {
            if ($Line -match "^$([regex]::Escape($Name))=(.*)$") {
                return $Matches[1].Trim()
            }
        }
    }
    return $Default
}

function Save-PalworldLogs {
    $LogsDir = Join-Path $ProjectDir 'logs'
    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogPath = Join-Path $LogsDir "palworld-$Timestamp.log"
    $Output = & docker compose logs --no-color --timestamps palworld-server 2>&1
    if ($LASTEXITCODE -eq 0) {
        $Output | Set-Content -LiteralPath $LogPath -Encoding UTF8
        Write-Host "Server log saved: $LogPath"
        return $LogPath
    }
    Write-Warning 'Could not save the Docker server log.'
    return $null
}

function New-PalworldBackup {
    param([string]$Label = 'palworld')

    $SavedPath = Join-Path $ProjectDir 'data\Saved'
    if (-not (Test-Path -LiteralPath $SavedPath)) {
        throw 'The Saved directory does not exist.'
    }

    $BackupsDir = Join-Path $ProjectDir 'backups'
    New-Item -ItemType Directory -Force -Path $BackupsDir | Out-Null
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $FinalPath = Join-Path $BackupsDir "$Label-$Timestamp.zip"
    $PartialPath = "$FinalPath.partial.zip"

    if (Test-Path -LiteralPath $PartialPath) {
        Remove-Item -LiteralPath $PartialPath -Force
    }

    try {
        Compress-Archive -Path $SavedPath -DestinationPath $PartialPath -CompressionLevel Fastest
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($PartialPath)
        try {
            if ($Archive.Entries.Count -eq 0) { throw 'Backup archive is empty.' }
            if (-not ($Archive.Entries | Where-Object { $_.FullName -match '^Saved[\\/]' })) {
                throw 'Backup archive does not contain the Saved directory.'
            }
        }
        finally {
            $Archive.Dispose()
        }
        Move-Item -LiteralPath $PartialPath -Destination $FinalPath
    }
    catch {
        if (Test-Path -LiteralPath $PartialPath) {
            Remove-Item -LiteralPath $PartialPath -Force
        }
        throw
    }

    $Retention = [int](Get-ProjectSetting -Name 'BACKUP_RETENTION' -Default '20')
    if ($Retention -gt 0) {
        $OldBackups = @(Get-ChildItem -LiteralPath $BackupsDir -Filter 'palworld-*.zip' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Retention)
        foreach ($OldBackup in $OldBackups) {
            Remove-Item -LiteralPath $OldBackup.FullName -Force
            Write-Host "Backup removed by count limit: $($OldBackup.Name)"
        }
    }

    $MaximumTotalGb = [double](Get-ProjectSetting -Name 'BACKUP_MAX_TOTAL_GB' -Default '10')
    $MinimumRetention = [int](Get-ProjectSetting -Name 'BACKUP_MIN_RETENTION' -Default '3')
    if ($MinimumRetention -lt 1) { $MinimumRetention = 1 }
    if ($Retention -gt 0 -and $MinimumRetention -gt $Retention) { $MinimumRetention = $Retention }
    if ($MaximumTotalGb -gt 0) {
        $MaximumBytes = $MaximumTotalGb * 1GB
        $BackupsByAge = @(Get-ChildItem -LiteralPath $BackupsDir -Filter 'palworld-*.zip' -File | Sort-Object LastWriteTime)
        $TotalBytes = ($BackupsByAge | Measure-Object -Property Length -Sum).Sum
        while ($TotalBytes -gt $MaximumBytes -and $BackupsByAge.Count -gt $MinimumRetention) {
            $Oldest = $BackupsByAge[0]
            $OldestSize = $Oldest.Length
            Remove-Item -LiteralPath $Oldest.FullName -Force
            Write-Host "Backup removed by size limit: $($Oldest.Name)"
            $TotalBytes -= $OldestSize
            $BackupsByAge = @($BackupsByAge | Select-Object -Skip 1)
        }
        if ($TotalBytes -gt $MaximumBytes) {
            Write-Warning "Backup storage still exceeds $MaximumTotalGb GB because the minimum retention is $MinimumRetention."
        }
        Write-Host ('Backup storage: {0:N2} GB / {1:N2} GB ({2} files)' -f ($TotalBytes / 1GB), $MaximumTotalGb, $BackupsByAge.Count)
    }

    Write-Host "Backup created and verified: $FinalPath"
    return $FinalPath
}

function Start-UnlimHost {
    $UnlimCommand = Get-Command unlim -ErrorAction SilentlyContinue
    if (-not $UnlimCommand) {
        throw 'Unlim CLI was not found.'
    }

    $PidPath = Join-Path $ProjectDir 'runtime\unlim.pid'
    if (Test-Path -LiteralPath $PidPath) {
        $ExistingPid = (Get-Content -LiteralPath $PidPath -Raw).Trim()
        if ($ExistingPid -match '^\d+$') {
            $ExistingProcess = Get-Process -Id ([int]$ExistingPid) -ErrorAction SilentlyContinue
            if ($ExistingProcess -and $ExistingProcess.ProcessName -eq 'unlim') {
                Write-Host "Unlim is already running (PID $ExistingPid)."
                return [int]$ExistingPid
            }
        }
        Remove-Item -LiteralPath $PidPath -Force
    }

    $OtherUnlim = @(Get-Process unlim -ErrorAction SilentlyContinue)
    if ($OtherUnlim.Count -gt 0) {
        throw 'Another Unlim process is running. Close the Unlim app or CLI before starting this project.'
    }
    $ProcessIdsBeforeStart = @($OtherUnlim | ForEach-Object { $_.Id })

    $LogsDir = Join-Path $ProjectDir 'logs'
    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    $StdoutPath = Join-Path $LogsDir 'unlim-current.log'
    $StderrPath = Join-Path $LogsDir 'unlim-current-error.log'
    $Port = Get-ProjectSetting -Name 'PALWORLD_PORT' -Default '8211'
    $MaxPlayers = Get-ProjectSetting -Name 'MAX_PLAYERS' -Default '8'
    $Arguments = @('--now', "$Port/udp", '--no-tui', '--log', '--max-peers', $MaxPlayers)

    $Process = Start-Process -FilePath $UnlimCommand.Source -ArgumentList $Arguments -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $PidPath -Value $Process.Id -Encoding Ascii

    $Deadline = (Get-Date).AddSeconds(15)
    $KeyMatch = $null
    while ((Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 500
        $Process.Refresh()
        if ($Process.HasExited) {
            $Replacement = @(Get-Process unlim -ErrorAction SilentlyContinue | Where-Object { $ProcessIdsBeforeStart -notcontains $_.Id } | Sort-Object StartTime -Descending | Select-Object -First 1)
            if ($Replacement.Count -gt 0) {
                $Process = $Replacement[0]
                Set-Content -LiteralPath $PidPath -Value $Process.Id -Encoding Ascii
            }
            else {
                Start-Sleep -Seconds 1
                $Replacement = @(Get-Process unlim -ErrorAction SilentlyContinue | Where-Object { $ProcessIdsBeforeStart -notcontains $_.Id } | Sort-Object StartTime -Descending | Select-Object -First 1)
                if ($Replacement.Count -gt 0) {
                    $Process = $Replacement[0]
                    Set-Content -LiteralPath $PidPath -Value $Process.Id -Encoding Ascii
                }
                else {
                    $ErrorText = Get-Content -LiteralPath $StderrPath -Raw -ErrorAction SilentlyContinue
                    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
                    throw "Unlim exited during startup. $ErrorText"
                }
            }
        }
        $CurrentLog = ((Get-Content -LiteralPath $StdoutPath -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $StderrPath -Raw -ErrorAction SilentlyContinue))
        $KeyMatch = [regex]::Match($CurrentLog, '(?i)zshareunlim-[a-z0-9]+')
        if ($KeyMatch.Success) { break }
    }

    $Process.Refresh()
    if ($Process.HasExited) {
        Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
        throw 'Unlim exited during startup.'
    }
    $CombinedLog = ((Get-Content -LiteralPath $StdoutPath -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $StderrPath -Raw -ErrorAction SilentlyContinue))
    $KeyMatch = [regex]::Match($CombinedLog, '(?i)zshareunlim-[a-z0-9]+')
    Write-Host "Unlim started (PID $($Process.Id))."
    if ($KeyMatch.Success) {
        Write-Host "Unlim connection key: $($KeyMatch.Value)"
    }
    else {
        Write-Host "Unlim log: $StdoutPath"
    }
    return $Process.Id
}

function Stop-UnlimHost {
    $PidPath = Join-Path $ProjectDir 'runtime\unlim.pid'
    if (-not (Test-Path -LiteralPath $PidPath)) { return }

    $StoredPid = (Get-Content -LiteralPath $PidPath -Raw).Trim()
    if ($StoredPid -match '^\d+$') {
        $Process = Get-Process -Id ([int]$StoredPid) -ErrorAction SilentlyContinue
        if ($Process -and $Process.ProcessName -eq 'unlim') {
            Stop-Process -Id $Process.Id
            try { Wait-Process -Id $Process.Id -Timeout 10 -ErrorAction Stop } catch { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
            Write-Host 'Unlim stopped.'
        }
    }
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}
