$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $ProjectDir 'config\discord.env'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null

$SecureToken = Read-Host 'Enter the Discord Bot Token' -AsSecureString
$Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
try {
    $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
}

$ChannelId = Read-Host 'Enter the Discord status Channel ID'
if (-not $Token -or $Token.Contains("`r") -or $Token.Contains("`n")) {
    throw 'Invalid Discord Bot Token.'
}
if ($ChannelId -notmatch '^\d{15,25}$') {
    throw 'Invalid Discord Channel ID.'
}

$Encoding = New-Object System.Text.UTF8Encoding($false)
$Content = "DISCORD_ENABLED=true`nDISCORD_BOT_TOKEN=$Token`nDISCORD_CHANNEL_ID=$ChannelId`n"
[System.IO.File]::WriteAllText($ConfigPath, $Content, $Encoding)

Write-Host 'Discord Bot configuration saved.'
Write-Host 'Sending the initial offline status message...'
& "$PSScriptRoot\discord-status.ps1" -Status Offline -Detail 'Discord integration configured.'
Write-Host 'Setup completed. Pin the new status message in Discord.'
