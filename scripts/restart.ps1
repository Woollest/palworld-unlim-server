$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
& "$PSScriptRoot\shutdown.ps1"
if ($LASTEXITCODE -ne 0) { throw 'Safe shutdown failed.' }
& "$PSScriptRoot\start.ps1"
if ($LASTEXITCODE -ne 0) { throw 'Server restart failed.' }
