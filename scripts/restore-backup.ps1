param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^palworld-\d{8}-\d{6}\.zip$')]
    [string]$BackupName
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
$BackupPath = Join-Path (Join-Path $ProjectDir 'backups') $BackupName
if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { throw 'The selected backup does not exist.' }

$WasRunning = $false
& docker info 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    $WasRunning = [bool]((& docker compose ps --status running --quiet palworld-server | Out-String).Trim())
}

if ($WasRunning) {
    & "$PSScriptRoot\shutdown.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Safe shutdown failed before restore.' }
}

try {
    & "$PSScriptRoot\restore.ps1" -BackupPath $BackupPath -NonInteractive
    if ($LASTEXITCODE -ne 0) { throw 'Backup restore failed.' }
}
catch {
    if ($WasRunning) {
        try { & "$PSScriptRoot\start.ps1" } catch {}
    }
    throw
}

if ($WasRunning) {
    & "$PSScriptRoot\start.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Restore succeeded, but the server did not restart.' }
}
