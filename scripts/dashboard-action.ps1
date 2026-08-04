param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'restart', 'shutdown', 'backup', 'check-update', 'update', 'restore', 'migration-export', 'diagnostics')]
    [string]$Action,
    [string]$Target = ''
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
$RuntimeDir = Join-Path $ProjectDir 'runtime'
$StatePath = Join-Path $RuntimeDir 'dashboard-action.json'
$HistoryPath = Join-Path $RuntimeDir 'dashboard-history.json'
$LockPath = Join-Path $RuntimeDir 'dashboard-action.lock'
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

function Set-ActionState {
    param([string]$State, [string]$StartedAt, [string]$CompletedAt = '', [string]$Message = '')
    $Value = [ordered]@{ name = $Action; state = $State; pid = $PID; startedAt = $StartedAt }
    if ($Target) { $Value.target = $Target }
    if ($CompletedAt) { $Value.completedAt = $CompletedAt }
    if ($Message) { $Value.message = $Message }
    $TemporaryPath = "$StatePath.tmp"
    $Value | ConvertTo-Json -Compress | Set-Content -LiteralPath $TemporaryPath -Encoding UTF8
    Move-Item -LiteralPath $TemporaryPath -Destination $StatePath -Force
}

function Add-ActionHistory {
    param([string]$State, [string]$StartedAt, [string]$CompletedAt, [string]$Message)
    $History = @()
    if (Test-Path -LiteralPath $HistoryPath) {
        try { $History = @(Get-Content -LiteralPath $HistoryPath -Raw | ConvertFrom-Json) } catch { $History = @() }
    }
    $Entry = [pscustomobject]@{ name = $Action; target = $Target; state = $State; startedAt = $StartedAt; completedAt = $CompletedAt; message = $Message }
    @($Entry) + @($History) | Select-Object -First 20 | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $HistoryPath -Encoding UTF8
}

$LockStream = $null
$StartedAt = (Get-Date).ToString('o')
try {
    $LockStream = [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $ReservationDeadline = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $ReservationDeadline) {
        try {
            $Reservation = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            if ([int]$Reservation.pid -eq $PID) { break }
        } catch {}
        Start-Sleep -Milliseconds 50
    }
    Set-ActionState -State 'running' -StartedAt $StartedAt
    $ScriptName = switch ($Action) { 'start' { 'start.ps1' } 'restart' { 'restart.ps1' } 'shutdown' { 'shutdown.ps1' } 'backup' { 'backup.ps1' } 'check-update' { 'check-update.ps1' } 'update' { 'update-server.ps1' } 'restore' { 'restore-backup.ps1' } 'migration-export' { 'export-migration.ps1' } 'diagnostics' { 'test-project.ps1' } }
    $ScriptArguments = if ($Action -eq 'update') { @('-NonInteractive') } elseif ($Action -eq 'restore') { @('-BackupName', $Target) } elseif ($Action -eq 'diagnostics') { @('-Online') } else { @() }
    & (Join-Path $PSScriptRoot $ScriptName) @ScriptArguments
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "$ScriptName exited with code $LASTEXITCODE." }
    $CompletedAt = (Get-Date).ToString('o')
    $Message = 'Operation completed successfully.'
    Set-ActionState -State 'succeeded' -StartedAt $StartedAt -CompletedAt $CompletedAt -Message $Message
    Add-ActionHistory -State 'succeeded' -StartedAt $StartedAt -CompletedAt $CompletedAt -Message $Message
}
catch {
    $CompletedAt = (Get-Date).ToString('o')
    $Message = $_.Exception.Message
    try { Set-ActionState -State 'failed' -StartedAt $StartedAt -CompletedAt $CompletedAt -Message $Message } catch {}
    try { Add-ActionHistory -State 'failed' -StartedAt $StartedAt -CompletedAt $CompletedAt -Message $Message } catch {}
    Write-Error $Message
    exit 1
}
finally {
    if ($LockStream) { $LockStream.Dispose() }
}
