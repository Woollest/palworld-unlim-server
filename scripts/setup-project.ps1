param(
    [switch]$Start,
    [switch]$SkipDockerValidation
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir

$Directories = @('data/Saved/Config/LinuxServer', 'backups', 'logs', 'recovery', 'runtime', 'reports', 'work', 'config')
foreach ($Directory in $Directories) {
    New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir $Directory) | Out-Null
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir '.env'))) {
    Copy-Item -LiteralPath (Join-Path $ProjectDir '.env.example') -Destination (Join-Path $ProjectDir '.env')
    Write-Host 'Created .env from .env.example.'
}

$DiscordConfig = Join-Path $ProjectDir 'config/discord.env'
if (-not (Test-Path -LiteralPath $DiscordConfig)) {
    Copy-Item -LiteralPath (Join-Path $ProjectDir 'config/discord.env.example') -Destination $DiscordConfig
    Write-Host 'Created config/discord.env from its example.'
}

$WorldSettings = Join-Path $ProjectDir 'data/Saved/Config/LinuxServer/PalWorldSettings.ini'
if (-not (Test-Path -LiteralPath $WorldSettings)) {
    Copy-Item -LiteralPath (Join-Path $ProjectDir 'config/PalWorldSettings.ini.example') -Destination $WorldSettings
    Write-Host 'Created the initial PalWorldSettings.ini from the public template.'
}

if (-not $SkipDockerValidation) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker was not found.' }
    & docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose configuration validation failed.' }
    Write-Host 'Docker Compose configuration is valid.'
}

Write-Host ''
Write-Host 'Initial project setup completed.' -ForegroundColor Green
Write-Host 'Review .env, config/discord.env and data/Saved/Config/LinuxServer/PalWorldSettings.ini before inviting players.'

if ($Start) {
    & "$PSScriptRoot\start.ps1"
    exit $LASTEXITCODE
}
