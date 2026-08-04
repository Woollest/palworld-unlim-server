$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker was not found. Start Docker Desktop and try again.'
}
& docker info | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is not ready.' }

if (-not (Test-Path '.env')) {
    Copy-Item '.env.example' '.env'
    Write-Host 'Created .env from .env.example.'
}

New-Item -ItemType Directory -Force -Path 'data\Saved', 'backups', 'logs', 'recovery', 'runtime', 'config' | Out-Null
Invoke-DiscordStatusSafe -Status Starting -Detail 'Starting Palworld Dedicated Server.'

try {
    $SettingsPath = Join-Path $ProjectDir 'data\Saved\Config\LinuxServer\PalWorldSettings.ini'
    $NeedsManagementRestart = -not (Test-Path -LiteralPath $SettingsPath)
    if (-not $NeedsManagementRestart) { Enable-PalworldManagementApi }
    Invoke-DockerCompose -Arguments @('config', '--quiet')
    Invoke-DockerCompose -Arguments @('pull')
    Invoke-DockerCompose -Arguments @('up', '-d')

    $TimeoutSeconds = [int](Get-ProjectSetting -Name 'STARTUP_TIMEOUT_SECONDS' -Default '180')
    Write-Host 'Waiting for Palworld to become ready...'
    Wait-PalworldReady -TimeoutSeconds $TimeoutSeconds

    if ($NeedsManagementRestart) {
        Write-Host 'Enabling the local Palworld management API...'
        Invoke-DockerCompose -Arguments @('stop', '--timeout', '120', 'palworld-server')
        Enable-PalworldManagementApi
        Invoke-DockerCompose -Arguments @('up', '-d')
        Wait-PalworldReady -TimeoutSeconds $TimeoutSeconds
    }

    Start-UnlimHost | Out-Null
    $ConnectionKey = Get-UnlimConnectionKey
    if (-not $ConnectionKey) { throw 'Unlim started, but its connection key could not be detected.' }
    Invoke-DiscordConnectionSafe -State Online -ConnectionKey $ConnectionKey
    Start-PlayerMonitor
    Invoke-DiscordStatusSafe -Status Online -Detail 'Palworld and Unlim are running.' -PlayerCount 0
    Set-Content -LiteralPath (Join-Path $ProjectDir 'runtime\server-enabled') -Value (Get-Date).ToString('o') -Encoding Ascii
    Remove-Item -LiteralPath (Join-Path $ProjectDir 'runtime\settings-restart-required') -Force -ErrorAction SilentlyContinue
}
catch {
    $StartupError = $_.Exception.Message
    try { Save-PalworldLogs | Out-Null } catch {}
    try { Stop-UnlimHost } catch {}
    try { Stop-PlayerMonitor } catch {}
    try { & docker compose stop --timeout 120 palworld-server 2>&1 | Out-Null } catch {}
    Remove-Item -LiteralPath (Join-Path $ProjectDir 'runtime\server-enabled') -Force -ErrorAction SilentlyContinue
    Invoke-DiscordConnectionSafe -State Offline
    Invoke-DiscordStatusSafe -Status Error -Detail $StartupError
    throw
}

Invoke-DockerCompose -Arguments @('ps')
Write-Host ''
Write-Host 'Palworld and Unlim are ready.'
Write-Host 'View logs: docker compose logs -f --tail=100'
