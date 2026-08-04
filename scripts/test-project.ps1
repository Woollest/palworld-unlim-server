param(
    [switch]$Online,
    [switch]$Notify
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$PSScriptRoot\common.ps1"

$Results = [System.Collections.Generic.List[object]]::new()

function Add-TestResult {
    param([string]$Name, [ValidateSet('PASS', 'FAIL', 'SKIP')][string]$Status, [string]$Detail = '')
    $Results.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail })
    $Color = switch ($Status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    Write-Host ("[{0}] {1}{2}" -f $Status, $Name, $(if ($Detail) { " - $Detail" } else { '' })) -ForegroundColor $Color
}

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Test)
    try {
        & $Test
        Add-TestResult -Name $Name -Status PASS
    }
    catch {
        Add-TestResult -Name $Name -Status FAIL -Detail $_.Exception.Message
    }
}

Write-Host 'Palworld Server project checks' -ForegroundColor Cyan
Write-Host ("Mode: {0}" -f $(if ($Online) { 'online' } else { 'repository' }))
Write-Host ''

Invoke-TestCase 'Required public files exist' {
    $Required = @('.env.example', '.gitattributes', '.gitignore', 'LICENSE', 'CONTRIBUTING.md', 'compose.yaml', 'README.md', 'SECURITY.md', 'Manage-Server.ps1', 'Open-Server-Manager.cmd', 'config/discord.env.example', 'config/PalWorldSettings.ini.example', 'docker/helper.sh', 'docs/ARCHITECTURE.md', '.github/workflows/ci.yml', '.github/workflows/release.yml', 'scripts/build-release.ps1')
    $Missing = @($Required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ProjectDir $_)) })
    if ($Missing.Count) { throw "Missing: $($Missing -join ', ')" }
}

Invoke-TestCase 'All PowerShell files parse' {
    $Files = @(Get-ChildItem -LiteralPath $ProjectDir -Filter '*.ps1' -File; Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'scripts') -Filter '*.ps1' -File; Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'tests') -Filter '*.ps1' -File)
    foreach ($File in $Files) { [void][scriptblock]::Create((Get-Content -LiteralPath $File.FullName -Raw)) }
}

Invoke-TestCase 'Docker Compose configuration is valid' {
    & docker compose config --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'docker compose config failed.' }
}

Invoke-TestCase 'Management API is localhost-only' {
    $Compose = Get-Content -LiteralPath (Join-Path $ProjectDir 'compose.yaml') -Raw
    if ($Compose -notmatch '127\.0\.0\.1:\$\{PALWORLD_REST_PORT:-8212\}:8212/tcp') { throw 'REST API port 8212 is not explicitly bound to 127.0.0.1.' }
    if ($Compose -match '(?m)^\s*-\s*["'']?8212:8212') { throw 'REST API has a public port binding.' }
}

Invoke-TestCase 'Git excludes secrets and generated data' {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir '.git'))) { throw 'Local Git repository is not initialized.' }
    foreach ($Path in @('.env', 'config/discord.env', 'config/admin.env', 'data/Saved', 'runtime/state.tmp', 'backups/test.zip', 'logs/test.log', 'recovery/test.tmp', 'reports/latest-test-results.json')) {
        & git check-ignore --no-index -q -- $Path
        if ($LASTEXITCODE -ne 0) { throw "Not ignored: $Path" }
    }
}

Invoke-TestCase 'Public files contain no credential-shaped values' {
    $Candidates = @(& git ls-files --cached --others --exclude-standard)
    $TokenPattern = '[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{20,}'
    $LiteralSecretPattern = '(?:TOKEN|PASSWORD)\s*=\s*["''][A-Za-z0-9_+/=-]{24,}["'']'
    foreach ($File in $Candidates) {
        if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { continue }
        $Text = Get-Content -LiteralPath $File -Raw -ErrorAction SilentlyContinue
        if ($Text -match $TokenPattern -or $Text -match $LiteralSecretPattern) { throw "Possible credential in: $File" }
    }
}

Invoke-TestCase 'Environment template contains required settings' {
    $Template = Get-Content -LiteralPath (Join-Path $ProjectDir '.env.example') -Raw
    foreach ($Name in @('PALWORLD_IMAGE', 'PALWORLD_PORT', 'PALWORLD_REST_PORT', 'MAX_PLAYERS', 'BACKUP_RETENTION', 'STARTUP_TIMEOUT_SECONDS')) {
        if ($Template -notmatch "(?m)^$Name=.+$") { throw "Missing template setting: $Name" }
    }
}

Invoke-TestCase 'Public world-settings template contains no local identity or password' {
    $Template = Get-Content -LiteralPath (Join-Path $ProjectDir 'config/PalWorldSettings.ini.example') -Raw
    if ($Template -notmatch 'AdminPassword=""') { throw 'AdminPassword must be empty in the public template.' }
    if ($Template -notmatch 'ServerPassword=""') { throw 'ServerPassword must be empty in the public template.' }
    if ($Template -match 'C:\\Users\\|AdminPassword="[^"]+"') { throw 'Local identity or password remains in the public template.' }
}

