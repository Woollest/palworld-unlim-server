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
    $Required = @('.env.example', '.gitattributes', '.gitignore', 'LICENSE', 'CONTRIBUTING.md', 'compose.yaml', 'README.md', 'SECURITY.md', 'Manage-Server.ps1', 'Open-Server-Manager.cmd', 'Open-Dashboard.cmd', 'web/index.html', 'web/styles.css', 'web/app.js', 'web/manifest.webmanifest', 'web/service-worker.js', 'web/palops-icon.svg', 'desktop/README.md', 'desktop/src-tauri/Cargo.toml', 'desktop/src-tauri/Cargo.lock', 'desktop/src-tauri/tauri.conf.json', 'desktop/src-tauri/tauri.release.conf.json', 'desktop/src-tauri/src/main.rs', 'config/discord.env.example', 'config/PalWorldSettings.ini.example', 'docker/helper.sh', 'docs/ARCHITECTURE.md', '.github/workflows/ci.yml', '.github/workflows/desktop.yml', '.github/workflows/release.yml', 'scripts/build-release.ps1', 'scripts/dashboard.ps1', 'scripts/dashboard-action.ps1', 'scripts/open-dashboard.ps1', 'scripts/stop-dashboard.ps1', 'scripts/restore-backup.ps1', 'scripts/maintenance.ps1', 'scripts/restart.ps1', 'scripts/discord-command-bot.ps1', 'scripts/stop-discord-command-bot.ps1')
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

Invoke-TestCase 'PalOps dashboard is localhost-only' {
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    if ($Dashboard -notmatch 'http://127\.0\.0\.1:\$Port/') { throw 'Dashboard listener is not explicitly bound to 127.0.0.1.' }
    if ($Dashboard -notmatch "Headers\['Origin'\]") { throw 'Dashboard actions do not validate the browser origin.' }
    if ($Dashboard -match 'http://\+|http://\*:') { throw 'Dashboard contains a wildcard listener.' }
}

Invoke-TestCase 'PalOps PWA is complete and keeps APIs live' {
    $Manifest = Get-Content -LiteralPath (Join-Path $ProjectDir 'web/manifest.webmanifest') -Raw | ConvertFrom-Json
    $Worker = Get-Content -LiteralPath (Join-Path $ProjectDir 'web/service-worker.js') -Raw
    $Page = Get-Content -LiteralPath (Join-Path $ProjectDir 'web/index.html') -Raw
    if ($Manifest.display -ne 'standalone' -or @($Manifest.icons).Count -lt 2) { throw 'PWA manifest is incomplete.' }
    if ($Worker -notmatch "pathname\.startsWith\('/api/'\)") { throw 'PWA may cache live API requests.' }
    if ($Page -notmatch 'rel="manifest"' -or $Page -notmatch 'id="installApp"') { throw 'PWA installation UI is missing.' }
}

Invoke-TestCase 'PalOps desktop shell is loopback-only' {
    $Desktop = Get-Content -LiteralPath (Join-Path $ProjectDir 'desktop/src-tauri/src/main.rs') -Raw
    $DesktopConfig = Get-Content -LiteralPath (Join-Path $ProjectDir 'desktop/src-tauri/tauri.conf.json') -Raw | ConvertFrom-Json
    $App = Get-Content -LiteralPath (Join-Path $ProjectDir 'web/app.js') -Raw
    $Readme = Get-Content -LiteralPath (Join-Path $ProjectDir 'README.md') -Raw
    if ($Desktop -notmatch 'http://127\.0\.0\.1:8765/\?desktop=1' -or $Desktop -notmatch 'on_navigation') { throw 'Desktop navigation is not constrained.' }
    if ($Desktop -notmatch 'host_str\(\) == Some\("127\.0\.0\.1"\)' -or $Desktop -notmatch 'port_or_known_default\(\) == Some\(8765\)') { throw 'Desktop shell may navigate outside PalOps.' }
    if ($App -notmatch "get\('desktop'\) === '1'" -or $App -notmatch 'if \(isDesktopShell\).*installApp.*hidden') { throw 'Desktop-only PWA controls are not suppressed.' }
    if ($Desktop -notmatch 'tauri_plugin_single_instance::init' -or $Desktop -notmatch 'get_webview_window\("main"\)') { throw 'Desktop single-instance focusing is missing.' }
    if ($Desktop -notmatch 'project-path\.txt' -or $Desktop -notmatch 'pick_folder') { throw 'Installed app cannot remember its PalworldServer folder.' }
    if (-not $DesktopConfig.bundle.active -or @($DesktopConfig.bundle.targets) -notcontains 'nsis' -or $DesktopConfig.bundle.windows.nsis.installMode -ne 'currentUser') { throw 'Current-user NSIS installer is not configured.' }
    if ($Desktop -notmatch 'tauri_plugin_updater' -or $Desktop -notmatch 'download_and_install') { throw 'Signed desktop updater is not implemented.' }
    if ($DesktopConfig.plugins.updater.endpoints -notcontains 'https://github.com/Woollest/palworld-unlim-server/releases/latest/download/latest.json') { throw 'Desktop updater endpoint is invalid.' }
    if ([string]::IsNullOrWhiteSpace($DesktopConfig.plugins.updater.pubkey)) { throw 'Desktop updater public key is missing.' }
    $Release = Get-Content -LiteralPath (Join-Path $ProjectDir '.github/workflows/release.yml') -Raw
    if ($Release -notmatch 'TAURI_SIGNING_PRIVATE_KEY' -or $Release -notmatch 'latest\.json' -or $Release -notmatch 'desktop-release') { throw 'Desktop updater release automation is incomplete.' }
    if ($Readme -notmatch '日常運用はPalOps EXEから' -or $Readme -notmatch '`Open-Dashboard\.cmd`はブラウザ版PalOpsを開く復旧用入口') { throw 'README does not describe the EXE as the primary operator entry point.' }
}

