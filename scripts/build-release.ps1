param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir

$SafeVersion = $Version.TrimStart('v')
$PackageName = "palworld-unlim-server-$SafeVersion"
$WorkRoot = Join-Path $ProjectDir 'work'
$PackageRoot = Join-Path $WorkRoot $PackageName
$DistRoot = Join-Path $ProjectDir 'dist'
$ArchivePath = Join-Path $DistRoot "$PackageName.zip"
$ChecksumPath = "$ArchivePath.sha256"
New-Item -ItemType Directory -Force -Path $WorkRoot, $DistRoot | Out-Null

try {
    if (Test-Path -LiteralPath $PackageRoot) { Remove-Item -LiteralPath $PackageRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $PackageRoot | Out-Null

    $Files = @(& git ls-files)
    if ($Files.Count -eq 0) { $Files = @(& git ls-files --others --exclude-standard) }
    if ($Files.Count -eq 0) { throw 'No public files are available for packaging.' }

    foreach ($RelativePath in $Files) {
        if ($RelativePath -like '.github/*' -or $RelativePath -like 'tests/*') { continue }
        $Source = Join-Path $ProjectDir $RelativePath
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { continue }
        $Destination = Join-Path $PackageRoot $RelativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination
    }

    if (Test-Path -LiteralPath $ArchivePath) { Remove-Item -LiteralPath $ArchivePath -Force }
    if (Test-Path -LiteralPath $ChecksumPath) { Remove-Item -LiteralPath $ChecksumPath -Force }
    Compress-Archive -LiteralPath $PackageRoot -DestinationPath $ArchivePath -CompressionLevel Optimal
    if (-not (Test-Path -LiteralPath $ArchivePath) -or (Get-Item -LiteralPath $ArchivePath).Length -eq 0) { throw 'Release archive was not created.' }

    $Hash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $ChecksumPath -Value "$Hash  $([IO.Path]::GetFileName($ArchivePath))" -Encoding Ascii
    Write-Host "Release archive: $ArchivePath"
    Write-Host "SHA-256: $Hash"
}
finally {
    $ResolvedWork = [IO.Path]::GetFullPath($WorkRoot)
    $ResolvedPackage = [IO.Path]::GetFullPath($PackageRoot)
    if ($ResolvedPackage.StartsWith($ResolvedWork, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $ResolvedPackage) -eq $PackageName) {
        Remove-Item -LiteralPath $ResolvedPackage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