if ($Online) {
    Invoke-TestCase 'World settings are structurally valid' {
        $SettingsPath = Join-Path $ProjectDir 'data\Saved\Config\LinuxServer\PalWorldSettings.ini'
        $Text = Get-Content -LiteralPath $SettingsPath -Raw
        if ($Text -notmatch '^\s*\[/Script/Pal\.PalGameWorldSettings\]') { throw 'Settings section header is missing.' }
        if ($Text -notmatch 'OptionSettings=\(.+\)') { throw 'OptionSettings is malformed.' }
        foreach ($Expected in @('ServerPlayerMaxNum=8', 'CrossplayPlatforms=\(Steam\)', 'RESTAPIEnabled=True', 'RCONEnabled=False')) {
            if ($Text -notmatch $Expected) { throw "Required setting not found: $Expected" }
        }
    }

    Invoke-TestCase 'Latest backup contains required world saves' {
        $Latest = Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'backups') -Filter '*.zip' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $Latest) { throw 'No backup ZIP exists.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $Archive = [IO.Compression.ZipFile]::OpenRead($Latest.FullName)
        try {
            $Names = $Archive.Entries.FullName
            if (-not ($Names -match '^Saved[\\/]SaveGames[\\/].+[\\/]Level\.sav$')) { throw 'Level.sav is missing.' }
            if (-not ($Names -match '^Saved[\\/]SaveGames[\\/].+[\\/]LevelMeta\.sav$')) { throw 'LevelMeta.sav is missing.' }
        }
        finally { $Archive.Dispose() }
    }

    Invoke-TestCase 'Docker and Palworld container are running' {
        & docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is unavailable.' }
        $Id = (& docker compose ps --status running --quiet palworld-server | Out-String).Trim()
        if (-not $Id) { throw 'Palworld container is not running.' }
    }

    Invoke-TestCase 'Container mounts use the organized data paths' {
        $Inspect = & docker inspect palworld-server | ConvertFrom-Json
        $Sources = @($Inspect[0].Mounts.Source)
        if ($Sources -notcontains (Join-Path $ProjectDir 'data\Saved')) { throw 'data/Saved mount is missing.' }
        if ($Sources -notcontains (Join-Path $ProjectDir 'docker\helper.sh')) { throw 'docker/helper.sh mount is missing.' }
    }

    Invoke-TestCase 'Palworld REST API returns metrics' {
        $Metrics = Invoke-PalworldApi -Method Get -Path 'metrics'
        if ($null -eq $Metrics.serverfps -or $null -eq $Metrics.uptime) { throw 'Metrics response is incomplete.' }
    }

    Invoke-TestCase 'Unlim and player monitor are running' {
        if (-not (Test-UnlimHost)) { throw 'Unlim is not running.' }
        $PidPath = Join-Path $ProjectDir 'runtime\player-monitor.pid'
        if (-not (Test-Path -LiteralPath $PidPath)) { throw 'Player monitor PID is missing.' }
        $PidValue = (Get-Content -LiteralPath $PidPath -Raw).Trim()
        if ($PidValue -notmatch '^\d+$' -or -not (Get-Process -Id ([int]$PidValue) -ErrorAction SilentlyContinue)) { throw 'Player monitor is not running.' }
    }

    Invoke-TestCase 'Windows maintenance tasks use the current project path' {
        $ExpectedTasks = @('Palworld-Unlim-AutoStart', 'Palworld-Monitor-Watchdog', 'Palworld-Idle-Backup', 'Palworld-Backup-Verify', 'Palworld-Update-Check', 'Palworld-Health-Metrics', 'Palworld-Log-Maintenance', 'Palworld-Project-Test')
        foreach ($Name in $ExpectedTasks) {
            $Task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
            if (-not $Task) { throw "Scheduled task is missing: $Name" }
            if ($Task.State -eq 'Disabled') { throw "Scheduled task is disabled: $Name" }
            if (($Task.Actions.Arguments -join ';') -notlike "*$ProjectDir*") { throw "Scheduled task uses an old path: $Name" }
        }
    }
}
else {
    Add-TestResult -Name 'Live server, backups and scheduled tasks' -Status SKIP -Detail 'Run with -Online to include operational checks.'
}

$Passed = @($Results | Where-Object status -eq 'PASS').Count
$Failed = @($Results | Where-Object status -eq 'FAIL').Count
$Skipped = @($Results | Where-Object status -eq 'SKIP').Count
$ReportDir = Join-Path $ProjectDir 'reports'
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$Report = [pscustomobject]@{ timestamp = (Get-Date).ToString('o'); online = [bool]$Online; passed = $Passed; failed = $Failed; skipped = $Skipped; results = $Results }
$Report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ReportDir 'latest-test-results.json') -Encoding UTF8

Write-Host ''
Write-Host ("Result: {0} passed, {1} failed, {2} skipped" -f $Passed, $Failed, $Skipped) -ForegroundColor $(if ($Failed) { 'Red' } else { 'Green' })
if ($Notify -and $Failed -gt 0) {
    Invoke-DiscordNotificationSafe -Type ServiceError -Message "Automated project checks failed: $Failed failure(s). Review reports/latest-test-results.json."
}
if ($Failed -gt 0) { exit 1 }
exit 0
