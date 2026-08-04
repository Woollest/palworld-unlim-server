$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

$CurrentImage = Get-ProjectSetting -Name 'PALWORLD_IMAGE'
$CurrentTag = ($CurrentImage -split ':')[-1]
$Token = (Invoke-RestMethod -Uri 'https://ghcr.io/token?scope=repository:pocketpairjp/palserver:pull' -Headers @{ 'User-Agent' = 'Palworld-Server-Monitor' }).token
$Tags = (Invoke-RestMethod -Uri 'https://ghcr.io/v2/pocketpairjp/palserver/tags/list' -Headers @{ Authorization = "Bearer $Token"; 'User-Agent' = 'Palworld-Server-Monitor' }).tags
$Versions = @($Tags | Where-Object { $_ -match '^v?\d+\.\d+\.\d+\.\d+$' } | ForEach-Object { [pscustomobject]@{ Tag = $_; Version = [version]($_ -replace '^v') } } | Sort-Object Version -Descending)
if ($Versions.Count -eq 0) { throw 'No versioned tags were returned by the official registry.' }
$LatestTag = $Versions[0].Tag
$LatestVersion = $Versions[0].Version
$CurrentVersion = [version]($CurrentTag -replace '^v')
$UpdateStatusPath = Join-Path $ProjectDir 'runtime\update-status.json'
[pscustomobject]@{
    checkedAt = (Get-Date).ToString('o')
    currentTag = $CurrentTag
    latestTag = $LatestTag
    available = $LatestVersion -gt $CurrentVersion
} | ConvertTo-Json -Compress | Set-Content -LiteralPath $UpdateStatusPath -Encoding UTF8
$StatePath = Join-Path $ProjectDir 'runtime\version-notified'
if ($LatestVersion -gt $CurrentVersion) {
    $AlreadyNotified = if (Test-Path -LiteralPath $StatePath) { (Get-Content -LiteralPath $StatePath -Raw).Trim() } else { '' }
    if ($AlreadyNotified -ne $LatestTag) {
        Invoke-DiscordNotificationSafe -Type Information -Message "A new official Palworld server image is available: $LatestTag (current: $CurrentTag). Back up and review compatibility before updating."
        Set-Content -LiteralPath $StatePath -Value $LatestTag -Encoding Ascii
    }
}
