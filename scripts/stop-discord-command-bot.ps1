$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$PidPath = Join-Path $ProjectDir 'runtime\discord-command-bot.pid'
if (-not (Test-Path -LiteralPath $PidPath)) { return }
$PidValue = (Get-Content -LiteralPath $PidPath -Raw).Trim()
if ($PidValue -notmatch '^\d+$') { throw 'Discord command bot PID file is invalid.' }
$Process = Get-CimInstance Win32_Process -Filter "ProcessId = $PidValue" -ErrorAction SilentlyContinue
if ($Process -and $Process.Name -in @('powershell.exe', 'pwsh.exe') -and $Process.CommandLine -like '*discord-command-bot.ps1*') { Stop-Process -Id ([int]$PidValue) -Force }
Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
