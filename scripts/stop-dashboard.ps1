$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$PidPath = Join-Path $ProjectDir 'runtime\dashboard.pid'
if (-not (Test-Path -LiteralPath $PidPath)) { return }
$PidValue = (Get-Content -LiteralPath $PidPath -Raw).Trim()
if ($PidValue -notmatch '^\d+$') { throw 'Dashboard PID file is invalid.' }
$Process = Get-CimInstance Win32_Process -Filter "ProcessId = $PidValue" -ErrorAction SilentlyContinue
if ($Process -and $Process.Name -in @('powershell.exe', 'pwsh.exe') -and $Process.CommandLine -like '*dashboard.ps1*') {
    Stop-Process -Id ([int]$PidValue) -Force
}
Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
