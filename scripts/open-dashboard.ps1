$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$PSScriptRoot\common.ps1"

$Port = [int](Get-ProjectSetting -Name 'DASHBOARD_PORT' -Default '8765')
$Url = "http://127.0.0.1:$Port/"
$Ready = $false
try { $Ready = (Invoke-WebRequest -Uri "${Url}api/status" -TimeoutSec 2 -UseBasicParsing).StatusCode -eq 200 } catch {}

if (-not $Ready) {
    $LogPath = Join-Path $ProjectDir 'logs\dashboard.log'
    $ErrorPath = Join-Path $ProjectDir 'logs\dashboard-error.log'
    $Executable = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    Start-Process -FilePath $Executable -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\dashboard.ps1`"", '-NoBrowser') -WorkingDirectory $ProjectDir -WindowStyle Hidden -RedirectStandardOutput $LogPath -RedirectStandardError $ErrorPath | Out-Null
    $Deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $Deadline) {
        try {
            if ((Invoke-WebRequest -Uri "${Url}api/status" -TimeoutSec 2 -UseBasicParsing).StatusCode -eq 200) { $Ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 300
    }
}

if (-not $Ready) { throw "PalOps did not become ready. Review logs\dashboard-error.log." }
Start-Process $Url | Out-Null
