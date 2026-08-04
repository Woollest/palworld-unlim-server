param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Online', 'Offline')]
    [string]$State,
    [string]$ConnectionKey = ''
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $ProjectDir 'config\discord.env'
$MessageIdPath = Join-Path $ProjectDir 'runtime\discord-connection-message-id'
if (-not (Test-Path -LiteralPath $ConfigPath)) { return }

$Config = @{}
foreach ($Line in Get-Content -LiteralPath $ConfigPath) {
    if ($Line -match '^([^#=]+)=(.*)$') { $Config[$Matches[1].Trim()] = $Matches[2].Trim() }
}
if ($Config['DISCORD_ENABLED'] -ne 'true') { return }
if ($Config['DISCORD_CONNECTION_CHANNEL_ALLOW_EVERYONE'] -ne 'true') {
    throw 'Connection channel publishing has not been explicitly approved.'
}
$Token = $Config['DISCORD_BOT_TOKEN']
$ChannelId = $Config['DISCORD_CONNECTION_CHANNEL_ID']
if (-not $Token -or -not $ChannelId) { throw 'Discord connection channel configuration is incomplete.' }
if ($State -eq 'Online' -and -not $ConnectionKey) { throw 'Unlim connection key is missing.' }

$ProjectConfig = @{}
foreach ($Line in Get-Content -LiteralPath (Join-Path $ProjectDir '.env')) {
    if ($Line -match '^([^#=]+)=(.*)$') { $ProjectConfig[$Matches[1].Trim()] = $Matches[2].Trim() }
}
$Port = if ($ProjectConfig['PALWORLD_PORT']) { $ProjectConfig['PALWORLD_PORT'] } else { '8211' }
$Players = if ($ProjectConfig['MAX_PLAYERS']) { $ProjectConfig['MAX_PLAYERS'] } else { '8' }
$Now = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'

if ($State -eq 'Online') {
    $Description = '**ONLINE - You can join now.**'
    $Color = 5763719
    $Fields = @(
        @{ name = 'Platform'; value = 'Steam'; inline = $true },
        @{ name = 'Maximum players'; value = $Players; inline = $true },
        @{ name = 'Unlim connection key'; value = "``$ConnectionKey``"; inline = $false },
        @{ name = 'Palworld address'; value = "``127.0.0.1:$Port``"; inline = $false },
        @{ name = 'Last updated'; value = $Now; inline = $false }
    )
}
else {
    $Description = '**OFFLINE - The server is currently unavailable.**'
    $Color = 15548997
    $Fields = @(@{ name = 'Last updated'; value = $Now; inline = $false })
}

$Body = @{ embeds = @(@{ title = 'Palworld Connection Information'; description = $Description; color = $Color; fields = $Fields; footer = @{ text = 'Do not share the connection key outside this Discord server.' } }); allowed_mentions = @{ parse = @() } } | ConvertTo-Json -Depth 8
$Headers = @{ Authorization = "Bot $Token"; 'User-Agent' = 'DiscordBot (https://github.com/openai/codex, 1.0)' }
$ApiBase = 'https://discord.com/api/v10'

function Invoke-DiscordRequest {
    param([string]$Method, [string]$Uri)
    $LastError = $null
    for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
        try { return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $Body }
        catch { $LastError = $_; if ($Attempt -lt 3) { Start-Sleep -Seconds ([math]::Pow(2, $Attempt)) } }
    }
    throw $LastError
}

$MessageId = ''
if (Test-Path -LiteralPath $MessageIdPath) { $MessageId = (Get-Content -LiteralPath $MessageIdPath -Raw).Trim() }
if ($MessageId) {
    try {
        Invoke-DiscordRequest -Method Patch -Uri "$ApiBase/channels/$ChannelId/messages/$MessageId" | Out-Null
        return
    }
    catch {
        $StatusCode = $null
        if ($_.Exception.Response) { $StatusCode = [int]$_.Exception.Response.StatusCode }
        if ($StatusCode -ne 404) { throw }
    }
}
$Response = Invoke-DiscordRequest -Method Post -Uri "$ApiBase/channels/$ChannelId/messages"
Set-Content -LiteralPath $MessageIdPath -Value $Response.id -Encoding Ascii
