$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
& "$PSScriptRoot\test-project.ps1" -Online -Notify
exit $LASTEXITCODE
