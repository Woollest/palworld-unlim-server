param(
    [int]$Port = 0,
    [switch]$NoBrowser,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$PSScriptRoot\common.ps1"
if ($Port -le 0) { $Port = [int](Get-ProjectSetting -Name 'DASHBOARD_PORT' -Default '8765') }

$WebRoot = Join-Path $ProjectDir 'web'
$RuntimeDir = Join-Path $ProjectDir 'runtime'
$ActionStatePath = Join-Path $RuntimeDir 'dashboard-action.json'
$ActionHistoryPath = Join-Path $RuntimeDir 'dashboard-history.json'
$IncidentPath = Join-Path $RuntimeDir 'incidents.json'
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

function Get-Incidents { if (-not (Test-Path $IncidentPath)){return @()}; try{return @(Get-Content $IncidentPath -Raw|ConvertFrom-Json|Select-Object -First 100)}catch{return @()} }
function Add-Incident { param($Body); $Title=([string]$Body.title).Trim();$Detail=([string]$Body.detail).Trim();if($Title.Length-lt 2-or$Title.Length-gt 100-or$Detail.Length-gt 1000){throw 'Title or detail length is invalid.'};if([string]$Body.severity-notin @('info','warning','critical')){throw 'Invalid severity.'};$Entry=[pscustomobject]@{id=[guid]::NewGuid().ToString('N');createdAt=(Get-Date).ToString('o');severity=[string]$Body.severity;title=$Title;detail=$Detail;status='open'};@($Entry)+@(Get-Incidents)|Select-Object -First 100|ConvertTo-Json -Depth 4|Set-Content $IncidentPath -Encoding UTF8;return $Entry }
function Get-MigrationInventory { @((Get-ChildItem (Join-Path $ProjectDir 'exports') -Filter 'palops-migration-*.zip' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 10)|ForEach-Object{[pscustomobject]@{name=$_.Name;createdAt=$_.LastWriteTime.ToString('o');sizeMb=[math]::Round($_.Length/1MB,1)}}) }

function Write-HttpResponse {
    param($Context, [int]$StatusCode, [string]$ContentType, [byte[]]$Body)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentLength64 = $Body.Length
    $Context.Response.Headers['Cache-Control'] = 'no-store'
    $Context.Response.OutputStream.Write($Body, 0, $Body.Length)
    $Context.Response.Close()
}

function Write-JsonResponse {
    param($Context, [int]$StatusCode, $Value)
    $Json = $Value | ConvertTo-Json -Depth 8 -Compress
    Write-HttpResponse -Context $Context -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($Json))
}

