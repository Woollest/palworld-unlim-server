Write-Warning 'stop.ps1 now performs the safe backup-and-shutdown workflow.'
& "$PSScriptRoot\shutdown.ps1"
exit $LASTEXITCODE
