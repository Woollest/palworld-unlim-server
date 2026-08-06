param(
    [Parameter(Mandatory = $true)][ValidateSet('Maintenance', 'Information', 'ServiceError', 'ServiceRecovered', 'BackupSuccess', 'BackupFailure')][string]$Type,
    [Parameter(Mandatory = $true)][string]$Message
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $ProjectDir 'config\discord.env'
if (-not (Test-Path -LiteralPath $ConfigPath)) { return }
$Config = @{}
foreach ($Line in Get-Content -LiteralPath $ConfigPath) {
    if ($Line -match '^([^#=]+)=(.*)$') { $Config[$Matches[1].Trim()] = $Matches[2].Trim() }
}
if ($Config['DISCORD_ENABLED'] -ne 'true') { return }
$Token = $Config['DISCORD_BOT_TOKEN']
$AdminLogChannelId = if ($Config['DISCORD_ADMIN_LOG_CHANNEL_ID']) { $Config['DISCORD_ADMIN_LOG_CHANNEL_ID'] } elseif ($Config['DISCORD_BACKUP_CHANNEL_ID']) { $Config['DISCORD_BACKUP_CHANNEL_ID'] } else { $Config['DISCORD_ALERT_CHANNEL_ID'] }
$ChannelId = if ($Type -eq 'Maintenance') {
    $Config['DISCORD_ANNOUNCEMENT_CHANNEL_ID']
} elseif ($AdminLogChannelId) {
    $AdminLogChannelId
} else {
    $Config['DISCORD_CHANNEL_ID']
}
if (-not $ChannelId) { Write-Warning 'The Discord notification channel is not configured.'; return }
if (-not $Token) { throw 'DISCORD_BOT_TOKEN is missing.' }
$Appearance = switch ($Type) {
    'Maintenance'      { @{ Title = 'Maintenance Notice'; Color = 16705372 } }
    'ServiceError'     { @{ Title = 'Server Problem Detected'; Color = 15548997 } }
    'ServiceRecovered' { @{ Title = 'Server Service Recovered'; Color = 5763719 } }
    'BackupSuccess'    { @{ Title = 'Backup Completed'; Color = 5763719 } }
    'BackupFailure'    { @{ Title = 'Backup Failed'; Color = 15548997 } }
    default            { @{ Title = 'Server Information'; Color = 3447003 } }
}
$Title = $Appearance.Title
$Color = $Appearance.Color
$Body = @{ embeds = @(@{ title = $Title; description = $Message; color = $Color; timestamp = (Get-Date).ToUniversalTime().ToString('o'); footer = @{ text = 'Palworld Server Bot' } }); allowed_mentions = @{ parse = @() } } | ConvertTo-Json -Depth 7
$Headers = @{ Authorization = "Bot $Token"; 'User-Agent' = 'DiscordBot (https://github.com/openai/codex, 1.0)' }
$LastError = $null
for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
    try {
        Invoke-RestMethod -Method Post -Uri "https://discord.com/api/v10/channels/$ChannelId/messages" -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $Body | Out-Null
        return
    }
    catch {
        $LastError = $_
        if ($Attempt -lt 3) { Start-Sleep -Seconds ([math]::Pow(2, $Attempt)) }
    }
}
throw $LastError