Invoke-TestCase 'PalOps operations are serialized and recorded' {
    $Runner = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard-action.ps1') -Raw
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    if ($Runner -notmatch '\[IO\.File\]::Open\(.+FileShare\]::None') { throw 'Exclusive action locking is missing.' }
    if ($Runner -notmatch 'dashboard-history\.json') { throw 'Operation history persistence is missing.' }
    if ($Runner -notmatch "Set-ActionState -State 'failed'") { throw 'Failed operations are not recorded.' }
    if ($Dashboard -notmatch '\$Response = Get-Content -LiteralPath \$ActionHistoryPath') { throw 'Action history arrays are not normalized.' }
}

Invoke-TestCase 'PalOps omits empty positional arguments' {
    $Runner = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard-action.ps1') -Raw
    if ($Runner -notmatch 'if \(@\(\$ScriptArguments\)\.Count -gt 0\)' -or $Runner -notmatch 'else \{ & \$ScriptPath \}') {
        throw 'Argument-free actions may receive an empty positional argument.'
    }
}

Invoke-TestCase 'PalOps health history is local and bounded' {
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    if ($Dashboard -notmatch "logs\\health-metrics\.csv") { throw 'Dashboard does not use the local health history.' }
    if ($Dashboard -notmatch '\$MaximumPoints = 180') { throw 'Health API response is not bounded.' }
    $Client = Get-Content -LiteralPath (Join-Path $ProjectDir 'web/app.js') -Raw
    $Page = Get-Content -LiteralPath (Join-Path $ProjectDir 'web/index.html') -Raw
    if ($Client -notmatch 'renderChart' -or $Page -match '<script[^>]+src=["'']https?://') { throw 'Local chart rendering is missing or uses an external dependency.' }
}

Invoke-TestCase 'PalOps diagnosis covers operational risks' {
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    foreach ($Code in @('disk-low', 'backup-missing', 'backup-stale', 'unlim-offline', 'cpu-high', 'memory-high', 'fps-low')) {
        if ($Dashboard -notmatch "code = '$Code'") { throw "Missing diagnosis: $Code" }
    }
}

Invoke-TestCase 'PalOps safe update requires the guarded updater' {
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    $Runner = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard-action.ps1') -Raw
    $Updater = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/update-server.ps1') -Raw
    $Checker = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/check-update.ps1') -Raw
    if ($Dashboard -notmatch 'Get-UpdateStatus' -or $Runner -notmatch "'update' \{ 'update-server\.ps1' \}") { throw 'Dashboard update routing is incomplete.' }
    if ($Updater -notmatch 'param\(\[switch\]\$NonInteractive\)' -or $Updater -notmatch 'Restore-UpdateBackup') { throw 'Safe non-interactive update or rollback is missing.' }
    if ($Checker -notmatch 'runtime\\update-status\.json') { throw 'Update check status is not persisted.' }
}

