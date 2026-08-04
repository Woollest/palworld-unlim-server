$ErrorActionPreference = 'Stop'
foreach ($TaskName in @('Palworld-Unlim-AutoStart', 'PalOps-Dashboard-AutoStart', 'PalOps-Discord-Commands-AutoStart')) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Auto-start task removed: $TaskName"
    } else {
        Write-Host "Auto-start task is not registered: $TaskName"
    }
}
& (Join-Path $PSScriptRoot 'stop-dashboard.ps1')
& (Join-Path $PSScriptRoot 'stop-discord-command-bot.ps1')
