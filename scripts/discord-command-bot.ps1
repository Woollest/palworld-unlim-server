param([switch]$FunctionsOnly)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
$RuntimeDir = Join-Path $ProjectDir 'runtime'
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

function Parse-PalOpsCommand {
    param([string]$Content, [string]$Prefix = '!palops')
    if (-not $Content) { return $null }
    $Trimmed = $Content.Trim()
    if (-not $Trimmed.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    $Remainder = $Trimmed.Substring($Prefix.Length).Trim()
    if (-not $Remainder) { return [pscustomobject]@{ name = 'help'; argument = '' } }
    $Parts = $Remainder.Split(@(' '), 2, [StringSplitOptions]::RemoveEmptyEntries)
    return [pscustomobject]@{ name = $Parts[0].ToLowerInvariant(); argument = if ($Parts.Count -gt 1) { $Parts[1].Trim() } else { '' } }
}

function Test-AdministratorPermissions {
    param([string[]]$RoleIds, [object[]]$GuildRoles, [string]$GuildId)
    [uint64]$Permissions = 0
    foreach ($Role in $GuildRoles) {
        if ($Role.id -eq $GuildId -or $RoleIds -contains $Role.id) { $Permissions = $Permissions -bor [uint64]$Role.permissions }
    }
    return ($Permissions -band [uint64]8) -ne 0
}

if ($FunctionsOnly) { return }

$ConfigPath = Join-Path $ProjectDir 'config\discord.env'
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw 'config/discord.env does not exist.' }
$Config = @{}
foreach ($Line in Get-Content -LiteralPath $ConfigPath) {
    if ($Line -match '^([^#=]+)=(.*)$') { $Config[$Matches[1].Trim()] = $Matches[2].Trim() }
}
if ($Config['DISCORD_ENABLED'] -ne 'true') { return }
$Token = $Config['DISCORD_BOT_TOKEN']
$ChannelId = if ($Config['DISCORD_COMMAND_CHANNEL_ID']) { $Config['DISCORD_COMMAND_CHANNEL_ID'] } else { $Config['DISCORD_CHANNEL_ID'] }
$Prefix = if ($Config['DISCORD_COMMAND_PREFIX']) { $Config['DISCORD_COMMAND_PREFIX'] } else { '!palops' }
if (-not $Token -or $ChannelId -notmatch '^\d{15,25}$') { throw 'Discord command token or channel is not configured.' }

$CreatedNew = $false
$BotMutex = [Threading.Mutex]::new($true, 'Local\PalOpsDiscordCommands', [ref]$CreatedNew)
if (-not $CreatedNew) { $BotMutex.Dispose(); return }
$PidPath = Join-Path $RuntimeDir 'discord-command-bot.pid'
Set-Content -LiteralPath $PidPath -Value $PID -Encoding Ascii
$LastMessagePath = Join-Path $RuntimeDir "discord-command-last-message-$ChannelId"
$ConfirmationPath = Join-Path $RuntimeDir 'discord-command-confirmations.json'
$Headers = @{ Authorization = "Bot $Token"; 'User-Agent' = 'PalOps/1.0' }
$ApiBase = 'https://discord.com/api/v10'
$ConsecutiveFailures = 0

function Invoke-DiscordCommandApi {
    param([string]$Method, [string]$Uri, $Body = $null)
    $Parameters = @{ Method = $Method; Uri = $Uri; Headers = $Headers; TimeoutSec = 15 }
    if ($null -ne $Body) {
        $Parameters.ContentType = 'application/json; charset=utf-8'
        # Windows PowerShell 5 may otherwise submit JSON using its legacy
        # string encoding, which Discord rejects with HTTP 400.
        $Json = $Body | ConvertTo-Json -Depth 8 -Compress
        $Parameters.Body = [Text.Encoding]::UTF8.GetBytes($Json)
    }
    return Invoke-RestMethod @Parameters
}

