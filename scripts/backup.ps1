param(
    [ValidateSet('Manual', 'Scheduled')][string]$Mode = 'Manual'
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"
$MaintenanceLock = Join-Path $ProjectDir 'runtime\maintenance.lock'
Set-Content -LiteralPath $MaintenanceLock -Value (Get-Date).ToString('o') -Encoding Ascii
trap {
    Remove-Item -LiteralPath $MaintenanceLock -Force -ErrorAction SilentlyContinue
    throw $_
}

$WasRunning = $false
& docker info 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    $ContainerOutput = & docker compose ps --status running --quiet palworld-server
    if ($LASTEXITCODE -ne 0) { throw 'Failed to inspect Docker Compose status.' }
    $WasRunning = [bool](($ContainerOutput | Out-String).Trim())
}
else {
    Write-Host 'Docker Desktop is not running; creating an offline backup.'
}

if ($WasRunning) {
    $StatusLabel = if ($Mode -eq 'Scheduled') { 'Creating a scheduled backup.' } else { 'Creating a manual backup.' }
    Invoke-DiscordStatusSafe -Status Maintenance -Detail $StatusLabel
    $WarningSeconds = 1
    try {
        $PlayerResponse = Invoke-PalworldApi -Method Get -Path 'players'
        $PlayerCount = @($PlayerResponse.players).Count
        if ($PlayerCount -gt 0) {
            $WarningSeconds = [int](Get-ProjectSetting -Name 'MAINTENANCE_WARNING_SECONDS' -Default '60')
            Invoke-DiscordNotificationSafe -Type Maintenance -Message "A manual backup will restart the Palworld server in $WarningSeconds seconds. Please move to a safe location."
        }
        Invoke-PalworldApi -Method Post -Path 'save' | Out-Null
        Invoke-PalworldApi -Method Post -Path 'shutdown' -Body @{ waittime = $WarningSeconds; message = 'Server backup will begin soon. Please move to a safe location.' } | Out-Null
        Stop-PlayerMonitor
        Start-Sleep -Seconds ($WarningSeconds + 5)
        Invoke-DockerCompose -Arguments @('stop', '--timeout', '30', 'palworld-server')
    }
    catch {
        Write-Warning "Palworld API shutdown failed; using Docker stop: $($_.Exception.Message)"
        Stop-PlayerMonitor
        Invoke-DockerCompose -Arguments @('stop', '--timeout', '60', 'palworld-server')
    }
}

try {
    $BackupPath = New-PalworldBackup
}
catch {
    $FailureLabel = if ($Mode -eq 'Scheduled') { 'Scheduled backup failed' } else { 'Manual backup failed' }
    Invoke-DiscordStatusSafe -Status Error -Detail "$FailureLabel."
    Invoke-DiscordNotificationSafe -Type BackupFailure -Message "$FailureLabel`: $($_.Exception.Message)"
    throw
}
finally {
    if ($WasRunning) {
        Invoke-DockerCompose -Arguments @('start', 'palworld-server')
        $TimeoutSeconds = [int](Get-ProjectSetting -Name 'STARTUP_TIMEOUT_SECONDS' -Default '180')
        Wait-PalworldReady -TimeoutSeconds $TimeoutSeconds
        Start-PlayerMonitor
    }
}

if ($WasRunning) {
    $CompletedLabel = if ($Mode -eq 'Scheduled') { 'Scheduled backup completed; server restarted.' } else { 'Manual backup completed; server restarted.' }
    Invoke-DiscordStatusSafe -Status Online -Detail $CompletedLabel
}
$SuccessLabel = if ($Mode -eq 'Scheduled') { 'Scheduled backup' } else { 'Manual backup' }
Invoke-DiscordNotificationSafe -Type BackupSuccess -Message "$SuccessLabel created and verified: $([IO.Path]::GetFileName($BackupPath))"
Write-Host "Backup: $BackupPath"
Remove-Item -LiteralPath $MaintenanceLock -Force -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
