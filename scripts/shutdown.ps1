$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker was not found. Start Docker Desktop and try again.'
}
if (-not (Test-Path 'data\Saved')) {
    throw 'The Saved directory does not exist.'
}

$WarningSeconds = [int](Get-ProjectSetting -Name 'MAINTENANCE_WARNING_SECONDS' -Default '60')
Remove-Item -LiteralPath (Join-Path $ProjectDir 'runtime\server-enabled') -Force -ErrorAction SilentlyContinue
Invoke-DiscordStatusSafe -Status Maintenance -Detail "Server shutdown in $WarningSeconds seconds."
try { & "$PSScriptRoot\discord-notify.ps1" -Type Maintenance -Message "Palworld server maintenance will begin in $WarningSeconds seconds. Please move to a safe location and finish your current work." } catch { Write-Warning $_.Exception.Message }

try {
    Write-Host '[1/5] Warning players and stopping the Palworld server safely...'
    Stop-PlayerMonitor
    try {
        Invoke-PalworldApi -Method Post -Path 'shutdown' -Body @{ waittime = $WarningSeconds; message = 'Server maintenance will begin soon. Please move to a safe location.' } | Out-Null
        Start-Sleep -Seconds ($WarningSeconds + 5)
        # The restart policy may relaunch a process that exits itself, so Compose
        # always confirms the container is stopped before files are copied.
        Invoke-DockerCompose -Arguments @('stop', '--timeout', '120', 'palworld-server')
    }
    catch {
        Write-Warning "In-game shutdown notification failed; using Docker stop: $($_.Exception.Message)"
        Invoke-DockerCompose -Arguments @('stop', '--timeout', '120', 'palworld-server')
    }

    Write-Host '[2/5] Saving the server log...'
    Save-PalworldLogs | Out-Null

    Write-Host '[3/5] Creating and verifying a backup...'
    $BackupPath = New-PalworldBackup

    Write-Host '[4/5] Stopping Unlim...'
    Stop-UnlimHost
    Invoke-DiscordConnectionSafe -State Offline

    Write-Host '[5/5] Removing the stopped container...'
    Invoke-DockerCompose -Arguments @('down', '--timeout', '120')

    Invoke-DiscordStatusSafe -Status Offline -Detail "Backup completed: $([IO.Path]::GetFileName($BackupPath))"
    Invoke-DiscordNotificationSafe -Type BackupSuccess -Message "Shutdown backup created and verified: $([IO.Path]::GetFileName($BackupPath))"
}
catch {
    Set-Content -LiteralPath (Join-Path $ProjectDir 'runtime\server-enabled') -Value (Get-Date).ToString('o') -Encoding Ascii
    Invoke-DiscordStatusSafe -Status Error -Detail $_.Exception.Message
    Invoke-DiscordNotificationSafe -Type BackupFailure -Message "Shutdown or backup failed: $($_.Exception.Message)"
    Write-Warning 'Shutdown did not complete. Review the error before taking further action.'
    throw
}

Write-Host ''
Write-Host 'Backup and shutdown completed.'
Write-Host "Backup: $BackupPath"