function Send-CommandReply {
    param([string]$Message)
    if ($Message.Length -gt 1900) { $Message = $Message.Substring(0, 1900) }
    Invoke-DiscordCommandApi -Method Post -Uri "$ApiBase/channels/$ChannelId/messages" -Body @{ content = $Message; allowed_mentions = @{ parse = @() } } | Out-Null
}

function Get-LocalApi {
    param([string]$Path)
    $Port = '8765'
    $EnvPath = Join-Path $ProjectDir '.env'
    if (Test-Path -LiteralPath $EnvPath) {
        foreach ($Line in Get-Content -LiteralPath $EnvPath) { if ($Line -match '^DASHBOARD_PORT=(\d+)$') { $Port = $Matches[1] } }
    }
    return Invoke-RestMethod -Uri "http://127.0.0.1:$Port$Path" -TimeoutSec 10
}

function Start-LocalAction {
    param([ValidateSet('backup', 'restart')][string]$Action)
    $Port = '8765'
    $EnvPath = Join-Path $ProjectDir '.env'
    if (Test-Path -LiteralPath $EnvPath) { foreach ($Line in Get-Content -LiteralPath $EnvPath) { if ($Line -match '^DASHBOARD_PORT=(\d+)$') { $Port = $Matches[1] } } }
    return Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port/api/actions/$Action" -Headers @{ Origin = "http://127.0.0.1:$Port" } -TimeoutSec 10
}

function Get-Confirmations {
    if (-not (Test-Path -LiteralPath $ConfirmationPath)) { return @() }
    try { return @(Get-Content -LiteralPath $ConfirmationPath -Raw | ConvertFrom-Json | Where-Object { [datetime]$_.expiresAt -gt (Get-Date) }) } catch { return @() }
}

function Save-Confirmations { param([object[]]$Values) @($Values) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ConfirmationPath -Encoding UTF8 }

