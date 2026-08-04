$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$ExportDir = Join-Path $ProjectDir 'exports'
$StageDir = Join-Path $ProjectDir ('runtime\migration-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $ExportDir, $StageDir | Out-Null
try {
    $Backup = Get-ChildItem (Join-Path $ProjectDir 'backups') -Filter 'palworld-*.zip' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $Backup) { throw 'Create a world backup before exporting a migration package.' }
    Copy-Item $Backup.FullName (Join-Path $StageDir $Backup.Name)
    Copy-Item (Join-Path $ProjectDir 'compose.yaml') $StageDir
    $ConfigDir = Join-Path $StageDir 'config'; New-Item -ItemType Directory $ConfigDir | Out-Null
    $Settings = Get-Content (Join-Path $ProjectDir 'data\Saved\Config\LinuxServer\PalWorldSettings.ini') -Raw
    $Settings = [regex]::Replace($Settings, '(AdminPassword|ServerPassword)="[^"]*"', '$1=""')
    Set-Content (Join-Path $ConfigDir 'PalWorldSettings.ini') $Settings -Encoding UTF8
    Get-Content (Join-Path $ProjectDir '.env') | Where-Object { $_ -notmatch '(?i)(TOKEN|PASSWORD|SECRET|KEY)\s*=' } | Set-Content (Join-Path $StageDir 'server.env') -Encoding UTF8
    [pscustomobject]@{schemaVersion=1;createdAt=(Get-Date).ToString('o');backup=$Backup.Name;secretsExcluded=$true}|ConvertTo-Json|Set-Content (Join-Path $StageDir 'manifest.json') -Encoding UTF8
    $Target=Join-Path $ExportDir ('palops-migration-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')
    Compress-Archive -Path (Join-Path $StageDir '*') -DestinationPath $Target -CompressionLevel Optimal
    Write-Host $Target
} finally { Remove-Item $StageDir -Recurse -Force -ErrorAction SilentlyContinue }
