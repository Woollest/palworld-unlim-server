$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$PSScriptRoot\common.ps1"

$LogsDir = Join-Path $ProjectDir 'logs'
$ArchiveDir = Join-Path $LogsDir 'archive'
$MetricsPath = Join-Path $LogsDir 'health-metrics.csv'
$CompressAfterDays = [int](Get-ProjectSetting -Name 'LOG_COMPRESS_AFTER_DAYS' -Default '7')
$LogRetentionDays = [int](Get-ProjectSetting -Name 'LOG_RETENTION_DAYS' -Default '90')
$MetricsRetentionDays = [int](Get-ProjectSetting -Name 'METRICS_RETENTION_DAYS' -Default '30')
New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null

$CompressBefore = (Get-Date).AddDays(-$CompressAfterDays)
Get-ChildItem -LiteralPath $LogsDir -Filter 'palworld-*.log' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $CompressBefore } | ForEach-Object {
        $ZipPath = Join-Path $ArchiveDir ($_.BaseName + '.zip')
        if (-not (Test-Path -LiteralPath $ZipPath)) {
            Compress-Archive -LiteralPath $_.FullName -DestinationPath $ZipPath -CompressionLevel Optimal
        }
        if ((Test-Path -LiteralPath $ZipPath) -and (Get-Item -LiteralPath $ZipPath).Length -gt 0) {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    }

$DeleteBefore = (Get-Date).AddDays(-$LogRetentionDays)
Get-ChildItem -LiteralPath $ArchiveDir -Filter '*.zip' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $DeleteBefore } |
    Remove-Item -Force

if (Test-Path -LiteralPath $MetricsPath) {
    $KeepAfter = (Get-Date).AddDays(-$MetricsRetentionDays)
    $Rows = @(Import-Csv -LiteralPath $MetricsPath | Where-Object {
        try { [datetime]$_.timestamp -ge $KeepAfter } catch { $false }
    })
    $TempPath = "$MetricsPath.tmp"
    if ($Rows.Count -gt 0) {
        $Rows | Export-Csv -LiteralPath $TempPath -NoTypeInformation -Encoding UTF8
        Move-Item -LiteralPath $TempPath -Destination $MetricsPath -Force
    }
}

Write-Host 'Log and metrics maintenance completed.'