function Request-Confirmation {
    param([string]$UserId, [string]$Action)
    $Code = -join ((48..57 + 65..90) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $Value = [pscustomobject]@{ userId = $UserId; action = $Action; code = $Code; expiresAt = (Get-Date).AddMinutes(2).ToString('o') }
    Save-Confirmations -Values (@($Value) + @(Get-Confirmations) | Select-Object -First 20)
    return $Code
}

function Confirm-Action {
    param([string]$UserId, [string]$Code)
    $Values = @(Get-Confirmations)
    $Match = $Values | Where-Object { $_.userId -eq $UserId -and $_.code -ceq $Code } | Select-Object -First 1
    if (-not $Match) { return $null }
    Save-Confirmations -Values @($Values | Where-Object { $_.code -cne $Code -or $_.userId -ne $UserId })
    return $Match.action
}

try {
    $Channel = Invoke-DiscordCommandApi -Method Get -Uri "$ApiBase/channels/$ChannelId"
    $GuildId = [string]$Channel.guild_id
    if (-not $GuildId) { throw 'Discord command channel is not a guild channel.' }
    $GuildRoleResponse = Invoke-DiscordCommandApi -Method Get -Uri "$ApiBase/guilds/$GuildId/roles"
    $GuildRoles = @($GuildRoleResponse)
    if (-not (Test-Path -LiteralPath $LastMessagePath) -or (Get-Item -LiteralPath $LastMessagePath).Length -eq 0) {
        $LatestResponse = Invoke-DiscordCommandApi -Method Get -Uri "$ApiBase/channels/$ChannelId/messages?limit=1"
        $LatestMessages = @($LatestResponse)
        if ($LatestMessages.Count -and $LatestMessages[0].id) { Set-Content -LiteralPath $LastMessagePath -Value $LatestMessages[0].id -Encoding Ascii }
    }
    while ($true) {
        try {
            $LastIdText = if (Test-Path -LiteralPath $LastMessagePath) { Get-Content -LiteralPath $LastMessagePath -Raw } else { '' }
            $LastId = if ($null -ne $LastIdText) { $LastIdText.Trim() } else { '' }
            $Uri = "$ApiBase/channels/$ChannelId/messages?limit=20"
            if ($LastId) { $Uri += "&after=$LastId" }
            # Windows PowerShell 5 can keep a JSON array returned by Invoke-RestMethod
            # as one pipeline object. Assign first so PowerShell enumerates each message.
            $MessageResponse = Invoke-DiscordCommandApi -Method Get -Uri $Uri
            $Messages = @($MessageResponse) | Where-Object { $null -ne $_ -and $null -ne $_.id } | Sort-Object timestamp
            foreach ($Message in $Messages) {
                Set-Content -LiteralPath $LastMessagePath -Value $Message.id -Encoding Ascii
                if ($Message.author.bot) { continue }
                $Command = Parse-PalOpsCommand -Content ([string]$Message.content) -Prefix $Prefix
                if (-not $Command) { continue }
                $IsAdministrator = Test-AdministratorPermissions -RoleIds @($Message.member.roles) -GuildRoles $GuildRoles -GuildId $GuildId
                switch ($Command.name) {
                    'help' { Send-CommandReply "**PalOps commands**`n`$Prefix status - server status`n`$Prefix players - online players`n`$Prefix maintenance - scheduled maintenance`nAdministrator: `$Prefix backup / restart / confirm CODE" }
                    'status' {
                        $Status = Get-LocalApi -Path '/api/status'
                        Send-CommandReply "**Palworld:** $($Status.server.status) | **Players:** $($Status.server.players)/$($Status.server.maxPlayers) | **Unlim:** $($Status.unlim.status) | **Diagnosis:** $($Status.insights.state)"
                    }
                    'players' {
                        $Status = Get-LocalApi -Path '/api/status'; $Names = @($Status.server.playerNames)
                        Send-CommandReply $(if ($Names.Count) { "**Online players ($($Names.Count)):** " + ($Names -join ', ') } else { '**Online players:** none' })
                    }
                    'maintenance' {
                        $Schedules = @((Get-LocalApi -Path '/api/maintenance').schedules | Where-Object status -eq 'scheduled' | Select-Object -First 5)
                        Send-CommandReply $(if ($Schedules.Count) { "**Scheduled maintenance**`n" + (($Schedules | ForEach-Object { "- $($_.operation): $($_.runAt)" }) -join "`n") } else { '**Scheduled maintenance:** none' })
                    }
                    { $_ -in @('backup', 'restart') } {
                        if (-not $IsAdministrator) { Send-CommandReply 'This command requires the Discord Administrator permission.'; break }
                        $Code = Request-Confirmation -UserId $Message.author.id -Action $Command.name
                        Send-CommandReply "Confirm **$($Command.name)** within 2 minutes: `$Prefix confirm $Code"
                    }
                    'confirm' {
                        if (-not $IsAdministrator) { Send-CommandReply 'This command requires the Discord Administrator permission.'; break }
                        $Action = Confirm-Action -UserId $Message.author.id -Code $Command.argument.ToUpperInvariant()
                        if (-not $Action) { Send-CommandReply 'The confirmation code is invalid or expired.'; break }
                        Start-LocalAction -Action $Action | Out-Null
                        Send-CommandReply "Accepted: **$Action**. Progress is available in PalOps."
                    }
                    default { Send-CommandReply "Unknown command. Use `$Prefix help." }
                }
            }
        }
        catch {
            $ConsecutiveFailures++
            $BackoffSeconds = [Math]::Min(300, 5 * [Math]::Pow(2, [Math]::Min(6, $ConsecutiveFailures - 1)))
            Add-Content -LiteralPath (Join-Path $ProjectDir 'logs\discord-command-error.log') -Value "[$(Get-Date -Format o)] retry in $([int]$BackoffSeconds)s, line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
            Start-Sleep -Seconds ([int]$BackoffSeconds)
            continue
        }
        $ConsecutiveFailures = 0
        Start-Sleep -Seconds 5
    }
}
finally {
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
    $BotMutex.ReleaseMutex(); $BotMutex.Dispose()
}
