$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

$LogsDir = Join-Path $ProjectDir 'logs'
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
$TranscriptPath = Join-Path $LogsDir 'autostart.log'
Start-Transcript -LiteralPath $TranscriptPath -Append | Out-Null

try {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Automatic startup began."

    $DockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $DockerCommand) { throw 'Docker CLI was not found.' }
    function Test-DockerEngineReady {
        $PreviousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $DockerCommand.Source info 1>$null 2>$null
            return $LASTEXITCODE -eq 0
        }
        finally {
            $ErrorActionPreference = $PreviousPreference
        }
    }
    $Timeout = [int](Get-ProjectSetting -Name 'AUTO_START_DOCKER_TIMEOUT_SECONDS' -Default '600')
    $DockerDesktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    $DockerReady = Test-DockerEngineReady
    if (-not $DockerReady) {
        if (-not (Test-Path -LiteralPath $DockerDesktop)) { throw "Docker Desktop was not found: $DockerDesktop" }
        Write-Host 'Starting Docker Desktop...'
        Start-Process -FilePath $DockerDesktop -WindowStyle Hidden
    }

    $Deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $Deadline) {
        if (Test-DockerEngineReady) { break }
        Start-Sleep -Seconds 10
    }
    if (-not (Test-DockerEngineReady)) { throw "Docker Desktop was not ready within $Timeout seconds." }

    Write-Host 'Docker Desktop is ready. Starting Palworld and Unlim...'
    & "$PSScriptRoot\start.ps1"
    if ($LASTEXITCODE -ne 0) { throw "start.ps1 failed with exit code $LASTEXITCODE." }
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Automatic startup completed."
}
catch {
    $Message = "Automatic startup failed: $($_.Exception.Message)"
    Write-Error $Message
    Invoke-DiscordStatusSafe -Status Error -Detail $Message
    Invoke-DiscordNotificationSafe -Type ServiceError -Message $Message
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
