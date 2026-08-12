param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Starting', 'Online', 'Maintenance', 'Offline', 'Error')]
    [string]$Status,

    [string]$Detail = '',

    [int]$PlayerCount = -1
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $ProjectDir 'config\discord.env'
$MessageIdPath = Join-Path $ProjectDir 'runtime\discord-status-message-id'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    return
}

$Config = @{}
foreach ($Line in Get-Content -LiteralPath $ConfigPath) {
    $Trimmed = $Line.Trim()
    if (-not $Trimmed -or $Trimmed.StartsWith('#')) { continue }
    $Parts = $Trimmed.Split('=', 2)
    if ($Parts.Count -eq 2) {
        $Config[$Parts[0].Trim()] = $Parts[1].Trim()
    }
}

if ($Config['DISCORD_ENABLED'] -ne 'true') { return }

$Token = $Config['DISCORD_BOT_TOKEN']
$ChannelId = $Config['DISCORD_CHANNEL_ID']
if (-not $Token -or -not $ChannelId) {
    throw 'DISCORD_BOT_TOKEN or DISCORD_CHANNEL_ID is missing.'
}

$ProjectConfig = @{}
$ProjectEnvPath = Join-Path $ProjectDir '.env'
if (Test-Path -LiteralPath $ProjectEnvPath) {
    foreach ($Line in Get-Content -LiteralPath $ProjectEnvPath) {
        if ($Line -match '^([^#=]+)=(.*)$') {
            $ProjectConfig[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
}
$PlayerLimit = if ($ProjectConfig['MAX_PLAYERS']) { $ProjectConfig['MAX_PLAYERS'] } else { '8' }
$GamePort = if ($ProjectConfig['PALWORLD_PORT']) { $ProjectConfig['PALWORLD_PORT'] } else { '8211' }

$Now = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
$StatusData = switch ($Status) {
    'Starting' {
        @{ Title = 'Palworld Server Status'; Description = '**STARTING - The server is preparing.**'; Color = 3447003 }
    }
    'Online' {
        @{ Title = 'Palworld Server Status'; Description = '**ONLINE - You can join now.**'; Color = 5763719 }
    }
    'Maintenance' {
        @{ Title = 'Palworld Server Status'; Description = '**MAINTENANCE - Backup and shutdown in progress.**'; Color = 16705372 }
    }
    'Offline' {
        @{ Title = 'Palworld Server Status'; Description = '**OFFLINE - The server is stopped.**'; Color = 15548997 }
    }
    'Error' {
        @{ Title = 'Palworld Server Status'; Description = '**ERROR - Administrator attention is required.**'; Color = 10038562 }
    }
}

$Fields = @(
    @{ name = 'Platform'; value = 'Steam'; inline = $true },
    @{ name = 'Maximum players'; value = $PlayerLimit; inline = $true },
    @{ name = 'Address'; value = "127.0.0.1:$GamePort"; inline = $false },
    @{ name = 'Last updated'; value = $Now; inline = $false }
)
if ($PlayerCount -ge 0) {
    $Fields = @(
        @{ name = 'Players online'; value = "$PlayerCount / $PlayerLimit"; inline = $true },
        @{ name = 'Platform'; value = 'Steam'; inline = $true },
        @{ name = 'Address'; value = "127.0.0.1:$GamePort"; inline = $false },
        @{ name = 'Last updated'; value = $Now; inline = $false }
    )
}
if ($Detail) {
    $Fields += @{ name = 'Details'; value = $Detail; inline = $false }
}

$Body = @{
    embeds = @(
        @{
            title = $StatusData.Title
            description = $StatusData.Description
            color = $StatusData.Color
            fields = $Fields
            footer = @{ text = 'Updated automatically by Palworld Server Bot' }
        }
    )
    allowed_mentions = @{ parse = @() }
} | ConvertTo-Json -Depth 8

$Headers = @{
    Authorization = "Bot $Token"
    'User-Agent' = 'DiscordBot (https://github.com/openai/codex, 1.0)'
}
$ApiBase = 'https://discord.com/api/v10'

function Invoke-DiscordApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$JsonBody
    )
    $LastError = $null
    for ($Attempt = 1; $Attempt -le 2; $Attempt++) {
        try {
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $JsonBody -TimeoutSec 5
        }
        catch {
            $LastError = $_
            if ($Attempt -lt 2) {
                Start-Sleep -Seconds 2
            }
        }
    }
    throw $LastError
}

$MessageId = $null
if (Test-Path -LiteralPath $MessageIdPath) {
    $MessageId = (Get-Content -LiteralPath $MessageIdPath -Raw).Trim()
}

if ($MessageId) {
    try {
        Invoke-DiscordApi -Method Patch -Uri "$ApiBase/channels/$ChannelId/messages/$MessageId" -JsonBody $Body | Out-Null
        return
    }
    catch {
        $StatusCode = $null
        if ($_.Exception.Response) { $StatusCode = [int]$_.Exception.Response.StatusCode }
        if ($StatusCode -ne 404) { throw }
        Write-Warning 'The previous Discord status message no longer exists. Creating a new one.'
    }
}

$Response = Invoke-DiscordApi -Method Post -Uri "$ApiBase/channels/$ChannelId/messages" -JsonBody $Body
Set-Content -LiteralPath $MessageIdPath -Value $Response.id -Encoding Ascii
