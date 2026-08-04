$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectDir
. "$PSScriptRoot\common.ps1"

$Latest = Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'backups') -Filter 'palworld-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Latest) { return }
$StampPath = Join-Path $ProjectDir 'runtime\backup-verified'
if ((Test-Path -LiteralPath $StampPath) -and (Get-Content -LiteralPath $StampPath -Raw).Trim() -eq $Latest.Name) { return }
$WorkRoot = Join-Path $ProjectDir 'work'
$VerifyRoot = Join-Path $WorkRoot ("backup-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $VerifyRoot | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [IO.Compression.ZipFile]::OpenRead($Latest.FullName)
    try {
        $Names = @($Archive.Entries.FullName)
        if (-not ($Names -match '^Saved[\\/]SaveGames[\\/].+[\\/]Level\.sav$')) { throw 'Level.sav is missing.' }
        if (-not ($Names -match '^Saved[\\/]SaveGames[\\/].+[\\/]LevelMeta\.sav$')) { throw 'LevelMeta.sav is missing.' }
        foreach ($Entry in $Archive.Entries) {
            if (-not ($Entry.FullName.EndsWith('/') -or $Entry.FullName.EndsWith('\'))) {
                $Stream = $Entry.Open()
                try {
                    $Buffer = New-Object byte[] 65536
                    while ($Stream.Read($Buffer, 0, $Buffer.Length) -gt 0) {}
                } finally { $Stream.Dispose() }
            }
        }
    } finally { $Archive.Dispose() }
    Expand-Archive -LiteralPath $Latest.FullName -DestinationPath $VerifyRoot
    $RestoredSaveRoot = Join-Path $VerifyRoot 'Saved\SaveGames'
    $RestoredLevels = @(Get-ChildItem -LiteralPath $RestoredSaveRoot -Filter 'Level.sav' -File -Recurse -ErrorAction SilentlyContinue)
    $RestoredMetadata = @(Get-ChildItem -LiteralPath $RestoredSaveRoot -Filter 'LevelMeta.sav' -File -Recurse -ErrorAction SilentlyContinue)
    if ($RestoredLevels.Count -eq 0 -or $RestoredMetadata.Count -eq 0) { throw 'Extracted save files are incomplete.' }
    Set-Content -LiteralPath $StampPath -Value $Latest.Name -Encoding Ascii
    Write-Host "Backup restore-readiness verified: $($Latest.Name)"
}
catch {
    Invoke-DiscordNotificationSafe -Type BackupFailure -Message "Backup verification failed for $($Latest.Name): $($_.Exception.Message)"
    throw
}
finally {
    if (Test-Path -LiteralPath $VerifyRoot) {
        $ResolvedWork = (Resolve-Path -LiteralPath $WorkRoot).Path
        $ResolvedVerify = (Resolve-Path -LiteralPath $VerifyRoot).Path
        if ($ResolvedVerify.StartsWith($ResolvedWork + [IO.Path]::DirectorySeparatorChar)) {
            Remove-Item -LiteralPath $ResolvedVerify -Recurse -Force
        }
    }
}
