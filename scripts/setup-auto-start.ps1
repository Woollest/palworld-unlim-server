$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$TaskName = 'Palworld-Unlim-AutoStart'
$WScript = "$env:SystemRoot\System32\wscript.exe"
$HiddenRunner = Join-Path $PSScriptRoot 'run-hidden.vbs'
$AutoStartScript = Join-Path $PSScriptRoot 'autostart.ps1'
$Action = New-ScheduledTaskAction -Execute $WScript -Argument "//B //Nologo `"$HiddenRunner`" `"$AutoStartScript`"" -WorkingDirectory $ProjectDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 2)
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description 'Starts Docker-backed Palworld and Unlim after Windows sign-in.' -Force | Out-Null
Write-Host "Auto-start task registered: $TaskName"
Write-Host 'It runs after this Windows user signs in and waits for Docker Desktop.'