Invoke-TestCase 'PalOps dashboard has single-instance recovery' {
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    $Watchdog = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/watchdog.ps1') -Raw
    $AutoStart = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/setup-auto-start.ps1') -Raw
    if ($Dashboard -notmatch 'Local\\PalOpsDashboard' -or $Dashboard -notmatch '\$CreatedNew') { throw 'Dashboard single-instance mutex is missing.' }
    if ($Watchdog -notmatch 'dashboard\.ps1' -or $Watchdog -notmatch 'DASHBOARD_PORT') { throw 'Dashboard watchdog recovery is missing.' }
    if ($AutoStart -notmatch 'PalOps-Dashboard-AutoStart') { throw 'Dashboard auto-start task is missing.' }
}

Invoke-TestCase 'PalOps restore is constrained and recoverable' {
    $Restore = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/restore.ps1') -Raw
    $Coordinator = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/restore-backup.ps1') -Raw
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    if ($Restore -notmatch 'ResolvedBackupsDir' -or $Restore -notmatch 'Saved-before-restore' -or $Restore -notmatch '\$NonInteractive') { throw 'Restore path confinement or rollback is missing.' }
    if ($Coordinator -notmatch 'shutdown\.ps1' -or $Coordinator -notmatch 'start\.ps1') { throw 'Coordinated restore lifecycle is incomplete.' }
    if ($Dashboard -notmatch 'Test-BackupName' -or $Dashboard -notmatch 'ContentLength64') { throw 'Dashboard restore request validation is incomplete.' }
}

Invoke-TestCase 'PalOps maintenance scheduling is bounded and persistent' {
    $Maintenance = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/maintenance.ps1') -Raw
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    if ($Maintenance -notmatch "ValidateSet\('restart', 'update', 'backup', 'shutdown'\)" -or $Maintenance -notmatch 'AddDays\(30\)') { throw 'Maintenance operation or time bounds are missing.' }
    if ($Maintenance -notmatch 'PalOps-Maintenance-\$Id' -or $Maintenance -notmatch 'maintenance-schedules\.json') { throw 'Maintenance task or persistence is missing.' }
    if ($Dashboard -notmatch '/api/maintenance/schedule' -or $Dashboard -notmatch '/cancel') { throw 'Maintenance API routes are incomplete.' }
}

Invoke-TestCase 'PalOps world settings use an allowlist and snapshots' {
    $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/dashboard.ps1') -Raw
    if ($Dashboard -notmatch 'Get-SettingsSchema' -or $Dashboard -notmatch 'Unsupported setting') { throw 'Settings allowlist is missing.' }
    if ($Dashboard -notmatch 'recovery\\settings' -or $Dashboard -notmatch 'settings-restart-required') { throw 'Settings snapshots or restart marker is missing.' }
    if ($Dashboard -notmatch '/api/settings' -or $Dashboard -notmatch 'ContentLength64') { throw 'Settings API bounds are incomplete.' }
}

Invoke-TestCase 'PalOps Discord commands are permissioned and confirmed' {
    $Bot = Get-Content -LiteralPath (Join-Path $ProjectDir 'scripts/discord-command-bot.ps1') -Raw
    $Template = Get-Content -LiteralPath (Join-Path $ProjectDir 'config/discord.env.example') -Raw
    if ($Bot -notmatch 'Test-AdministratorPermissions' -or $Bot -notmatch 'Request-Confirmation' -or $Bot -notmatch 'Confirm-Action') { throw 'Discord command authorization or confirmation is missing.' }
    if ($Bot -match 'Get-UnlimConnectionKey' -or $Bot -match '/api/actions/(shutdown|update|restore)') { throw 'Discord commands expose a secret or unsafe direct operation.' }
    if ($Template -notmatch 'DISCORD_COMMAND_CHANNEL_ID=' -or $Template -notmatch 'DISCORD_COMMAND_PREFIX=') { throw 'Discord command configuration is missing.' }
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
        $ExpectedTasks = @('Palworld-Unlim-AutoStart', 'PalOps-Dashboard-AutoStart', 'PalOps-Discord-Commands-AutoStart', 'Palworld-Monitor-Watchdog', 'Palworld-Idle-Backup', 'Palworld-Backup-Verify', 'Palworld-Update-Check', 'Palworld-Health-Metrics', 'Palworld-Log-Maintenance', 'Palworld-Project-Test')
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
