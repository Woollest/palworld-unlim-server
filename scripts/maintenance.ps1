param(
    [Parameter(Mandatory = $true)][ValidateSet('Schedule', 'Execute', 'Cancel')][string]$Mode,
    [ValidateSet('restart', 'update', 'backup', 'shutdown')][string]$Operation = 'restart',
    [string]$RunAt = '',
    [ValidateRange(1, 60)][int]$WarningMinutes = 10,
    [ValidatePattern('^[a-z0-9-]{8,40}$')][string]$Id = ''
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
. "$PSScriptRoot\common.ps1"
$StatePath = Join-Path $ProjectDir 'runtime\maintenance-schedules.json'

function Get-Schedules {
    if (-not (Test-Path -LiteralPath $StatePath)) { return @() }
    try { return @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) } catch { return @() }
}

function Save-Schedules {
    param([object[]]$Schedules)
    $TemporaryPath = "$StatePath.tmp"
    @($Schedules) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $TemporaryPath -Encoding UTF8
    Move-Item -LiteralPath $TemporaryPath -Destination $StatePath -Force
}

function Set-ScheduleState {
    param([string]$ScheduleId, [string]$Status, [string]$Message = '')
    $Schedules = @(Get-Schedules)
    $Schedule = $Schedules | Where-Object id -eq $ScheduleId | Select-Object -First 1
    if (-not $Schedule) { throw 'Maintenance schedule was not found.' }
    $Schedule.status = $Status
    $Schedule.updatedAt = (Get-Date).ToString('o')
    if ($Message) { $Schedule | Add-Member -NotePropertyName message -NotePropertyValue $Message -Force }
    Save-Schedules -Schedules $Schedules
    return $Schedule
}

if ($Mode -eq 'Schedule') {
    if (-not $RunAt) { throw 'RunAt is required.' }
    $RunAtValue = [datetimeoffset]::Parse($RunAt)
    if ($RunAtValue -lt (Get-Date).AddMinutes(1)) { throw 'Maintenance must be scheduled at least one minute in the future.' }
    if ($RunAtValue -gt (Get-Date).AddDays(30)) { throw 'Maintenance cannot be scheduled more than 30 days ahead.' }
    $Id = ((Get-Date -Format 'yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)).ToLowerInvariant()
    $NoticeAt = $RunAtValue.AddMinutes(-$WarningMinutes)
    if ($NoticeAt -lt (Get-Date).AddSeconds(10)) { $NoticeAt = (Get-Date).AddSeconds(10) }
    $TaskName = "PalOps-Maintenance-$Id"
    $HiddenRunner = Join-Path $PSScriptRoot 'run-hidden.vbs'
    $WScript = "$env:SystemRoot\System32\wscript.exe"
    $Action = New-ScheduledTaskAction -Execute $WScript -Argument "//B //Nologo `"$HiddenRunner`" `"$PSCommandPath`" -Mode Execute -Id $Id" -WorkingDirectory $ProjectDir
    $Trigger = New-ScheduledTaskTrigger -Once -At $NoticeAt.LocalDateTime
    $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
    $Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "PalOps scheduled $Operation maintenance." -Force | Out-Null
    $Schedule = [pscustomobject]@{ id = $Id; operation = $Operation; runAt = $RunAtValue.ToString('o'); noticeAt = $NoticeAt.ToString('o'); warningMinutes = $WarningMinutes; status = 'scheduled'; taskName = $TaskName; createdAt = (Get-Date).ToString('o'); updatedAt = (Get-Date).ToString('o') }
    $Schedules = @($Schedule) + @(Get-Schedules) | Select-Object -First 30
    Save-Schedules -Schedules $Schedules
    $Schedule | ConvertTo-Json -Compress
    return
}

if (-not $Id) { throw 'Id is required.' }
$Selected = Get-Schedules | Where-Object id -eq $Id | Select-Object -First 1
if (-not $Selected) { throw 'Maintenance schedule was not found.' }

if ($Mode -eq 'Cancel') {
    if ($Selected.status -ne 'scheduled') { throw 'Only a pending maintenance schedule can be cancelled.' }
    if (Get-ScheduledTask -TaskName $Selected.taskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $Selected.taskName -Confirm:$false }
    Set-ScheduleState -ScheduleId $Id -Status 'cancelled' -Message 'Cancelled by the administrator.' | ConvertTo-Json -Compress
    return
}

Set-ScheduleState -ScheduleId $Id -Status 'running' | Out-Null
try {
    $RunAtValue = [datetimeoffset]::Parse($Selected.runAt)
    $MinutesRemaining = [math]::Max(1, [math]::Ceiling(($RunAtValue - [datetimeoffset](Get-Date)).TotalMinutes))
    $Notice = "Scheduled Palworld maintenance begins in $MinutesRemaining minute(s): $($Selected.operation)."
    Invoke-DiscordNotificationSafe -Type Maintenance -Message $Notice
    try { Invoke-PalworldApi -Method Post -Path 'announce' -Body @{ message = $Notice } | Out-Null } catch {}
    while ([datetimeoffset](Get-Date) -lt $RunAtValue) {
        $RemainingSeconds = [math]::Ceiling(($RunAtValue - [datetimeoffset](Get-Date)).TotalSeconds)
        Start-Sleep -Seconds ([math]::Min(30, [math]::Max(1, $RemainingSeconds)))
    }
    switch ($Selected.operation) {
        'restart' { & "$PSScriptRoot\shutdown.ps1"; if ($LASTEXITCODE -ne 0) { throw 'Safe shutdown failed.' }; & "$PSScriptRoot\start.ps1" }
        'update' { & "$PSScriptRoot\update-server.ps1" -NonInteractive }
        'backup' { & "$PSScriptRoot\backup.ps1" }
        'shutdown' { & "$PSScriptRoot\shutdown.ps1" }
    }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Maintenance operation exited with code $LASTEXITCODE." }
    Set-ScheduleState -ScheduleId $Id -Status 'succeeded' -Message 'Maintenance completed successfully.' | Out-Null
    Invoke-DiscordNotificationSafe -Type Information -Message "Scheduled Palworld maintenance completed: $($Selected.operation)."
}
catch {
    Set-ScheduleState -ScheduleId $Id -Status 'failed' -Message $_.Exception.Message | Out-Null
    Invoke-DiscordNotificationSafe -Type ServiceError -Message "Scheduled Palworld maintenance failed: $($_.Exception.Message)"
    throw
}