function Get-ActionState {
    if (-not (Test-Path -LiteralPath $ActionStatePath)) { return $null }
    try {
        $State = Get-Content -LiteralPath $ActionStatePath -Raw | ConvertFrom-Json
        if ($State.PSObject.Properties.Name -notcontains 'state') {
            $LegacyProcess = Get-Process -Id ([int]$State.pid) -ErrorAction SilentlyContinue
            if ($LegacyProcess) {
                $State | Add-Member -NotePropertyName state -NotePropertyValue 'running' -Force
            } else {
                Remove-Item -LiteralPath $ActionStatePath -Force -ErrorAction SilentlyContinue
                return $null
            }
        }
        if ($State.state -eq 'running') {
            $Process = Get-Process -Id ([int]$State.pid) -ErrorAction SilentlyContinue
            if (-not $Process) {
                $State.state = 'failed'
                $State | Add-Member -NotePropertyName completedAt -NotePropertyValue (Get-Date).ToString('o') -Force
                $State | Add-Member -NotePropertyName message -NotePropertyValue 'The operation ended unexpectedly.' -Force
            }
        }
        return $State
    }
    catch {
        Remove-Item -LiteralPath $ActionStatePath -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Get-ActionHistory {
    if (-not (Test-Path -LiteralPath $ActionHistoryPath)) { return @() }
    try { return @(Get-Content -LiteralPath $ActionHistoryPath -Raw | ConvertFrom-Json | Select-Object -First 8) }
    catch { return @() }
}

function Get-UpdateStatus {
    $StatusPath = Join-Path $ProjectDir 'runtime\update-status.json'
    $CurrentImage = Get-ProjectSetting -Name 'PALWORLD_IMAGE'
    $CurrentTag = if ($CurrentImage) { ($CurrentImage -split ':')[-1] } else { '' }
    if (-not (Test-Path -LiteralPath $StatusPath)) {
        return [pscustomobject]@{ checkedAt = $null; currentTag = $CurrentTag; latestTag = $null; available = $false; known = $false }
    }
    try {
        $Status = Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json
        return [pscustomobject]@{ checkedAt = $Status.checkedAt; currentTag = $Status.currentTag; latestTag = $Status.latestTag; available = [bool]$Status.available; known = $true }
    }
    catch { return [pscustomobject]@{ checkedAt = $null; currentTag = $CurrentTag; latestTag = $null; available = $false; known = $false } }
}

function Get-BackupInventory {
    $BackupsDir = Join-Path $ProjectDir 'backups'
    $VerifiedPath = Join-Path $ProjectDir 'runtime\backup-verified'
    $VerifiedName = if (Test-Path -LiteralPath $VerifiedPath) { (Get-Content -LiteralPath $VerifiedPath -Raw).Trim() } else { '' }
    $Files = @(Get-ChildItem -LiteralPath $BackupsDir -Filter 'palworld-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 20)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    return @($Files | ForEach-Object {
        $StructurallyValid = $false
        try {
            $Archive = [IO.Compression.ZipFile]::OpenRead($_.FullName)
            try {
                $Names = @($Archive.Entries.FullName)
                $StructurallyValid = [bool](($Names -match '^Saved[\\/]SaveGames[\\/].+[\\/]Level\.sav$') -and ($Names -match '^Saved[\\/]SaveGames[\\/].+[\\/]LevelMeta\.sav$'))
            } finally { $Archive.Dispose() }
        } catch {}
        [pscustomobject]@{ name = $_.Name; createdAt = $_.LastWriteTime.ToString('o'); sizeMb = [math]::Round($_.Length / 1MB, 1); valid = $StructurallyValid; fullyVerified = $_.Name -eq $VerifiedName }
    })
}

function Test-BackupName {
    param([string]$Name)
    return [bool]($Name -match '^palworld-\d{8}-\d{6}\.zip$' -and [IO.Path]::GetFileName($Name) -eq $Name)
}

function Get-MaintenanceSchedules {
    $SchedulesPath = Join-Path $ProjectDir 'runtime\maintenance-schedules.json'
    if (-not (Test-Path -LiteralPath $SchedulesPath)) { return @() }
    try { return @(Get-Content -LiteralPath $SchedulesPath -Raw | ConvertFrom-Json | Select-Object -First 20) } catch { return @() }
}

function Get-SettingsSchema {
    return @(
        [pscustomobject]@{ key = 'ExpRate'; group = 'gameplay'; type = 'number'; min = 0.1; max = 20; step = 0.1 },
        [pscustomobject]@{ key = 'PalCaptureRate'; group = 'gameplay'; type = 'number'; min = 0.1; max = 20; step = 0.1 },
        [pscustomobject]@{ key = 'PalSpawnNumRate'; group = 'gameplay'; type = 'number'; min = 0.5; max = 3; step = 0.1 },
        [pscustomobject]@{ key = 'CollectionDropRate'; group = 'gameplay'; type = 'number'; min = 0.1; max = 20; step = 0.1 },
        [pscustomobject]@{ key = 'EnemyDropItemRate'; group = 'gameplay'; type = 'number'; min = 0.1; max = 20; step = 0.1 },
        [pscustomobject]@{ key = 'WorkSpeedRate'; group = 'gameplay'; type = 'number'; min = 0.1; max = 10; step = 0.1 },
        [pscustomobject]@{ key = 'DayTimeSpeedRate'; group = 'world'; type = 'number'; min = 0.1; max = 5; step = 0.05 },
        [pscustomobject]@{ key = 'NightTimeSpeedRate'; group = 'world'; type = 'number'; min = 0.1; max = 5; step = 0.05 },
        [pscustomobject]@{ key = 'PalEggDefaultHatchingTime'; group = 'world'; type = 'number'; min = 0; max = 240; step = 0.016667 },
        [pscustomobject]@{ key = 'CollectionObjectRespawnSpeedRate'; group = 'world'; type = 'number'; min = 0.1; max = 10; step = 0.1 },
        [pscustomobject]@{ key = 'SupplyDropSpan'; group = 'world'; type = 'integer'; min = 10; max = 86400; step = 10 },
        [pscustomobject]@{ key = 'AutoSaveSpan'; group = 'performance'; type = 'integer'; min = 30; max = 3600; step = 30 },
        [pscustomobject]@{ key = 'DropItemMaxNum'; group = 'performance'; type = 'integer'; min = 100; max = 10000; step = 100 },
        [pscustomobject]@{ key = 'PhysicsActiveDropItemMaxNum'; group = 'performance'; type = 'integer'; min = 0; max = 3000; step = 50 },
        [pscustomobject]@{ key = 'DropItemAliveMaxHours'; group = 'performance'; type = 'number'; min = 0.1; max = 24; step = 0.1 },
        [pscustomobject]@{ key = 'ItemContainerForceMarkDirtyInterval'; group = 'performance'; type = 'number'; min = 0.1; max = 60; step = 0.1 },
        [pscustomobject]@{ key = 'ServerPlayerMaxNum'; group = 'server'; type = 'integer'; min = 1; max = 32; step = 1 }
    )
}

function Get-EditableWorldSettings {
    $SettingsPath = Join-Path $ProjectDir 'data\Saved\Config\LinuxServer\PalWorldSettings.ini'
    if (-not (Test-Path -LiteralPath $SettingsPath)) { throw 'PalWorldSettings.ini does not exist.' }
    $Text = Get-Content -LiteralPath $SettingsPath -Raw
    $Values = [ordered]@{}
    foreach ($Field in Get-SettingsSchema) {
        $Match = [regex]::Match($Text, "(?:[(,])$([regex]::Escape($Field.key))=([^,)]*)")
        if (-not $Match.Success) { continue }
        if ($Field.type -eq 'integer') { $Values[$Field.key] = [int]([double]::Parse($Match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)) }
        else { $Values[$Field.key] = [double]::Parse($Match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) }
    }
    return [pscustomobject]@{ schema = @(Get-SettingsSchema); values = $Values; restartRequired = Test-Path -LiteralPath (Join-Path $ProjectDir 'runtime\settings-restart-required') }
}

function Set-EditableWorldSettings {
    param($Submitted)
    if ($null -eq $Submitted) { throw 'Settings are required.' }
    $Schema = @(Get-SettingsSchema)
    $Allowed = @{}; foreach ($Field in $Schema) { $Allowed[$Field.key] = $Field }
    $Properties = @($Submitted.PSObject.Properties)
    if ($Properties.Count -eq 0 -or $Properties.Count -gt $Schema.Count) { throw 'The settings payload is empty or too large.' }
    $SettingsPath = Join-Path $ProjectDir 'data\Saved\Config\LinuxServer\PalWorldSettings.ini'
    if (-not (Test-Path -LiteralPath $SettingsPath)) { throw 'PalWorldSettings.ini does not exist.' }
    $Original = Get-Content -LiteralPath $SettingsPath -Raw
    $Updated = $Original
    $Changes = [System.Collections.Generic.List[object]]::new()
    foreach ($Property in $Properties) {
        if (-not $Allowed.ContainsKey($Property.Name)) { throw "Unsupported setting: $($Property.Name)" }
        $Field = $Allowed[$Property.Name]
        $Number = 0.0
        if (-not [double]::TryParse([string]$Property.Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$Number)) { throw "Invalid value for $($Property.Name)." }
        if ($Number -lt $Field.min -or $Number -gt $Field.max) { throw "$($Property.Name) must be between $($Field.min) and $($Field.max)." }
        if ($Field.type -eq 'integer' -and $Number -ne [math]::Truncate($Number)) { throw "$($Property.Name) must be an integer." }
        $Formatted = if ($Field.type -eq 'integer') { ([int]$Number).ToString([Globalization.CultureInfo]::InvariantCulture) } else { $Number.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture) }
        $Pattern = "(?<prefix>[(,]$([regex]::Escape($Property.Name))=)[^,)]*"
        $Existing = [regex]::Match($Updated, $Pattern)
        if (-not $Existing.Success) { throw "Setting is missing from PalWorldSettings.ini: $($Property.Name)" }
        $OldValue = ($Existing.Value -split '=', 2)[1]
        if ([double]::Parse($OldValue, [Globalization.CultureInfo]::InvariantCulture) -ne $Number) {
            $Updated = [regex]::Replace($Updated, $Pattern, "`${prefix}$Formatted", 1)
            $Changes.Add([pscustomobject]@{ key = $Property.Name; before = $OldValue; after = $Formatted })
        }
    }
    if ($Changes.Count -gt 0) {
        $SnapshotDir = Join-Path $ProjectDir 'recovery\settings'
        New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
        $SnapshotPath = Join-Path $SnapshotDir ("PalWorldSettings-" + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.ini')
        Copy-Item -LiteralPath $SettingsPath -Destination $SnapshotPath
        $TemporaryPath = "$SettingsPath.tmp"
        Set-Content -LiteralPath $TemporaryPath -Value $Updated -Encoding UTF8
        Move-Item -LiteralPath $TemporaryPath -Destination $SettingsPath -Force
        Set-Content -LiteralPath (Join-Path $ProjectDir 'runtime\settings-restart-required') -Value (Get-Date).ToString('o') -Encoding Ascii
    }
    return [pscustomobject]@{ changes = @($Changes); restartRequired = $Changes.Count -gt 0 }
}

function Get-HealthTrend {
    $MetricsPath = Join-Path $ProjectDir 'logs\health-metrics.csv'
    if (-not (Test-Path -LiteralPath $MetricsPath)) { return [pscustomobject]@{ points = @(); summary = $null } }
    try {
        $Since = (Get-Date).AddHours(-24)
        $Rows = @(Import-Csv -LiteralPath $MetricsPath | Where-Object {
            try { [datetime]$_.timestamp -ge $Since } catch { $false }
        })
        if ($Rows.Count -eq 0) { return [pscustomobject]@{ points = @(); summary = $null } }
        $MaximumPoints = 180
        $Step = [math]::Max(1, [math]::Ceiling($Rows.Count / $MaximumPoints))
        $Points = for ($Index = 0; $Index -lt $Rows.Count; $Index += $Step) {
            $Row = $Rows[$Index]
            [pscustomobject]@{
                timestamp = ([datetime]$Row.timestamp).ToString('o')
                online = $Row.server_online -eq 'True'
                cpu = if ($Row.cpu_percent -ne '') { [math]::Round([double]$Row.cpu_percent, 1) } else { $null }
                memory = if ($Row.memory_percent -ne '') { [math]::Round([double]$Row.memory_percent, 1) } else { $null }
                fps = if ($Row.server_fps -ne '') { [math]::Round([double]$Row.server_fps, 1) } else { $null }
                players = if ($Row.players -ne '') { [int]$Row.players } else { $null }
            }
        }
        $OnlineRows = @($Rows | Where-Object { $_.server_online -eq 'True' })
        $Summary = if ($OnlineRows.Count) {
            [pscustomobject]@{
                samples = $Rows.Count
                availability = [math]::Round(($OnlineRows.Count / $Rows.Count) * 100, 1)
                averageCpu = [math]::Round((($OnlineRows | Where-Object cpu_percent -ne '' | Measure-Object cpu_percent -Average).Average), 1)
                peakMemory = [math]::Round((($OnlineRows | Where-Object memory_percent -ne '' | Measure-Object memory_percent -Maximum).Maximum), 1)
            }
        } else { [pscustomobject]@{ samples = $Rows.Count; availability = 0; averageCpu = $null; peakMemory = $null } }
        return [pscustomobject]@{ points = @($Points); summary = $Summary }
    }
    catch { return [pscustomobject]@{ points = @(); summary = $null } }
}

function Get-OperationalInsights {
    param(
        [bool]$ServerRunning,
        [bool]$UnlimRunning,
        $Disk,
        $LatestBackup,
        $Health
    )
    $Items = [System.Collections.Generic.List[object]]::new()
    $DiskThreshold = [double](Get-ProjectSetting -Name 'DISK_WARNING_FREE_GB' -Default '20')
    if ($Disk -and ($Disk.Free / 1GB) -lt $DiskThreshold) {
        $Items.Add([pscustomobject]@{ severity = 'warning'; code = 'disk-low'; value = [math]::Round($Disk.Free / 1GB, 1); title = 'Disk space is low'; detail = 'Review stored backups.' })
    }

    $BackupMaximumAge = [double](Get-ProjectSetting -Name 'HEALTH_BACKUP_MAX_AGE_HOURS' -Default '12')
    if (-not $LatestBackup) {
        $Items.Add([pscustomobject]@{ severity = 'warning'; code = 'backup-missing'; title = 'No backup exists'; detail = 'Create the first backup.' })
    } elseif (((Get-Date) - $LatestBackup.LastWriteTime).TotalHours -gt $BackupMaximumAge) {
        $Items.Add([pscustomobject]@{ severity = 'warning'; code = 'backup-stale'; value = [math]::Floor(((Get-Date) - $LatestBackup.LastWriteTime).TotalHours); title = 'Backup is stale'; detail = 'Create a fresh backup.' })
    }

    if ($ServerRunning -and -not $UnlimRunning) {
        $Items.Add([pscustomobject]@{ severity = 'critical'; code = 'unlim-offline'; title = 'Unlim is offline'; detail = 'External connections may be unavailable.' })
    }

    $Points = @($Health.points | Where-Object online)
    if ($ServerRunning -and $Points.Count) {
        $Latest = $Points[-1]
        $CpuThreshold = [double](Get-ProjectSetting -Name 'HEALTH_CPU_WARNING_PERCENT' -Default '85')
        $RecentCpu = @($Points | Select-Object -Last 3 | Where-Object { $null -ne $_.cpu })
        if ($RecentCpu.Count -ge 3 -and (($RecentCpu | Measure-Object cpu -Average).Average) -ge $CpuThreshold) {
            $Items.Add([pscustomobject]@{ severity = 'warning'; code = 'cpu-high'; value = [math]::Round((($RecentCpu | Measure-Object cpu -Average).Average), 1); title = 'CPU usage is high'; detail = 'Recent average exceeded the threshold.' })
        }
        $MemoryThreshold = [double](Get-ProjectSetting -Name 'HEALTH_MEMORY_WARNING_PERCENT' -Default '85')
        if ($null -ne $Latest.memory -and $Latest.memory -ge $MemoryThreshold) {
            $Items.Add([pscustomobject]@{ severity = 'warning'; code = 'memory-high'; value = $Latest.memory; title = 'Memory usage is high'; detail = 'Current usage exceeded the threshold.' })
        }
        $FpsThreshold = [double](Get-ProjectSetting -Name 'HEALTH_FPS_WARNING' -Default '45')
        if ($null -ne $Latest.fps -and $Latest.fps -lt $FpsThreshold) {
            $Items.Add([pscustomobject]@{ severity = 'warning'; code = 'fps-low'; value = $Latest.fps; title = 'Server FPS is low'; detail = 'Current FPS is below the threshold.' })
        }
    }

    $State = if (-not $ServerRunning) { 'stopped' } elseif (@($Items | Where-Object severity -eq 'critical').Count) { 'critical' } elseif ($Items.Count) { 'warning' } else { 'healthy' }
    return [pscustomobject]@{ state = $State; items = @($Items) }
}

function Get-DashboardStatus {
    $ContainerRunning = $false
    $ContainerStatus = 'unavailable'
    try {
        $Output = & docker compose ps --format json palworld-server 2>$null
        if ($LASTEXITCODE -eq 0 -and $Output) {
            $Info = $Output | ConvertFrom-Json
            $ContainerRunning = @($Info | Where-Object State -eq 'running').Count -gt 0
            $ContainerStatus = if ($ContainerRunning) { 'online' } else { 'offline' }
        }
    } catch {}

    $Players = @()
    $Metrics = $null
    if ($ContainerRunning) {
        try { $Players = @((Invoke-PalworldApi -Method Get -Path 'players').players) } catch {}
        try { $Metrics = Invoke-PalworldApi -Method Get -Path 'metrics' } catch {}
    }

    $LatestBackup = Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'backups') -Filter '*.zip' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $Disk = Get-PSDrive -Name ([IO.Path]::GetPathRoot($ProjectDir).TrimEnd('\').TrimEnd(':')) -ErrorAction SilentlyContinue
    $UnlimRunning = Test-UnlimHost
    $Health = Get-HealthTrend
    $Insights = Get-OperationalInsights -ServerRunning $ContainerRunning -UnlimRunning $UnlimRunning -Disk $Disk -LatestBackup $LatestBackup -Health $Health

    [pscustomobject]@{
        generatedAt = (Get-Date).ToString('o')
        server = [pscustomobject]@{
            status = $ContainerStatus
            players = $Players.Count
            maxPlayers = [int](Get-ProjectSetting -Name 'MAX_PLAYERS' -Default '8')
            playerNames = @($Players | ForEach-Object { $_.name })
            version = if ($Metrics) { $Metrics.version } else { $null }
            uptimeSeconds = if ($Metrics) { $Metrics.uptime } else { $null }
            fps = if ($Metrics) { $Metrics.serverfps } else { $null }
            frameTimeMs = if ($Metrics) { $Metrics.frametime } else { $null }
        }
        unlim = [pscustomobject]@{
            status = if ($UnlimRunning) { 'online' } else { 'offline' }
            connectionKeyAvailable = [bool](Get-UnlimConnectionKey)
        }
        backup = if ($LatestBackup) {
            [pscustomobject]@{ name = $LatestBackup.Name; createdAt = $LatestBackup.LastWriteTime.ToString('o'); sizeMb = [math]::Round($LatestBackup.Length / 1MB, 1) }
        } else { $null }
        disk = if ($Disk) { [pscustomobject]@{ freeGb = [math]::Round($Disk.Free / 1GB, 1) } } else { $null }
        action = Get-ActionState
        history = @(Get-ActionHistory)
        health = $Health
        insights = $Insights
        update = Get-UpdateStatus
    }
}

function Start-DashboardAction {
    param(
        [ValidateSet('start', 'restart', 'shutdown', 'backup', 'check-update', 'update', 'restore', 'migration-export', 'diagnostics')][string]$Name,
        [string]$Target = ''
    )
    $CurrentAction = Get-ActionState
    if ($CurrentAction -and $CurrentAction.state -eq 'running') { throw 'Another server operation is already running.' }
    $LogPath = Join-Path $ProjectDir "logs\dashboard-$Name.log"
    $ErrorPath = Join-Path $ProjectDir "logs\dashboard-$Name-error.log"
    $Executable = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    $RunnerArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\dashboard-action.ps1`"", '-Action', $Name)
    if ($Target) { $RunnerArguments += @('-Target', $Target) }
    $Process = Start-Process -FilePath $Executable -ArgumentList $RunnerArguments -WorkingDirectory $ProjectDir -WindowStyle Hidden -RedirectStandardOutput $LogPath -RedirectStandardError $ErrorPath -PassThru
    [pscustomobject]@{ name = $Name; target = $Target; state = 'running'; pid = $Process.Id; startedAt = (Get-Date).ToString('o') } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $ActionStatePath -Encoding UTF8
    return [pscustomobject]@{ accepted = $true; action = $Name }
}

if ($FunctionsOnly) { return }

$CreatedNew = $false
$DashboardMutex = [Threading.Mutex]::new($true, 'Local\PalOpsDashboard', [ref]$CreatedNew)
$Prefix = "http://127.0.0.1:$Port/"
if (-not $CreatedNew) {
    if (-not $NoBrowser) { Start-Process $Prefix | Out-Null }
    Write-Host 'PalOps is already running.'
    $DashboardMutex.Dispose()
    return
}
$DashboardPidPath = Join-Path $RuntimeDir 'dashboard.pid'
Set-Content -LiteralPath $DashboardPidPath -Value $PID -Encoding Ascii

$Listener = [Net.HttpListener]::new()
$Listener.Prefixes.Add($Prefix)
$Listener.Start()
Write-Host "PalOps dashboard: $Prefix" -ForegroundColor Cyan
Write-Host 'Press Ctrl+C to stop the dashboard. The game server will keep running.'
if (-not $NoBrowser) { Start-Process $Prefix | Out-Null }

try {
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        try {
            $Path = $Context.Request.Url.AbsolutePath
            if ($Context.Request.HttpMethod -eq 'GET' -and $Path -eq '/api/status') {
                Write-JsonResponse -Context $Context -StatusCode 200 -Value (Get-DashboardStatus)
                continue
            }
            if ($Context.Request.HttpMethod -eq 'GET' -and $Path -eq '/api/backups') {
                Write-JsonResponse -Context $Context -StatusCode 200 -Value @{ backups = @(Get-BackupInventory) }
                continue
            }
            if ($Context.Request.HttpMethod -eq 'GET' -and $Path -eq '/api/maintenance') {
                Write-JsonResponse -Context $Context -StatusCode 200 -Value @{ schedules = @(Get-MaintenanceSchedules) }
                continue
            }
            if ($Context.Request.HttpMethod -eq 'GET' -and $Path -eq '/api/settings') {
                try { Write-JsonResponse -Context $Context -StatusCode 200 -Value (Get-EditableWorldSettings) }
                catch { Write-JsonResponse -Context $Context -StatusCode 500 -Value @{ error = $_.Exception.Message } }
                continue
            }
            if ($Context.Request.HttpMethod -eq 'GET' -and $Path -eq '/api/incidents') { Write-JsonResponse $Context 200 @{incidents=@(Get-Incidents)}; continue }
            if ($Context.Request.HttpMethod -eq 'POST' -and $Path -eq '/api/incidents') {
                if ($Context.Request.Headers['Origin'] -ne "http://127.0.0.1:$Port" -or $Context.Request.ContentLength64 -lt 1 -or $Context.Request.ContentLength64 -gt 4096){Write-JsonResponse $Context 400 @{error='Invalid request.'};continue}
                $Reader=[IO.StreamReader]::new($Context.Request.InputStream,$Context.Request.ContentEncoding);try{$Body=$Reader.ReadToEnd()|ConvertFrom-Json}finally{$Reader.Dispose()};try{Write-JsonResponse $Context 201 (Add-Incident $Body)}catch{Write-JsonResponse $Context 400 @{error=$_.Exception.Message}};continue
            }
            if ($Context.Request.HttpMethod -eq 'GET' -and $Path -eq '/api/migrations') { Write-JsonResponse $Context 200 @{packages=@(Get-MigrationInventory)}; continue }
            if ($Context.Request.HttpMethod -eq 'GET' -and $Path -eq '/api/logs') { try{$Lines=@(& docker compose logs --no-color --tail 200 palworld-server 2>&1);Write-JsonResponse $Context 200 @{lines=@($Lines|ForEach-Object{[string]$_})}}catch{Write-JsonResponse $Context 500 @{error='Logs could not be read.'}};continue }
            if ($Context.Request.HttpMethod -eq 'POST' -and $Path -eq '/api/settings') {
                $ExpectedOrigin = "http://127.0.0.1:$Port"
                if ($Context.Request.Headers['Origin'] -ne $ExpectedOrigin) { Write-JsonResponse -Context $Context -StatusCode 403 -Value @{ error = 'Request origin was rejected.' }; continue }
                if ($Context.Request.ContentLength64 -lt 1 -or $Context.Request.ContentLength64 -gt 16384) { Write-JsonResponse -Context $Context -StatusCode 400 -Value @{ error = 'Invalid request body.' }; continue }
                $Reader = [IO.StreamReader]::new($Context.Request.InputStream, $Context.Request.ContentEncoding)
                try { $Body = $Reader.ReadToEnd() | ConvertFrom-Json } finally { $Reader.Dispose() }
                try { Write-JsonResponse -Context $Context -StatusCode 200 -Value (Set-EditableWorldSettings -Submitted $Body.settings) }
                catch { Write-JsonResponse -Context $Context -StatusCode 400 -Value @{ error = $_.Exception.Message } }
                continue
            }
            if ($Context.Request.HttpMethod -eq 'POST' -and $Path -eq '/api/maintenance/schedule') {
                $ExpectedOrigin = "http://127.0.0.1:$Port"
                if ($Context.Request.Headers['Origin'] -ne $ExpectedOrigin) { Write-JsonResponse -Context $Context -StatusCode 403 -Value @{ error = 'Request origin was rejected.' }; continue }
                if ($Context.Request.ContentLength64 -lt 1 -or $Context.Request.ContentLength64 -gt 2048) { Write-JsonResponse -Context $Context -StatusCode 400 -Value @{ error = 'Invalid request body.' }; continue }
                $Reader = [IO.StreamReader]::new($Context.Request.InputStream, $Context.Request.ContentEncoding)
                try { $Body = $Reader.ReadToEnd() | ConvertFrom-Json } finally { $Reader.Dispose() }
                if ([string]$Body.operation -notin @('restart', 'update', 'backup', 'shutdown')) { Write-JsonResponse -Context $Context -StatusCode 400 -Value @{ error = 'Invalid maintenance operation.' }; continue }
                try {
                    $Output = & "$PSScriptRoot\maintenance.ps1" -Mode Schedule -Operation ([string]$Body.operation) -RunAt ([string]$Body.runAt) -WarningMinutes ([int]$Body.warningMinutes)
                    $Schedule = ($Output | Out-String).Trim() | ConvertFrom-Json
                    Write-JsonResponse -Context $Context -StatusCode 201 -Value $Schedule
                } catch { Write-JsonResponse -Context $Context -StatusCode 400 -Value @{ error = $_.Exception.Message } }
                continue
            }
            if ($Context.Request.HttpMethod -eq 'POST' -and $Path -match '^/api/maintenance/([a-z0-9-]{8,40})/cancel$') {
                $ExpectedOrigin = "http://127.0.0.1:$Port"
                if ($Context.Request.Headers['Origin'] -ne $ExpectedOrigin) { Write-JsonResponse -Context $Context -StatusCode 403 -Value @{ error = 'Request origin was rejected.' }; continue }
                try {
                    $Output = & "$PSScriptRoot\maintenance.ps1" -Mode Cancel -Id $Matches[1]
                    $Schedule = ($Output | Out-String).Trim() | ConvertFrom-Json
                    Write-JsonResponse -Context $Context -StatusCode 200 -Value $Schedule
                } catch { Write-JsonResponse -Context $Context -StatusCode 409 -Value @{ error = $_.Exception.Message } }
                continue
            }
            if ($Context.Request.HttpMethod -eq 'POST' -and $Path -eq '/api/actions/restore') {
                $ExpectedOrigin = "http://127.0.0.1:$Port"
                if ($Context.Request.Headers['Origin'] -ne $ExpectedOrigin) { Write-JsonResponse -Context $Context -StatusCode 403 -Value @{ error = 'Request origin was rejected.' }; continue }
                if ($Context.Request.ContentLength64 -lt 1 -or $Context.Request.ContentLength64 -gt 1024) { Write-JsonResponse -Context $Context -StatusCode 400 -Value @{ error = 'Invalid request body.' }; continue }
                $Reader = [IO.StreamReader]::new($Context.Request.InputStream, $Context.Request.ContentEncoding)
                try { $Body = $Reader.ReadToEnd() | ConvertFrom-Json } finally { $Reader.Dispose() }
                $BackupName = [string]$Body.name
                if (-not (Test-BackupName -Name $BackupName) -or -not (Test-Path -LiteralPath (Join-Path (Join-Path $ProjectDir 'backups') $BackupName) -PathType Leaf)) {
                    Write-JsonResponse -Context $Context -StatusCode 400 -Value @{ error = 'Invalid backup selection.' }; continue
                }
                try { $Result = Start-DashboardAction -Name restore -Target $BackupName; Write-JsonResponse -Context $Context -StatusCode 202 -Value $Result }
                catch { Write-JsonResponse -Context $Context -StatusCode 409 -Value @{ error = $_.Exception.Message } }
                continue
            }
            if ($Context.Request.HttpMethod -eq 'POST' -and $Path -match '^/api/actions/(start|restart|shutdown|backup|check-update|update|migration-export|diagnostics)$') {
                $ExpectedOrigin = "http://127.0.0.1:$Port"
                if ($Context.Request.Headers['Origin'] -ne $ExpectedOrigin) {
                    Write-JsonResponse -Context $Context -StatusCode 403 -Value @{ error = 'Request origin was rejected.' }
                    continue
                }
                try { $Result = Start-DashboardAction -Name $Matches[1]; Write-JsonResponse -Context $Context -StatusCode 202 -Value $Result }
                catch { Write-JsonResponse -Context $Context -StatusCode 409 -Value @{ error = $_.Exception.Message } }
                continue
            }

            $RelativePath = if ($Path -eq '/') { 'index.html' } else { $Path.TrimStart('/') }
            if ($RelativePath -notin @('index.html', 'app.js', 'styles.css', 'manifest.webmanifest', 'palops-icon.svg', 'service-worker.js')) {
                Write-JsonResponse -Context $Context -StatusCode 404 -Value @{ error = 'Not found.' }
                continue
            }
            $FilePath = Join-Path $WebRoot $RelativePath
            $ContentType = switch ([IO.Path]::GetExtension($FilePath)) { '.html' { 'text/html; charset=utf-8' } '.js' { 'text/javascript; charset=utf-8' } '.css' { 'text/css; charset=utf-8' } '.webmanifest' { 'application/manifest+json; charset=utf-8' } '.svg' { 'image/svg+xml' } }
            Write-HttpResponse -Context $Context -StatusCode 200 -ContentType $ContentType -Body ([IO.File]::ReadAllBytes($FilePath))
        }
        catch {
            if ($Context.Response.OutputStream.CanWrite) { Write-JsonResponse -Context $Context -StatusCode 500 -Value @{ error = 'Dashboard request failed.' } }
        }
    }
}
finally {
    $Listener.Stop()
    $Listener.Close()
    $DashboardMutex.ReleaseMutex()
    $DashboardMutex.Dispose()
    Remove-Item -LiteralPath $DashboardPidPath -Force -ErrorAction SilentlyContinue
}
