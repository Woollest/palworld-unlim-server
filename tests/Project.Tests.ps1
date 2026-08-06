Describe 'Palworld Server repository' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
    }

    It 'contains the required public entry points' {
        foreach ($Path in @('compose.yaml', 'README.md', 'LICENSE', 'Open-Dashboard.cmd', 'web/index.html', 'web/styles.css', 'web/app.js', 'web/manifest.webmanifest', 'web/service-worker.js', 'web/palops-icon.svg', 'desktop/src-tauri/Cargo.toml', 'desktop/src-tauri/Cargo.lock', 'desktop/src-tauri/src/main.rs', 'desktop/src-tauri/tauri.release.conf.json', 'config/PalWorldSettings.ini.example', 'scripts/dashboard.ps1', 'scripts/dashboard-action.ps1', 'scripts/open-dashboard.ps1', 'scripts/test-project.ps1', '.github/workflows/ci.yml', '.github/workflows/desktop.yml', '.github/workflows/release.yml')) {
            if (-not (Test-Path (Join-Path $ProjectRoot $Path))) { throw "Missing: $Path" }
        }
    }

    It 'parses every PowerShell script' {
        $Files = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.ps1' -File; Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'scripts') -Filter '*.ps1' -File; Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests') -Filter '*.ps1' -File)
        foreach ($File in $Files) {
            [void][scriptblock]::Create((Get-Content -LiteralPath $File.FullName -Raw))
        }
    }

    It 'keeps the REST API on localhost' {
        $Compose = Get-Content -LiteralPath (Join-Path $ProjectRoot 'compose.yaml') -Raw
        if ($Compose -notmatch '127\.0\.0\.1:\$\{PALWORLD_REST_PORT:-8212\}:8212/tcp') { throw 'REST API is not bound to localhost.' }
    }

    It 'keeps the PalOps dashboard on localhost' {
        $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -Raw
        if ($Dashboard -notmatch 'http://127\.0\.0\.1:\$Port/') { throw 'Dashboard is not bound to localhost.' }
        if ($Dashboard -notmatch "Headers\['Origin'\]") { throw 'Dashboard origin validation is missing.' }
    }

    It 'ships an installable PWA without caching API requests' {
        $Manifest = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/manifest.webmanifest') -Raw | ConvertFrom-Json
        $Worker = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/service-worker.js') -Raw
        $Page = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/index.html') -Raw
        if ($Manifest.display -ne 'standalone' -or @($Manifest.icons).Count -lt 2) { throw 'PWA manifest is incomplete.' }
        if ($Worker -notmatch "pathname\.startsWith\('/api/'\)") { throw 'Service worker may cache live API requests.' }
        if ($Page -notmatch 'rel="manifest"' -or $Page -notmatch 'id="installApp"') { throw 'PWA installation UI is missing.' }
    }

    It 'constrains the desktop shell to local PalOps' {
        $Desktop = Get-Content -LiteralPath (Join-Path $ProjectRoot 'desktop/src-tauri/src/main.rs') -Raw
        $DesktopConfig = Get-Content -LiteralPath (Join-Path $ProjectRoot 'desktop/src-tauri/tauri.conf.json') -Raw | ConvertFrom-Json
        $App = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/app.js') -Raw
        $Readme = Get-Content -LiteralPath (Join-Path $ProjectRoot 'README.md') -Raw
        if ($Desktop -notmatch 'http://127\.0\.0\.1:8765/\?desktop=1' -or $Desktop -notmatch 'host_str\(\) == Some\("127\.0\.0\.1"\)') { throw 'Desktop navigation is not loopback-only.' }
        if ($App -notmatch "get\('desktop'\) === '1'" -or $App -notmatch 'if \(isDesktopShell\).*installApp.*hidden') { throw 'Desktop-only PWA controls are not suppressed.' }
        if ($Desktop -notmatch 'tauri_plugin_single_instance::init' -or $Desktop -notmatch 'get_webview_window\("main"\)') { throw 'Desktop single-instance focusing is missing.' }
        if ($Desktop -notmatch 'project-path\.txt' -or $Desktop -notmatch 'pick_folder') { throw 'Installed app cannot remember its PalworldServer folder.' }
        if (-not $DesktopConfig.bundle.active -or @($DesktopConfig.bundle.targets) -notcontains 'nsis' -or $DesktopConfig.bundle.windows.nsis.installMode -ne 'currentUser') { throw 'Current-user NSIS installer is not configured.' }
        if ($Desktop -notmatch 'tauri_plugin_updater' -or $Desktop -notmatch 'download_and_install') { throw 'Signed desktop updater is not implemented.' }
        if ($DesktopConfig.plugins.updater.endpoints -notcontains 'https://github.com/Woollest/palworld-unlim-server/releases/latest/download/latest.json') { throw 'Desktop updater endpoint is invalid.' }
        if ([string]::IsNullOrWhiteSpace($DesktopConfig.plugins.updater.pubkey)) { throw 'Desktop updater public key is missing.' }
        $Release = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github/workflows/release.yml') -Raw
        if ($Release -notmatch 'TAURI_SIGNING_PRIVATE_KEY' -or $Release -notmatch 'latest\.json' -or $Release -notmatch 'desktop-release') { throw 'Desktop updater release automation is incomplete.' }
        if ($Readme -notmatch '日常運用はPalOps EXEから' -or $Readme -notmatch '`Open-Dashboard\.cmd`はブラウザ版PalOpsを開く復旧用入口') { throw 'README does not describe the EXE as the primary operator entry point.' }
    }


    It 'serializes and records dashboard operations' {
        $Runner = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/dashboard-action.ps1') -Raw
        if ($Runner -notmatch 'FileShare\]::None') { throw 'Exclusive action lock is missing.' }
        if ($Runner -notmatch 'dashboard-history\.json') { throw 'Action history is missing.' }
    }

    It 'returns action history as a flat array' {
        . (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -FunctionsOnly
        $ActionHistoryPath = Join-Path $TestDrive 'dashboard-history.json'
        @([pscustomobject]@{name='backup';state='succeeded'},[pscustomobject]@{name='restart';state='failed'}) | ConvertTo-Json | Set-Content $ActionHistoryPath
        $History = @(Get-ActionHistory)
        if ($History.Count -ne 2 -or $History[0].name -ne 'backup' -or $History[0].PSObject.Properties.Name -contains 'value') { throw 'Action history is nested.' }
    }

    It 'records automatic operations and clears only display history' {
        . (Join-Path $ProjectRoot 'scripts/common.ps1')
        $HistoryPath = Join-Path $TestDrive 'automatic-history.json'
        $Now = (Get-Date).ToString('o')
        Add-PalOpsOperationHistory -Name 'automatic-backup' -State 'succeeded' -StartedAt $Now -CompletedAt $Now -Target 'test.zip' -Path $HistoryPath
        $History = @(Get-PalOpsOperationHistory -Path $HistoryPath)
        if ($History.Count -ne 1 -or $History[0].name -ne 'automatic-backup') { throw 'Automatic operation was not recorded.' }
        Clear-PalOpsOperationHistory -Path $HistoryPath
        if (@(Get-PalOpsOperationHistory -Path $HistoryPath).Count -ne 0) { throw 'Display history was not cleared.' }
    }

    It 'does not pass an empty positional argument to action scripts' {
        $Runner = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/dashboard-action.ps1') -Raw
        if ($Runner -notmatch 'if \(@\(\$ScriptArguments\)\.Count -gt 0\)' -or $Runner -notmatch 'else \{ & \$ScriptPath \}') {
            throw 'Argument-free actions may receive an empty positional argument.'
        }
    }


    It 'renders bounded health history without external chart code' {
        $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -Raw
        $Client = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/app.js') -Raw
        $Page = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/index.html') -Raw
        if ($Dashboard -notmatch '\$MaximumPoints = 180') { throw 'Health history is not bounded.' }
        if ($Client -notmatch 'renderChart' -or $Page -match '<script[^>]+src=["'']https?://') { throw 'Charts are not self-contained.' }
    }


    It 'classifies healthy, disconnected and stopped states' {
        . (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -FunctionsOnly
        $BackupPath = Join-Path $TestDrive 'recent.zip'
        Set-Content -LiteralPath $BackupPath -Value 'test'
        $Backup = Get-Item -LiteralPath $BackupPath
        $Health = [pscustomobject]@{ points = @(
            [pscustomobject]@{ online = $true; cpu = 20; memory = 30; fps = 59 },
            [pscustomobject]@{ online = $true; cpu = 25; memory = 32; fps = 59 },
            [pscustomobject]@{ online = $true; cpu = 30; memory = 35; fps = 59 }
        ) }
        $Healthy = Get-OperationalInsights -ServerRunning $true -UnlimRunning $true -Disk $null -LatestBackup $Backup -Health $Health
        $Disconnected = Get-OperationalInsights -ServerRunning $true -UnlimRunning $false -Disk $null -LatestBackup $Backup -Health $Health
        $Stopped = Get-OperationalInsights -ServerRunning $false -UnlimRunning $false -Disk $null -LatestBackup $Backup -Health $Health
        if ($Healthy.state -ne 'healthy') { throw "Expected healthy, got $($Healthy.state)." }
        if ($Disconnected.state -ne 'critical') { throw "Expected critical, got $($Disconnected.state)." }
        if ($Stopped.state -ne 'stopped') { throw "Expected stopped, got $($Stopped.state)." }
    }


    It 'reads persisted update availability' {
        . (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -FunctionsOnly
        $ProjectDir = Join-Path $TestDrive 'update-project'
        New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir 'runtime') | Out-Null
        Set-Content -LiteralPath (Join-Path $ProjectDir '.env') -Value 'PALWORLD_IMAGE=ghcr.io/pocketpairjp/palserver:v1.0.0.0'
        [pscustomobject]@{ checkedAt = '2026-08-04T00:00:00+09:00'; currentTag = 'v1.0.0.0'; latestTag = 'v1.0.1.0'; available = $true } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $ProjectDir 'runtime/update-status.json')
        $Status = Get-UpdateStatus
        if (-not $Status.known -or -not $Status.available -or $Status.latestTag -ne 'v1.0.1.0') { throw 'Persisted update status was not returned.' }
    }


    It 'keeps one recoverable dashboard instance' {
        $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -Raw
        $Watchdog = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/watchdog.ps1') -Raw
        if ($Dashboard -notmatch 'Local\\PalOpsDashboard' -or $Watchdog -notmatch 'dashboard\.ps1') { throw 'Single-instance recovery is incomplete.' }
    }

    It 'controls background automation through persistent allowlisted tasks' {
        $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -Raw
        $Monitor = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/player-monitor.ps1') -Raw
        $Web = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/app.js') -Raw
        if ($Dashboard -notmatch 'Get-AutomationSettings' -or $Dashboard -notmatch 'Enable-ScheduledTask' -or $Dashboard -notmatch 'Disable-ScheduledTask') { throw 'Persistent automation controls are incomplete.' }
        if ($Monitor -notmatch 'AutomaticRecoveryEnabled' -or $Web -notmatch 'data-automation') { throw 'Automation state is not enforced or displayed.' }
    }


    It 'rejects unsafe backup names' {
        . (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -FunctionsOnly
        if (-not (Test-BackupName 'palworld-20260804-120000.zip')) { throw 'A valid backup name was rejected.' }
        foreach ($UnsafeName in @('..\secret.zip', '../secret.zip', 'other.zip', 'palworld-20260804-120000.zip.exe', 'C:\temp\palworld-20260804-120000.zip')) {
            if (Test-BackupName $UnsafeName) { throw "Unsafe backup name accepted: $UnsafeName" }
        }
    }


    It 'bounds maintenance scheduling operations' {
        $Maintenance = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/maintenance.ps1') -Raw
        if ($Maintenance -notmatch "ValidateSet\('restart', 'update', 'backup', 'shutdown'\)") { throw 'Maintenance operation allowlist is missing.' }
        if ($Maintenance -notmatch 'AddDays\(30\)' -or $Maintenance -notmatch 'AddMinutes\(1\)') { throw 'Maintenance time bounds are incomplete.' }
    }


    It 'validates and snapshots editable world settings' {
        . (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -FunctionsOnly
        $ProjectDir = Join-Path $TestDrive 'settings-project'
        $SettingsDir = Join-Path $ProjectDir 'data/Saved/Config/LinuxServer'
        New-Item -ItemType Directory -Force -Path $SettingsDir, (Join-Path $ProjectDir 'runtime') | Out-Null
        $SettingsPath = Join-Path $SettingsDir 'PalWorldSettings.ini'
        Set-Content -LiteralPath $SettingsPath -Value '[/Script/Pal.PalGameWorldSettings]`nOptionSettings=(ExpRate=1.500000,ServerPlayerMaxNum=8,ServerName="fixture")'
        $UnknownFailed = $false
        try { Set-EditableWorldSettings -Submitted ([pscustomobject]@{ UnknownSetting = 1 }) | Out-Null } catch { $UnknownFailed = $true }
        $RangeFailed = $false
        try { Set-EditableWorldSettings -Submitted ([pscustomobject]@{ ExpRate = 100 }) | Out-Null } catch { $RangeFailed = $true }
        if (-not $UnknownFailed -or -not $RangeFailed) { throw 'Unsafe setting input was accepted.' }
        $Result = Set-EditableWorldSettings -Submitted ([pscustomobject]@{ ExpRate = 2.5 })
        $Updated = Get-Content -LiteralPath $SettingsPath -Raw
        if ($Result.changes.Count -ne 1 -or $Updated -notmatch 'ExpRate=2\.5' -or $Updated -notmatch 'ServerName="fixture"') { throw 'Allowlisted setting update did not preserve unrelated values.' }
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir 'runtime/settings-restart-required'))) { throw 'Restart marker was not created.' }
        if (@(Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'recovery/settings') -Filter '*.ini').Count -ne 1) { throw 'Settings snapshot was not created.' }
    }


    It 'parses Discord commands and checks Administrator permission' {
        . (Join-Path $ProjectRoot 'scripts/discord-command-bot.ps1') -FunctionsOnly
        $StatusCommand = Parse-PalOpsCommand -Content '  !PALOPS status  ' -Prefix '!palops'
        $ConfirmCommand = Parse-PalOpsCommand -Content '!palops confirm ABC123' -Prefix '!palops'
        if ($StatusCommand.name -ne 'status' -or $ConfirmCommand.name -ne 'confirm' -or $ConfirmCommand.argument -ne 'ABC123') { throw 'Discord command parsing failed.' }
        if ($null -ne (Parse-PalOpsCommand -Content '!other status' -Prefix '!palops')) { throw 'Foreign command prefix was accepted.' }
        $Roles = @([pscustomobject]@{ id = 'guild'; permissions = '0' }, [pscustomobject]@{ id = 'admin-role'; permissions = '8' }, [pscustomobject]@{ id = 'member-role'; permissions = '1024' })
        if (-not (Test-AdministratorPermissions -RoleIds @('admin-role') -GuildRoles $Roles -GuildId 'guild')) { throw 'Administrator role was rejected.' }
        if (Test-AdministratorPermissions -RoleIds @('member-role') -GuildRoles $Roles -GuildId 'guild') { throw 'Non-administrator role was accepted.' }
    }

    It 'records and displays player access history locally' {
        $Monitor = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/player-monitor.ps1') -Raw
        $Dashboard = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -Raw
        $Page = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/index.html') -Raw
        $App = Get-Content -LiteralPath (Join-Path $ProjectRoot 'web/app.js') -Raw
        if ($Monitor -notmatch 'player-access\.json' -or $Monitor -notmatch 'lastSeenAt' -or $Monitor -notmatch 'Save-PlayerAccessDirectory') { throw 'Persistent player access tracking is incomplete.' }
        if ($Dashboard -notmatch "'/api/players'" -or $Dashboard -notmatch 'Get-PlayerAccessDirectory') { throw 'Player directory API is missing.' }
        if ($Page -notmatch 'id="playerDirectory"' -or $App -notmatch "fetch\('/api/players'") { throw 'Player directory UI is missing.' }
        if ($App -match 'innerHTML\s*=.*player\.') { throw 'Player-provided values may be rendered as HTML.' }
    }

    It 'calculates completed and active player sessions' {
        . (Join-Path $ProjectRoot 'scripts/dashboard.ps1') -FunctionsOnly
        $OriginalEventsPath = $PlayerEventsPath
        try {
            $PlayerEventsPath = Join-Path $TestDrive 'player-sessions.csv'
            @(
                'timestamp,event,name,accountName,userId',
                '"2026-08-01T00:00:00+09:00","JOIN","Tester","Tester","steam_test"',
                '"2026-08-01T01:00:00+09:00","LEAVE","Tester","Tester","steam_test"',
                '"2026-08-01T02:00:00+09:00","JOIN","Tester","Tester","steam_test"'
            ) | Set-Content -LiteralPath $PlayerEventsPath -Encoding UTF8
            $Statistics = Get-PlayerSessionStatistics
            $Player = $Statistics['user:steam_test']
            if ([int]$Player.totalSeconds -ne 3600 -or $Player.completedSessions -ne 1 -or $null -eq $Player.activeStart -or $Player.estimated) { throw 'Session durations were calculated incorrectly.' }
        }
        finally { $PlayerEventsPath = $OriginalEventsPath }
    }
}
