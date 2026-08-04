$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$TaskName = 'Palworld-Unlim-AutoStart'
$DashboardTaskName = 'PalOps-Dashboard-AutoStart'
$DiscordCommandTaskName = 'PalOps-Discord-Commands-AutoStart'
$WScript = "$env:SystemRoot\System32\wscript.exe"
$HiddenRunner = Join-Path $PSScriptRoot 'run-hidden.vbs'
$PwshHiddenRunner = Join-Path $PSScriptRoot 'run-hidden-pwsh.vbs'
$AutoStartScript = Join-Path $PSScriptRoot 'autostart.ps1'
$Action = New-ScheduledTaskAction -Execute $WScript -Argument "//B //Nologo `"$HiddenRunner`" `"$AutoStartScript`"" -WorkingDirectory $ProjectDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 2)
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description 'Starts Docker-backed Palworld and Unlim after Windows sign-in.' -Force | Out-Null
$DashboardScript = Join-Path $PSScriptRoot 'dashboard.ps1'
$DashboardAction = New-ScheduledTaskAction -Execute $WScript -Argument "//B //Nologo `"$HiddenRunner`" `"$DashboardScript`" -NoBrowser" -WorkingDirectory $ProjectDir
$DashboardSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $DashboardTaskName -Action $DashboardAction -Trigger $Trigger -Settings $DashboardSettings -Principal $Principal -Description 'Keeps the local PalOps dashboard available after Windows sign-in.' -Force | Out-Null
$DiscordCommandScript = Join-Path $PSScriptRoot 'discord-command-bot.ps1'
$DiscordCommandAction = New-ScheduledTaskAction -Execute $WScript -Argument "//B //Nologo `"$PwshHiddenRunner`" `"$DiscordCommandScript`"" -WorkingDirectory $ProjectDir
Register-ScheduledTask -TaskName $DiscordCommandTaskName -Action $DiscordCommandAction -Trigger $Trigger -Settings $DashboardSettings -Principal $Principal -Description 'Runs the local PalOps Discord command processor.' -Force | Out-Null
Write-Host "Auto-start task registered: $TaskName"
Write-Host "Dashboard task registered: $DashboardTaskName"
Write-Host "Discord command task registered: $DiscordCommandTaskName"
Write-Host 'It runs after this Windows user signs in and waits for Docker Desktop.'
