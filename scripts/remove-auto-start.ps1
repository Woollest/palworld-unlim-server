$ErrorActionPreference = 'Stop'
$TaskName = 'Palworld-Unlim-AutoStart'
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Auto-start task removed: $TaskName"
} else {
    Write-Host 'Auto-start task is not registered.'
}
