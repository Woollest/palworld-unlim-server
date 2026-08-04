$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OriginalLocation = (Get-Location).Path
Set-Location -LiteralPath $ProjectRoot

$TempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$Checkout = Join-Path $TempRoot ("palworldserver-clean-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Checkout | Out-Null

try {
    $Files = @(& git ls-files --cached --others --exclude-standard)
    if ($Files.Count -eq 0) { throw 'No public repository files were found.' }
    foreach ($RelativePath in $Files) {
        $Source = Join-Path $ProjectRoot $RelativePath
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { continue }
        $Destination = Join-Path $Checkout $RelativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination
    }

    & git -C $Checkout init --initial-branch=main | Out-Null
    & (Join-Path $Checkout 'scripts/setup-project.ps1') -SkipDockerValidation
    if ($LASTEXITCODE -ne 0) { throw 'First-time setup failed in the clean checkout.' }
    & (Join-Path $Checkout 'scripts/test-project.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Repository checks failed in the clean checkout.' }

    foreach ($Expected in @('.env', 'config/discord.env', 'data/Saved/Config/LinuxServer/PalWorldSettings.ini')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Checkout $Expected))) { throw "Setup did not create: $Expected" }
    }
    Write-Host 'Clean-checkout setup test passed.' -ForegroundColor Green
}
finally {
    Set-Location -LiteralPath $OriginalLocation
    $ResolvedCheckout = [IO.Path]::GetFullPath($Checkout)
    if ($ResolvedCheckout.StartsWith($TempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $ResolvedCheckout) -like 'palworldserver-clean-*') {
        Remove-Item -LiteralPath $ResolvedCheckout -Recurse -Force -ErrorAction SilentlyContinue
    }
}
