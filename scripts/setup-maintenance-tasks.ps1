$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$WScript = "$env:SystemRoot\System32\wscript.exe"
$HiddenRunner = Join-Path $PSScriptRoot 'run-hidden.vbs'
$User = "$env:USERDOMAIN\$env:USERNAME"
$Principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

function Register-PalworldTask {
    param([string]$Name, [string]$Script, $Trigger)
    $ScriptPath = Join-Path $PSScriptRoot $Script
    $Action = New-ScheduledTaskAction -Execute $WScript -Argument "//B //Nologo `"$HiddenRunner`" `"$ScriptPath`"" -WorkingDirectory $ProjectDir
    Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force | Out-Null
}

$LongDuration = New-TimeSpan -Days 3650
$WatchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration $LongDuration
$BackupTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration $LongDuration
$VerifyTrigger = New-ScheduledTaskTrigger -Daily -At '04:30'
$UpdateTrigger = New-ScheduledTaskTrigger -Daily -At '12:00'
$HealthTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration $LongDuration
$LogMaintenanceTrigger = New-ScheduledTaskTrigger -Daily -At '04:45'
$ProjectTestTrigger = New-ScheduledTaskTrigger -Daily -At '05:00'
Register-PalworldTask -Name 'Palworld-Monitor-Watchdog' -Script 'watchdog.ps1' -Trigger $WatchdogTrigger
Register-PalworldTask -Name 'Palworld-Idle-Backup' -Script 'scheduled-backup.ps1' -Trigger $BackupTrigger
Register-PalworldTask -Name 'Palworld-Backup-Verify' -Script 'verify-backups.ps1' -Trigger $VerifyTrigger
Register-PalworldTask -Name 'Palworld-Update-Check' -Script 'check-update.ps1' -Trigger $UpdateTrigger
Register-PalworldTask -Name 'Palworld-Health-Metrics' -Script 'health-metrics.ps1' -Trigger $HealthTrigger
Register-PalworldTask -Name 'Palworld-Log-Maintenance' -Script 'log-maintenance.ps1' -Trigger $LogMaintenanceTrigger
Register-PalworldTask -Name 'Palworld-Project-Test' -Script 'scheduled-project-test.ps1' -Trigger $ProjectTestTrigger
Write-Host 'Maintenance tasks registered.'
